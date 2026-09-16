import 'package:artificer_core/src/errors.dart';
import 'package:artificer_core/src/generation/generation.dart';
import 'package:artificer_core/src/models.dart';
import 'package:artificer_core/src/native.dart';
import 'package:artificer_core/src/protocols/responses/responses_codec.dart';
import 'package:artificer_core/src/protocols/responses/responses_models.dart';
import 'package:artificer_core/src/protocols/responses/responses_stream.dart';
import 'package:artificer_core/src/tools/tools.dart';
import 'package:artificer_core/src/transport/provider_http_client.dart';
import 'package:conflux/effect.dart';
import 'package:conflux/flow.dart';

/// A borrowed compatible Responses model with no runtime or conversation state.
final class CompatibleResponsesModel implements LanguageModel {
  /// Creates a lazy model handle; dialect routing and authentication are explicit.
  CompatibleResponsesModel({
    required this.modelId,
    required this.client,
    required this.codec,
    this.capabilities = const ModelCapabilities(),
    this.defaults = const GenerationOptions(),
    this.nativeDefaults = const ResponsesOptions(),
    this.eventCapacity = 16,
    this.maxEventBytes = 8 * 1024 * 1024,
    this.maxResponseBytes = 64 * 1024 * 1024,
  }) {
    if (modelId.isEmpty || codec.dialect.providerId.isEmpty) {
      throw ArgumentError('Provider and model IDs must be nonempty.');
    }
    if (eventCapacity <= 0 || maxEventBytes <= 0 || maxResponseBytes <= 0) {
      throw ArgumentError('Stream limits must be positive.');
    }
  }
  @override
  final String modelId;
  @override
  String get providerId => codec.dialect.providerId;
  @override
  final ModelCapabilities capabilities;

  /// Provider-owned transport borrowed by this handle.
  final ProviderHttpClient client;

  /// Pure endpoint conversion and provider policy hooks.
  final ResponsesCodec codec;

  /// Common model defaults; per-call Setting overrides resolve at execution.
  final GenerationOptions defaults;

  /// Provider-only defaults, with whole-collection replacement semantics.
  final ResponsesOptions nativeDefaults;

  /// Bounded decoded SSE capacity with upstream backpressure.
  final int eventCapacity;

  /// Independent byte limit for each SSE frame.
  final int maxEventBytes;

  /// Combined assembled response byte limit.
  final int maxResponseBytes;

  @override
  Effect<GenerationResult, AiError> generate(
    GenerationRequest request, {
    ResponsesOptions options = const ResponsesOptions(),
  }) => client.observe(
    rawGenerate(request, options: options).flatMap(
      (response, _) => Effect.fromResult(
        codec.normalize(response.value, response.raw, metadata: response.metadata),
      ),
    ),
    providerId: providerId,
    api: codec.dialect.api,
    modelId: modelId,
    usage: (result) => result.usage,
    verdict: (result) => result.finishReason,
  );

  /// Executes the common request once and returns both native views.
  Effect<NativeResponse<ResponsesResponse>, AiError> rawGenerate(
    GenerationRequest request, {
    ResponsesOptions options = const ResponsesOptions(),
  }) => Effect.build(($) async {
    final unsupported = _unsupported(request, streaming: false, options: options);
    if (unsupported != null) return $(Effect.fail(unsupported));
    final native = $.sync(
      codec.encode(
        request,
        modelId,
        defaults: defaults,
        options: options,
        nativeDefaults: nativeDefaults,
      ),
    );
    return $(create(native));
  });

  /// Native foreground text inference using the same transport and decoder.
  Effect<NativeResponse<ResponsesResponse>, AiError> create(ResponsesRequest request) =>
      client.observe(
        Effect.build<NativeResponse<ResponsesResponse>, AiError>(($) async {
          final body = $.sync(codec.prepare(request));
          final response = await $(
            client.requestJson(
              url: codec.dialect.route(request.model),
              headers: codec.dialect.authentication(),
              body: body,
            ),
          );
          if (response.data is! Map<String, Object?>) {
            return $(Effect.fail(const ProtocolError('Responses response must be an object.')));
          }
          final data = response.data! as Map<String, Object?>;
          final value = $.sync(codec.decode(data, metadata: response.metadata));
          return NativeResponse(
            value: value,
            raw: NativePayload(
              providerId: providerId,
              api: codec.dialect.api,
              modelId: request.model,
              data: data,
            ),
            metadata: response.metadata,
          );
        }).catchError((error, _) => Effect.fail(_nativeError(error))),
        providerId: providerId,
        api: codec.dialect.api,
        modelId: request.model,
        usage: (raw) {
          final native = raw.value.usage;
          if (native == null) return null;
          return Usage(
            inputTokens: native['input_tokens'] is int ? native['input_tokens']! as int : null,
            outputTokens: native['output_tokens'] is int ? native['output_tokens']! as int : null,
            totalTokens: native['total_tokens'] is int ? native['total_tokens']! as int : null,
          );
        },
      );

  @override
  Flow<GenerationEvent, AiError> stream(
    GenerationRequest request, {
    ResponsesOptions options = const ResponsesOptions(),
  }) => Flow.defer((_) {
    final unsupported = _unsupported(request, streaming: true, options: options);
    if (unsupported != null) return Effect.fail<GenerationEvent, AiError>(unsupported).asFlow();
    return Effect.fromResult(
      codec.encode(
        request,
        modelId,
        defaults: defaults,
        options: options,
        nativeDefaults: nativeDefaults,
      ),
    ).asFlow().concatMap((native, _) => streamNative(native));
  });

  /// Streams an explicit native request with common typed events and native replay.
  /// Every consumption opens one attempt; final output follows transport cleanup.
  Flow<GenerationEvent, AiError> streamNative(ResponsesRequest request) => client.observeFlow(
    Flow.defer((_) {
      final state = ResponsesStreamDecoder(
        codec: codec,
        modelId: request.model,
        maxResponseBytes: maxResponseBytes,
      );
      final flow = Effect.fromResult(codec.prepare(request, stream: true))
          .asFlow()
          .concatMap(
            (body, _) => client.withSse<GenerationEvent>(
              url: codec.dialect.route(request.model),
              headers: codec.dialect.authentication(),
              body: body,
              eventCapacity: eventCapacity,
              maxEventBytes: maxEventBytes,
              consume: (metadata, events) {
                state.metadata = metadata;
                return Effect.fromResult(state.start()).asFlow().concat(
                  events.concatMap(
                    (event, _) => Effect.fromResult(state.add(event))
                        .asFlow()
                        .concatMap((events, _) => Flow.fromIterable(events).widenError<AiError>()),
                  ),
                );
              },
            ),
          )
          .catchError(
            (error, _) =>
                Effect.fail<GenerationEvent, AiError>(state.withPartial(_nativeError(error)))
                    .asFlow(),
          );
      return flow.concat(
        Effect.defer<GenerationEvent, AiError>((_) => Effect.fromResult(state.complete())).asFlow(),
      );
    }),
    providerId: providerId,
    api: codec.dialect.api,
    modelId: request.model,
  );

  AiError? _unsupported(
    GenerationRequest request, {
    required bool streaming,
    required ResponsesOptions options,
  }) => capabilities.validateRequested([
    ModelCapability.textGeneration,
    if (streaming) ModelCapability.streaming,
    if (request.tools.isNotEmpty ||
        request.toolChoice is! AutoToolChoice ||
        (options.nativeTools.resolve(nativeDefaults.nativeTools.resolve(const []))?.isNotEmpty ??
            false))
      ModelCapability.tools,
    if (request.output is! TextOutput) ModelCapability.structuredOutput,
  ]);

  AiError _nativeError(AiError error) {
    if (error is! ProviderError || error.details is! Map<String, Object?>) return error;
    final mapped = codec.errorFrom(
      error.details! as Map<String, Object?>,
      metadata: ResponseMetadata(statusCode: error.statusCode ?? 0, requestId: error.requestId),
    );
    if (mapped == null) return error;
    return ProviderError(
      mapped.message,
      code: mapped.code ?? error.code,
      details: error.details,
      statusCode: error.statusCode,
      requestId: error.requestId,
      retryAfter: error.retryAfter,
      partialOutput: error.partialOutput ?? mapped.partialOutput,
    );
  }
}
