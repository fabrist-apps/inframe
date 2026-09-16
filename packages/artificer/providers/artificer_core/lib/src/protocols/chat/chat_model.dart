import 'package:artificer_core/src/errors.dart';
import 'package:artificer_core/src/generation/generation.dart';
import 'package:artificer_core/src/models.dart';
import 'package:artificer_core/src/native.dart';
import 'package:artificer_core/src/observations.dart';
import 'package:artificer_core/src/protocols/chat/chat_codec.dart';
import 'package:artificer_core/src/protocols/chat/chat_dialect.dart';
import 'package:artificer_core/src/protocols/chat/chat_models.dart';
import 'package:artificer_core/src/protocols/chat/chat_stream.dart';
import 'package:artificer_core/src/tools/tools.dart';
import 'package:artificer_core/src/transport/provider_http_client.dart';
import 'package:conflux/effect.dart';
import 'package:conflux/flow.dart';
import 'package:dio/dio.dart';

/// A configured compatible Chat provider with one owned or borrowed Dio client.
final class ChatProvider implements LanguageModelProvider {
  /// Configures routing and defaults without network work.
  ChatProvider({
    required this.dialect,
    Dio? dio,
    ProviderObserver? observer,
    this.generationDefaults = const GenerationOptions(),
    this.defaultOptions = const ChatOptions(),
    this.capabilities = const ModelCapabilities(),
  }) : client = ProviderHttpClient(dio: dio, observer: observer);

  /// Provider-owned identity, credentials and dialect hooks.
  final ChatDialect dialect;

  /// Common defaults inherited by model requests.
  final GenerationOptions generationDefaults;

  /// Native option defaults; collections replace rather than concatenate.
  final ChatOptions defaultOptions;

  /// Declared capabilities, unknown unless explicitly configured.
  final ModelCapabilities capabilities;

  /// The single transport owner; model handles only borrow it.
  final ProviderHttpClient client;
  @override
  ChatLanguageModel languageModel(String modelId) => ChatLanguageModel(
    client: client,
    dialect: dialect,
    modelId: modelId,
    generationDefaults: generationDefaults,
    defaultOptions: defaultOptions,
    capabilities: capabilities,
  );

  /// Closes only this provider's work and owned connection pool.
  Future<void> close() => client.close();

  /// Lazy scoped ownership cleanup.
  Effect<void, Never> closeEffect() => client.closeEffect();
}

/// A compatible Chat model borrowing a provider's transport owner.
final class ChatLanguageModel implements LanguageModel {
  /// Creates a cold model handle for an open provider-local model identity.
  ChatLanguageModel({
    required this.client,
    required this.dialect,
    required this.modelId,
    this.generationDefaults = const GenerationOptions(),
    this.defaultOptions = const ChatOptions(),
    this.capabilities = const ModelCapabilities(),
  }) : codec = ChatCodec(dialect) {
    if (modelId.isEmpty) throw ArgumentError.value(modelId, 'modelId');
  }

  /// Borrowed transport; closing a model never closes its provider.
  final ProviderHttpClient client;

  /// Provider configuration used for native and common calls alike.
  final ChatDialect dialect;

  /// Authoritative pure request/response conversion.
  final ChatCodec codec;

  /// Inherited common settings.
  final GenerationOptions generationDefaults;

  /// Inherited native settings.
  final ChatOptions defaultOptions;
  @override
  final String modelId;
  @override
  String get providerId => dialect.providerId;
  @override
  final ModelCapabilities capabilities;

  @override
  Effect<GenerationResult, AiError> generate(
    GenerationRequest request, {
    ChatOptions options = const ChatOptions(),
  }) => client.observe(
    rawGenerate(
      request,
      options: options,
    ).flatMap((response, _) => Effect.fromResult(codec.normalize(response))),
    providerId: providerId,
    api: dialect.api,
    modelId: modelId,
    usage: (result) => result.usage,
    verdict: (result) => result.finishReason,
  );

  /// Performs one common request and returns its typed and complete native views.
  Effect<NativeResponse<ChatResponse>, AiError> rawGenerate(
    GenerationRequest request, {
    ChatOptions options = const ChatOptions(),
  }) => Effect.defer((_) {
    final unsupported = _unsupported(request, stream: false);
    if (unsupported != null) return Effect.fail(unsupported);
    return Effect.fromResult(
      codec.request(
        modelId,
        request,
        defaults: generationDefaults,
        options: options,
        optionDefaults: defaultOptions,
      ),
    ).flatMap((body, _) => _execute(body));
  });

  /// Executes native request shapes through the identical one-attempt transport.
  Effect<NativeResponse<ChatResponse>, AiError> native(NativeChatRequest request) => Effect.defer(
    (_) => Effect.fromResult(codec.nativeRequest(request)).flatMap((body, _) => _execute(body)),
  );

  Effect<NativeResponse<ChatResponse>, AiError> _execute(Map<String, Object?> body) =>
      client.observe(
        client
            .requestJson(url: dialect.endpoint, headers: dialect.headers, body: body)
            .catchError((error, _) => Effect.fail(_serviceError(error)))
            .flatMap(
              (response, _) => Effect.fromResult(codec.decode(response.data, response.metadata)),
            ),
        providerId: providerId,
        api: dialect.api,
        modelId: body['model']! as String,
        usage: (raw) => raw.value.usage,
      );

  AiError _serviceError(AiError error) {
    if (error is! ProviderError || error.details is! Map<String, Object?>) return error;
    final mapped = codec.error(
      error.details! as Map<String, Object?>,
      ResponseMetadata(statusCode: error.statusCode ?? 500, requestId: error.requestId),
    );
    if (mapped is ProviderError) {
      return ProviderError(
        mapped.message,
        statusCode: mapped.statusCode ?? error.statusCode,
        code: mapped.code ?? error.code,
        details: mapped.details ?? error.details,
        requestId: mapped.requestId ?? error.requestId,
        retryAfter: mapped.retryAfter ?? error.retryAfter,
        partialOutput: mapped.partialOutput ?? error.partialOutput,
      );
    }
    return mapped ?? error;
  }

  @override
  Flow<GenerationEvent, AiError> stream(
    GenerationRequest request, {
    ChatOptions options = const ChatOptions(),
    int eventCapacity = 16,
    int maxEventBytes = 8 * 1024 * 1024,
    int maxResponseBytes = 64 * 1024 * 1024,
  }) {
    _checkLimits(eventCapacity, maxEventBytes, maxResponseBytes);
    return Flow.defer((_) {
      final unsupported = _unsupported(request, stream: true);
      if (unsupported != null) return Flow.fail(unsupported);
      final body = codec.request(
        modelId,
        request,
        defaults: generationDefaults,
        options: options,
        optionDefaults: defaultOptions,
        stream: true,
      );
      return Effect.fromResult(body).asFlow().concatMap(
        (native, _) => _stream(
          native,
          modelId,
          eventCapacity: eventCapacity,
          maxEventBytes: maxEventBytes,
          maxResponseBytes: maxResponseBytes,
        ),
      );
    });
  }

  /// Streams an explicitly selected candidate of a native Chat request.
  /// Multiple requested candidates require [choiceIndex] before I/O.
  Flow<GenerationEvent, AiError> streamNative(
    NativeChatRequest request, {
    int? choiceIndex,
    int eventCapacity = 16,
    int maxEventBytes = 8 * 1024 * 1024,
    int maxResponseBytes = 64 * 1024 * 1024,
  }) {
    _checkLimits(eventCapacity, maxEventBytes, maxResponseBytes);
    return Flow.defer((_) {
      if ((request.n ?? 1) > 1 && choiceIndex == null) {
        return Flow.fail(
          const InvalidRequestError('Native multi-candidate streams require selection.'),
        );
      }
      if (choiceIndex != null && (choiceIndex < 0 || choiceIndex >= (request.n ?? 1))) {
        return Flow.fail(const InvalidRequestError('Native selected candidate is out of range.'));
      }
      return Effect.fromResult(codec.nativeRequest(request, stream: true)).asFlow().concatMap(
        (body, _) => _stream(
          body,
          request.model,
          choiceIndex: choiceIndex ?? 0,
          eventCapacity: eventCapacity,
          maxEventBytes: maxEventBytes,
          maxResponseBytes: maxResponseBytes,
        ),
      );
    });
  }

  Flow<GenerationEvent, AiError> _stream(
    Map<String, Object?> body,
    String model, {
    required int eventCapacity,
    required int maxEventBytes,
    required int maxResponseBytes,
    int choiceIndex = 0,
  }) {
    final state = ChatStreamAssembly(
      codec,
      model,
      choiceIndex: choiceIndex,
      maxResponseBytes: maxResponseBytes,
    );
    final transport = client.withSse<GenerationEvent>(
      url: dialect.endpoint,
      headers: dialect.headers,
      body: body,
      eventCapacity: eventCapacity,
      maxEventBytes: maxEventBytes,
      consume: (metadata, events) => Effect.fromResult(state.start(metadata)).asFlow().concat(
        events
            .mapEffect((frame, _) => Effect.fromResult(state.accept(frame)))
            .takeWhile((_, _) => !state.terminal)
            .concatMap((events, _) => Flow.fromIterable(events).widenError<AiError>())
            .concat(
              Effect.defer((_) => Effect.fromResult(state.finishParts()))
                  .asFlow()
                  .concatMap((events, _) => Flow.fromIterable(events).widenError<AiError>()),
            ),
      ),
    );
    return client.observeFlow(
      transport
          .concat(
            Effect.defer<GenerationEvent, AiError>((_) => Effect.fromResult(state.complete()))
                .asFlow(),
          )
          .mapError((error, _) => state.withPartial(_serviceError(error))),
      providerId: providerId,
      api: dialect.api,
      modelId: model,
    );
  }

  void _checkLimits(int eventCapacity, int maxEventBytes, int maxResponseBytes) {
    if (eventCapacity <= 0) throw ArgumentError.value(eventCapacity, 'eventCapacity');
    if (maxEventBytes <= 0) throw ArgumentError.value(maxEventBytes, 'maxEventBytes');
    if (maxResponseBytes <= 0) throw ArgumentError.value(maxResponseBytes, 'maxResponseBytes');
  }

  AiError? _unsupported(GenerationRequest request, {required bool stream}) =>
      capabilities.validateRequested([
        ModelCapability.textGeneration,
        if (stream) ModelCapability.streaming,
        if (request.tools.isNotEmpty) ModelCapability.tools,
        if (request.output is! TextOutput) ModelCapability.structuredOutput,
      ]);
}
