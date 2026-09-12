import 'dart:convert';

import 'package:artificer_core/artificer_core.dart';
import 'package:artificer_core/json.dart';
import 'package:artificer_core/transport.dart';
import 'package:artificer_xai/src/chat/chat_completions_resource.dart';
import 'package:artificer_xai/src/embeddings/embedding_models.dart';
import 'package:artificer_xai/src/embeddings/embeddings_resource.dart';
import 'package:artificer_xai/src/files/files_resource.dart';
import 'package:artificer_xai/src/models/models_resource.dart';
import 'package:artificer_xai/src/options.dart';
import 'package:artificer_xai/src/responses/response_models.dart';
import 'package:artificer_xai/src/responses/responses_resource.dart';
import 'package:conflux/conflux.dart';
import 'package:http/http.dart' as http;

const _providerId = 'xai';
const _responsesApi = 'responses';

/// An Xai client with common models and typed native resources.
final class XaiProvider {
  /// Creates an explicit-credential Xai client.
  XaiProvider({
    required String apiKey,
    Uri? baseUrl,
    http.Client? httpClient,
  }) : _client = ProviderHttpClient(
         baseUrl: baseUrl ?? Uri.parse('https://api.x.ai/v1/'),
         client: httpClient,
         headers: {
           'authorization': 'Bearer ${_nonEmpty(apiKey, 'apiKey')}',
         },
       ) {
    chatCompletions = XaiChatCompletionsResource(_client);
    embeddings = XaiEmbeddingsResource(_client);
    files = XaiFilesResource(_client);
    models = XaiModelsResource(_client);
    responses = XaiResponsesResource(_client);
  }

  final ProviderHttpClient _client;

  /// Typed native Chat Completions operations.
  late final XaiChatCompletionsResource chatCompletions;

  /// Typed native embedding operations.
  late final XaiEmbeddingsResource embeddings;

  /// Explicit caller-managed file operations.
  late final XaiFilesResource files;

  /// Typed native model discovery operations.
  late final XaiModelsResource models;

  /// Typed native Responses operations.
  late final XaiResponsesResource responses;

  /// Creates a common language model backed by the Responses API.
  XaiLanguageModel languageModel(String modelId, {XaiModelOptions? options}) => XaiLanguageModel._(
    responses,
    _nonEmpty(modelId, 'modelId'),
    options ?? XaiModelOptions(),
  );

  /// Creates a common synchronous text embedding model.
  XaiEmbeddingModel embeddingModel(String modelId, {XaiEmbeddingOptions? options}) =>
      XaiEmbeddingModel(
        embeddings,
        _nonEmpty(modelId, 'modelId'),
        options ?? XaiEmbeddingOptions(),
      );

  /// Interrupts this provider's work and releases its owned HTTP client.
  Future<void> close() => _client.close();
}

/// An Xai Responses adapter for the common language-model contract.
final class XaiLanguageModel implements LanguageModel {
  XaiLanguageModel._(this._responses, this.modelId, this.options);

  final XaiResponsesResource _responses;

  /// Immutable model defaults.
  final XaiModelOptions options;

  @override
  final String modelId;

  @override
  String get providerId => _providerId;

  @override
  ModelCapabilities get capabilities => ModelCapabilities({
    ModelCapability.textGeneration: CapabilitySupport.supported,
    ModelCapability.streaming: CapabilitySupport.supported,
    ModelCapability.tools: CapabilitySupport.unknown,
    ModelCapability.structuredOutput: CapabilitySupport.unknown,
    ModelCapability.imageInput: CapabilitySupport.unknown,
    ModelCapability.audioInput: CapabilitySupport.unsupported,
    ModelCapability.videoInput: CapabilitySupport.unsupported,
    ModelCapability.documentInput: CapabilitySupport.unknown,
  });

  @override
  Effect<GenerationResult, AiError> generate(
    GenerationRequest request, {
    XaiModelOptions? options,
  }) {
    final native = _encodeCommon(request, options, stream: false);
    return switch (native) {
      AiError() => Effect.fail(native),
      XaiResponseRequest() =>
        _responses.create(native).map((value, _) => _responses.normalize(value)),
      _ => throw StateError('Unexpected common request encoding result.'),
    };
  }

  @override
  Flow<GenerationEvent, AiError> stream(
    GenerationRequest request, {
    XaiModelOptions? options,
  }) {
    final native = _encodeCommon(request, options, stream: true);
    return switch (native) {
      AiError() => Effect.fail<GenerationEvent, AiError>(native).asFlow(),
      XaiResponseRequest() => _responses.streamCommon(native),
      _ => throw StateError('Unexpected common request encoding result.'),
    };
  }

  Object _encodeCommon(
    GenerationRequest request,
    XaiModelOptions? callOptions, {
    required bool stream,
  }) {
    final replayError = request.validateReplayTarget(
      providerId: providerId,
      api: _responsesApi,
      modelId: modelId,
    );
    if (replayError != null) return replayError;
    if (request.options.stopSequences.isNotEmpty) {
      return const UnsupportedFeatureError('Xai Responses does not support stop sequences.');
    }
    final input = <XaiResponseInputItem>[];
    final calls = <String, ApplicationToolCallPart>{};
    for (final message in request.messages) {
      if (message case UserMessage(:final parts)) {
        final content = <XaiResponseInputPart>[];
        for (final part in parts) {
          final encoded = _encodeInputPart(part);
          if (encoded is AiError) return encoded;
          content.add(encoded as XaiResponseInputPart);
        }
        input.add(
          XaiResponseInputMessage(
            role: XaiResponseInputRole.user,
            content: content,
          ),
        );
      } else if (message case AssistantMessage(:final parts, :final replay)) {
        for (final call in parts.whereType<ApplicationToolCallPart>()) {
          calls[call.id] = call;
        }
        if (replay != null) {
          input.addAll(
            replay.items
                .where((item) => item.phase != 'unknown-event')
                .map((item) => XaiRawResponseInputItem(item.data)),
          );
          continue;
        }
        if (parts.any((part) => part is! TextOutputPart)) {
          return const UnsupportedFeatureError(
            'Edited assistant history supports portable text only.',
          );
        }
        final textParts = parts.cast<TextOutputPart>();
        if (textParts.isEmpty || textParts.any((part) => part.text.isEmpty)) {
          return const UnsupportedFeatureError(
            'Edited assistant history requires nonempty portable text.',
          );
        }
        input.add(
          XaiResponseInputMessage(
            role: XaiResponseInputRole.assistant,
            content: [
              for (final part in textParts) XaiTextInputPart(part.text),
            ],
          ),
        );
      } else if (message case ToolMessage(:final results)) {
        for (final result in results) {
          final call = calls[result.callId];
          if (call == null) {
            return InvalidRequestError('Tool result ${result.callId} references a missing call.');
          }
          final encoded = _encodeToolResult(result, call);
          if (encoded is AiError) return encoded;
          input.add(encoded as XaiResponseInputItem);
        }
      }
    }
    final applicationTools = [
      for (final tool in request.tools)
        XaiFunctionTool(
          functionName: tool.name,
          description: tool.description,
          parameters: tool.inputSchema,
          strict: false,
        ),
    ];
    final nativeTools = options.resolveTools(callOptions) ?? const <XaiToolDefinition>[];
    final names = applicationTools.map((tool) => tool.name).whereType<String>().toSet();
    final collision = nativeTools
        .map((tool) => tool.name)
        .whereType<String>()
        .where(names.contains)
        .firstOrNull;
    if (collision != null) {
      return InvalidRequestError('Native and application tools both declare $collision.');
    }
    final reasoning = options.resolveReasoning(callOptions);
    final include = {
      XaiResponseInclude.reasoningEncryptedContent,
      ...?options.resolveInclude(callOptions),
    };
    final serviceTier = options.resolveServiceTier(callOptions);
    final extraBody = JsonObject({
      ...options.extraBody.toDart(),
      ...?callOptions?.extraBody.toDart(),
    });
    final reserved = extraBody.toDart().keys.where(_commonResponseFields.contains).firstOrNull;
    if (reserved != null) {
      return InvalidRequestError('extraBody field $reserved conflicts with common generation.');
    }
    return XaiResponseRequest(
      model: modelId,
      input: input,
      instructions: request.instructions,
      maxOutputTokens: request.options.maxOutputTokens,
      temperature: request.options.temperature,
      topP: request.options.topP,
      store: false,
      stream: stream,
      reasoning: reasoning?.toJson(),
      promptCacheKey: options.resolvePromptCacheKey(callOptions),
      serviceTier: serviceTier?.wireValue,
      inference: options.resolveInference(callOptions),
      include: include.map((value) => value.wireValue),
      tools: applicationTools.isEmpty && nativeTools.isEmpty
          ? null
          : [...applicationTools, ...nativeTools],
      toolChoice:
          applicationTools.isEmpty && nativeTools.isEmpty && request.toolChoice is AutoToolChoice
          ? null
          : _encodeToolChoice(request.toolChoice),
      text: request.output is TextOutputFormat ? null : _encodeOutput(request.output),
      extraBody: extraBody,
    );
  }

  Object _encodeInputPart(InputPart part) => switch (part) {
    TextInputPart(:final text) => XaiTextInputPart(text),
    MediaInputPart(:final kind, :final mimeType, :final source) => switch (kind) {
      MediaKind.image => switch (source) {
        BytesMediaSource(:final bytes) => XaiImageInputPart(
          imageUrl: 'data:$mimeType;base64,${base64Encode(bytes)}',
        ),
        UrlMediaSource(:final url) => XaiImageInputPart(imageUrl: url.toString()),
        ProviderFileSource() => const UnsupportedFeatureError(
          'Xai image input supports URL and inline byte sources.',
        ),
      },
      MediaKind.document => switch (source) {
        ProviderFileSource(:final providerId, :final api, :final reference)
            when providerId == _providerId && api == _responsesApi =>
          XaiFileInputPart(reference),
        _ => const UnsupportedFeatureError(
          'Xai document input requires an explicit Xai file ID.',
        ),
      },
      MediaKind.audio => const UnsupportedFeatureError(
        'Audio input is unavailable in the pinned Xai Responses schema.',
      ),
      MediaKind.video => const UnsupportedFeatureError(
        'Video input is unavailable in the pinned Xai Responses schema.',
      ),
    },
  };

  JsonValue _encodeToolChoice(ToolChoice choice) => JsonValue.fromDart(switch (choice) {
    AutoToolChoice() => 'auto',
    NoToolChoice() => 'none',
    RequiredToolChoice() => 'required',
    FunctionToolChoice(:final name) => {'type': 'function', 'name': name},
  });

  JsonObject _encodeOutput(OutputFormat output) => JsonObject({
    'format': switch (output) {
      TextOutputFormat() => {'type': 'text'},
      JsonObjectOutputFormat() => {'type': 'json_object'},
      JsonSchemaOutputFormat(:final name, :final description, :final schema) => {
        'type': 'json_schema',
        'name': name,
        'description': ?description,
        'schema': schema.toDart(),
        'strict': true,
      },
    },
  });

  Object _encodeToolResult(ToolResult result, ApplicationToolCallPart call) {
    if (call.arguments case NativeToolArguments()) {
      if (result is! NativeToolResult) {
        return UnsupportedFeatureError(
          'Xai native tool call ${call.id} requires a provider-native result.',
        );
      }
      final type = switch (call.name) {
        'computer' => 'computer_call_output',
        'shell' => 'shell_call_output',
        'apply_patch' => 'apply_patch_call_output',
        _ => null,
      };
      if (type == null) {
        return UnsupportedFeatureError('Xai native tool ${call.name} has no output mapping.');
      }
      return XaiRawResponseInputItem(
        JsonObject({...result.value.toDart(), 'type': type, 'call_id': result.callId}),
      );
    }

    final output = _encodePortableToolOutput(result);
    if (output is AiError) return output;
    final type = call.arguments is TextToolArguments
        ? 'custom_tool_call_output'
        : 'function_call_output';
    return XaiRawResponseInputItem(
      JsonObject({'type': type, 'call_id': result.callId, 'output': output}),
    );
  }

  Object _encodePortableToolOutput(ToolResult result) => switch (result) {
    JsonToolResult(:final value) => jsonEncode(value.toDart()),
    TextToolResult(:final content) => _encodeToolContent(content),
    NativeToolResult() => const UnsupportedFeatureError(
      'A provider-native result requires a provider-native tool call.',
    ),
    ApplicationErrorToolResult(:final message, :final details) => jsonEncode({
      'error': message,
      if (details != null) 'details': details.toDart(),
    }),
  };

  Object _encodeToolContent(List<InputPart> content) {
    final encoded = <Map<String, Object?>>[];
    for (final part in content) {
      final value = _encodeInputPart(part);
      if (value is AiError) return value;
      encoded.add((value as XaiResponseInputPart).toDart());
    }
    return encoded;
  }
}

String _nonEmpty(String value, String name) {
  if (value.isEmpty) throw ArgumentError.value(value, name, 'must not be empty');
  return value;
}

const _commonResponseFields = {
  'model',
  'input',
  'instructions',
  'max_output_tokens',
  'temperature',
  'top_p',
  'store',
  'stream',
  'reasoning',
  'prompt_cache_key',
  'prompt_cache_retention',
  'service_tier',
  'include',
  'tools',
  'tool_choice',
  'text',
  'previous_response_id',
  'background',
};
