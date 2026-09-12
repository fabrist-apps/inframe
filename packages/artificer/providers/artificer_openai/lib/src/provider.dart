import 'package:artificer_core/artificer_core.dart';
import 'package:artificer_core/transport.dart';
import 'package:artificer_openai/src/options.dart';
import 'package:artificer_openai/src/responses/response_models.dart';
import 'package:artificer_openai/src/responses/responses_resource.dart';
import 'package:conflux/conflux.dart';
import 'package:http/http.dart' as http;

const _providerId = 'openai';
const _responsesApi = 'responses';

/// An OpenAI client with common models and typed native resources.
final class OpenAIProvider {
  /// Creates an explicit-credential OpenAI client.
  OpenAIProvider({
    required String apiKey,
    Uri? baseUrl,
    http.Client? httpClient,
    String? organization,
    String? project,
  }) : _client = ProviderHttpClient(
         baseUrl: baseUrl ?? Uri.parse('https://api.openai.com/v1/'),
         client: httpClient,
         headers: {
           'authorization': 'Bearer ${_nonEmpty(apiKey, 'apiKey')}',
           if (organization != null) 'openai-organization': _nonEmpty(organization, 'organization'),
           if (project != null) 'openai-project': _nonEmpty(project, 'project'),
         },
       ) {
    responses = OpenAIResponsesResource(_client);
  }

  final ProviderHttpClient _client;

  /// Typed native Responses operations.
  late final OpenAIResponsesResource responses;

  /// Creates a common language model backed by the Responses API.
  OpenAILanguageModel languageModel(String modelId, {OpenAIModelOptions? options}) =>
      OpenAILanguageModel._(
        responses,
        _nonEmpty(modelId, 'modelId'),
        options ?? OpenAIModelOptions(),
      );

  /// Interrupts this provider's work and releases its owned HTTP client.
  Future<void> close() => _client.close();
}

/// An OpenAI Responses adapter for the common language-model contract.
final class OpenAILanguageModel implements LanguageModel {
  OpenAILanguageModel._(this._responses, this.modelId, this.options);

  final OpenAIResponsesResource _responses;

  /// Immutable model defaults.
  final OpenAIModelOptions options;

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
    ModelCapability.videoInput: CapabilitySupport.unsupported,
    ModelCapability.documentInput: CapabilitySupport.unknown,
  });

  @override
  Effect<GenerationResult, AiError> generate(
    GenerationRequest request, {
    OpenAIModelOptions? options,
  }) {
    final native = _encodeCommon(request, options ?? this.options, stream: false);
    return switch (native) {
      AiError() => Effect.fail(native),
      OpenAIResponseRequest() => _responses.create(native).map(_responses.normalize),
      _ => throw StateError('Unexpected common request encoding result.'),
    };
  }

  @override
  Flow<GenerationEvent, AiError> stream(
    GenerationRequest request, {
    OpenAIModelOptions? options,
  }) {
    final native = _encodeCommon(request, options ?? this.options, stream: true);
    return switch (native) {
      AiError() => Effect.fail<GenerationEvent, AiError>(native).asFlow(),
      OpenAIResponseRequest() => _responses.streamCommon(native),
      _ => throw StateError('Unexpected common request encoding result.'),
    };
  }

  Object _encodeCommon(
    GenerationRequest request,
    OpenAIModelOptions options, {
    required bool stream,
  }) {
    final replayError = request.validateReplayTarget(
      providerId: providerId,
      api: _responsesApi,
      modelId: modelId,
    );
    if (replayError != null) return replayError;
    if (request.tools.isNotEmpty || request.output is! TextOutputFormat) {
      return const UnsupportedFeatureError(
        'This OpenAI slice currently supports text Responses without tools.',
      );
    }
    final input = <OpenAIResponseInputItem>[];
    for (final message in request.messages) {
      if (message case UserMessage(:final parts)) {
        if (parts.any((part) => part is! TextInputPart)) {
          return const UnsupportedFeatureError(
            'This OpenAI slice currently supports text message parts.',
          );
        }
        input.add(
          OpenAIResponseInputMessage(
            role: OpenAIResponseInputRole.user,
            content: [
              for (final part in parts.cast<TextInputPart>()) OpenAITextInputPart(part.text),
            ],
          ),
        );
      } else if (message case AssistantMessage(:final parts)) {
        if (parts.any((part) => part is! TextOutputPart)) {
          return const UnsupportedFeatureError(
            'This OpenAI slice currently supports text assistant history.',
          );
        }
        input.add(
          OpenAIResponseInputMessage(
            role: OpenAIResponseInputRole.assistant,
            content: [
              for (final part in parts.cast<TextOutputPart>()) OpenAITextInputPart(part.text),
            ],
          ),
        );
      } else {
        return const UnsupportedFeatureError(
          'This OpenAI slice currently supports user and assistant text messages.',
        );
      }
    }
    return OpenAIResponseRequest(
      model: modelId,
      input: input,
      instructions: request.instructions,
      maxOutputTokens: request.options.maxOutputTokens,
      temperature: request.options.temperature,
      topP: request.options.topP,
      store: false,
      stream: stream,
      extraBody: options.extraBody,
    );
  }
}

String _nonEmpty(String value, String name) {
  if (value.isEmpty) throw ArgumentError.value(value, name, 'must not be empty');
  return value;
}
