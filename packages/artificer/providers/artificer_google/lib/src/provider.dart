import 'package:artificer_core/artificer_core.dart';
import 'package:artificer_core/transport.dart';
import 'package:artificer_google/src/generate_content/generate_content_models.dart';
import 'package:artificer_google/src/generate_content/generate_content_resource.dart';
import 'package:artificer_google/src/models/models_resource.dart';
import 'package:artificer_google/src/options.dart';
import 'package:conflux/conflux.dart';
import 'package:http/http.dart' as http;

const _providerId = 'google';
const _api = 'generateContent';

/// A Gemini Developer API client with common and typed native operations.
final class GoogleProvider {
  /// Creates an explicit-credential Google client.
  GoogleProvider({required String apiKey, Uri? baseUrl, http.Client? httpClient})
    : _client = ProviderHttpClient(
        baseUrl: baseUrl ?? Uri.parse('https://generativelanguage.googleapis.com'),
        client: httpClient,
        headers: {'x-goog-api-key': _nonEmpty(apiKey, 'apiKey')},
      ) {
    generateContent = GoogleGenerateContentResource(_client);
    models = GoogleModelsResource(_client, generateContent);
  }

  final ProviderHttpClient _client;

  /// Typed native GenerateContent operations.
  late final GoogleGenerateContentResource generateContent;

  /// Typed native model discovery and model-bound operations.
  late final GoogleModelsResource models;

  /// Creates a common explicit-history language model without discovery.
  GoogleLanguageModel languageModel(String modelId, {GoogleModelOptions? options}) {
    if (modelId.isEmpty || modelId.startsWith('models/')) {
      throw ArgumentError.value(
        modelId,
        'modelId',
        'must be a nonempty bare provider model ID',
      );
    }
    return GoogleLanguageModel._(
      generateContent,
      modelId,
      options ?? GoogleModelOptions(),
    );
  }

  /// Interrupts this provider's work and releases its owned HTTP client.
  Future<void> close() => _client.close();
}

/// A GenerateContent adapter for the common language-model contract.
final class GoogleLanguageModel implements LanguageModel {
  GoogleLanguageModel._(this._resource, this.modelId, this.options);

  final GoogleGenerateContentResource _resource;

  /// Immutable model defaults.
  final GoogleModelOptions options;

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
    ModelCapability.audioInput: CapabilitySupport.unknown,
    ModelCapability.videoInput: CapabilitySupport.unknown,
    ModelCapability.documentInput: CapabilitySupport.unknown,
  });

  @override
  Effect<GenerationResult, AiError> generate(
    GenerationRequest request, {
    GoogleModelOptions? options,
  }) {
    final native = _encodeCommon(request, options);
    return switch (native) {
      AiError() => Effect.fail(native),
      GoogleGenerateContentRequest() => _resource.create(native).flatMap(_normalizeCommon),
      _ => throw StateError('Unexpected common Google request encoding result.'),
    };
  }

  Effect<GenerationResult, AiError> _normalizeCommon(
    NativeResponse<GoogleGenerateContentResponse> response,
  ) {
    try {
      return Effect.succeed(_resource.normalize(response));
    } on AiError catch (error) {
      return Effect.fail(error);
    }
  }

  @override
  Flow<GenerationEvent, AiError> stream(
    GenerationRequest request, {
    GoogleModelOptions? options,
  }) {
    final native = _encodeCommon(request, options);
    return switch (native) {
      AiError() => Effect.fail<GenerationEvent, AiError>(native).asFlow(),
      GoogleGenerateContentRequest() => _resource.streamCommon(native),
      _ => throw StateError('Unexpected common Google request encoding result.'),
    };
  }

  Object _encodeCommon(GenerationRequest request, GoogleModelOptions? callOptions) {
    final replayError = request.validateReplayTarget(
      providerId: providerId,
      api: _api,
      modelId: modelId,
    );
    if (replayError != null) return replayError;
    if (request.tools.isNotEmpty || request.toolChoice is! AutoToolChoice) {
      return const UnsupportedFeatureError(
        'Google tools are outside this text-generation slice.',
        feature: 'tools',
      );
    }
    if (request.output is! TextOutputFormat) {
      return const UnsupportedFeatureError(
        'Google structured output is outside this text-generation slice.',
        feature: 'structuredOutput',
      );
    }
    final contents = <GoogleContent>[];
    for (final message in request.messages) {
      switch (message) {
        case UserMessage(:final parts):
          final encoded = _encodeUserParts(parts);
          if (encoded is AiError) return encoded;
          contents.add(GoogleContent(role: 'user', parts: encoded as List<GooglePart>));
        case AssistantMessage(:final parts, :final replay):
          final replayContent = _replayContent(replay);
          if (replayContent != null) {
            contents.add(replayContent);
            continue;
          }
          if (parts.any((part) => part is! TextOutputPart)) {
            return const UnsupportedFeatureError(
              'Edited Google assistant history supports portable text only.',
            );
          }
          if (parts.isEmpty) {
            return const InvalidRequestError(
              'An assistant history turn must contain text in this slice.',
            );
          }
          contents.add(
            GoogleContent(
              role: 'model',
              parts: [for (final part in parts.cast<TextOutputPart>()) GooglePart.text(part.text)],
            ),
          );
        case ToolMessage():
          return const UnsupportedFeatureError(
            'Google tool-result history is outside this text-generation slice.',
            feature: 'tools',
          );
      }
    }
    final thinkingConfig = options.resolveThinkingConfig(callOptions);
    final safetySettings = options.resolveSafetySettings(callOptions);
    if (safetySettings != null) {
      final categories = <String>{};
      for (final setting in safetySettings) {
        if (!categories.add(setting.category)) {
          return InvalidRequestError(
            'Safety category ${setting.category} is configured more than once.',
          );
        }
      }
    }
    final cachedContent = options.resolveCachedContent(callOptions);
    if (cachedContent != null &&
        (!cachedContent.startsWith('cachedContents/') || cachedContent.length == 15)) {
      return const InvalidRequestError(
        'cachedContent must have the format cachedContents/{id}.',
      );
    }
    final extraBody = options.resolveExtraBody(callOptions);
    final reserved = extraBody.toDart().keys.where(_commonFields.contains).firstOrNull;
    if (reserved != null) {
      return InvalidRequestError('extraBody field $reserved conflicts with common generation.');
    }
    final instructions = request.instructions;
    if (instructions != null && instructions.isEmpty) {
      return const InvalidRequestError('instructions must not be empty when supplied.');
    }
    return GoogleGenerateContentRequest(
      model: 'models/$modelId',
      contents: contents,
      systemInstruction: instructions == null
          ? null
          : GoogleContent(parts: [GooglePart.text(instructions)]),
      generationConfig: GoogleGenerationConfig(
        candidateCount: 1,
        maxOutputTokens: request.options.maxOutputTokens,
        temperature: request.options.temperature,
        topP: request.options.topP,
        stopSequences: request.options.stopSequences.isEmpty ? null : request.options.stopSequences,
        thinkingConfig: thinkingConfig,
      ),
      safetySettings: safetySettings,
      cachedContent: cachedContent,
      extraBody: extraBody,
    );
  }

  Object _encodeUserParts(List<InputPart> parts) {
    final encoded = <GooglePart>[];
    for (final part in parts) {
      if (part case TextInputPart(:final text)) {
        encoded.add(GooglePart.text(text));
      } else {
        return const UnsupportedFeatureError(
          'Google media input is outside this text-generation slice.',
        );
      }
    }
    return encoded;
  }

  GoogleContent? _replayContent(ProviderReplay? replay) {
    if (replay == null) return null;
    for (final item in replay.items.reversed) {
      if (item.phase != 'candidate') continue;
      final candidate = GoogleCandidate.fromJson(item.data);
      return candidate.content;
    }
    return null;
  }
}

const _commonFields = {
  'contents',
  'systemInstruction',
  'generationConfig',
  'safetySettings',
  'cachedContent',
  'tools',
  'toolConfig',
};

String _nonEmpty(String value, String name) {
  if (value.isEmpty) throw ArgumentError.value(value, name, 'must not be empty');
  return value;
}
