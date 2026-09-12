import 'package:artificer_anthropic/src/messages/message_models.dart';
import 'package:artificer_anthropic/src/messages/messages_resource.dart';
import 'package:artificer_anthropic/src/options.dart';
import 'package:artificer_core/artificer_core.dart';
import 'package:artificer_core/transport.dart';
import 'package:conflux/conflux.dart';
import 'package:http/http.dart' as http;

const _providerId = 'anthropic';
const _messagesApi = 'messages';

/// An Anthropic client with common language models and typed native resources.
final class AnthropicProvider {
  /// Creates an explicit-credential Anthropic client.
  AnthropicProvider({
    required String apiKey,
    Uri? baseUrl,
    http.Client? httpClient,
    AnthropicApiVersion apiVersion = AnthropicApiVersion.v20230601,
    Iterable<AnthropicBeta> betaFeatures = const [],
    String? userProfileId,
  }) : _client = ProviderHttpClient(
         baseUrl: _directoryBaseUrl(
           baseUrl ?? Uri.parse('https://api.anthropic.com/v1'),
         ),
         client: httpClient,
         headers: {
           'x-api-key': _nonEmpty(apiKey, 'apiKey'),
           'anthropic-version': _nonEmpty(apiVersion.headerValue, 'apiVersion'),
           if (betaFeatures.isNotEmpty)
             'anthropic-beta': betaFeatures
                 .map((feature) => _nonEmpty(feature.headerValue, 'betaFeatures'))
                 .join(','),
           if (userProfileId != null)
             'anthropic-user-profile-id': _nonEmpty(userProfileId, 'userProfileId'),
         },
       ) {
    messages = AnthropicMessagesResource(_client);
  }

  final ProviderHttpClient _client;

  /// Typed native Messages operations.
  late final AnthropicMessagesResource messages;

  /// Creates a common language model backed by Messages.
  AnthropicLanguageModel languageModel(String modelId, {AnthropicModelOptions? options}) =>
      AnthropicLanguageModel._(
        messages,
        _nonEmpty(modelId, 'modelId'),
        options ?? AnthropicModelOptions(),
      );

  /// Interrupts this provider's work and releases its owned HTTP client.
  Future<void> close() => _client.close();
}

/// An Anthropic Messages adapter for the common language-model contract.
final class AnthropicLanguageModel implements LanguageModel {
  AnthropicLanguageModel._(this._messages, this.modelId, this.options);

  final AnthropicMessagesResource _messages;

  /// Immutable model defaults.
  final AnthropicModelOptions options;

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
    AnthropicModelOptions? options,
  }) {
    final native = _encodeCommon(request, options);
    return switch (native) {
      AiError() => Effect.fail(native),
      AnthropicMessageRequest() => _messages.create(native).map(_messages.normalize),
      _ => throw StateError('Unexpected common request encoding result.'),
    };
  }

  @override
  Flow<GenerationEvent, AiError> stream(
    GenerationRequest request, {
    AnthropicModelOptions? options,
  }) {
    final native = _encodeCommon(request, options);
    return switch (native) {
      AiError() => Effect.fail<GenerationEvent, AiError>(native).asFlow(),
      AnthropicMessageRequest() => _messages.streamCommon(native),
      _ => throw StateError('Unexpected common request encoding result.'),
    };
  }

  Object _encodeCommon(GenerationRequest request, AnthropicModelOptions? callOptions) {
    final replayError = request.validateReplayTarget(
      providerId: providerId,
      api: _messagesApi,
      modelId: modelId,
    );
    if (replayError != null) return replayError;
    if (request.tools.isNotEmpty || request.toolChoice is! AutoToolChoice) {
      return const UnsupportedFeatureError(
        'Application tools are not available in this Messages implementation.',
      );
    }
    if (request.output is! TextOutputFormat) {
      return const UnsupportedFeatureError(
        'Structured output is not available in this Messages implementation.',
      );
    }
    final messages = <AnthropicInputMessage>[];
    for (final message in request.messages) {
      final encoded = switch (message) {
        UserMessage(:final parts) => _textMessage(AnthropicMessageRole.user, parts),
        AssistantMessage(:final parts) => _assistantTextMessage(parts),
        ToolMessage() => const UnsupportedFeatureError(
          'Tool results are not available in this Messages implementation.',
        ),
      };
      if (encoded is AiError) return encoded;
      messages.add(encoded as AnthropicInputMessage);
    }
    final extra = options.resolveExtraBody(callOptions);
    return AnthropicMessageRequest(
      model: modelId,
      maxTokens: request.options.maxOutputTokens,
      messages: messages,
      system: request.instructions == null ? const [] : [AnthropicTextBlock(request.instructions!)],
      temperature: request.options.temperature,
      topP: request.options.topP,
      stopSequences: request.options.stopSequences,
      extraBody: extra,
    );
  }
}

Object _textMessage(AnthropicMessageRole role, Iterable<InputPart> parts) {
  final content = <AnthropicContentBlock>[];
  for (final part in parts) {
    if (part is! TextInputPart) {
      return const UnsupportedFeatureError(
        'Only text content is available in this Messages implementation.',
      );
    }
    content.add(AnthropicTextBlock(part.text));
  }
  return AnthropicInputMessage(role: role, content: content);
}

Object _assistantTextMessage(Iterable<OutputPart> parts) {
  final content = <AnthropicContentBlock>[];
  for (final part in parts) {
    if (part is! TextOutputPart) {
      return const UnsupportedFeatureError(
        'Only text content is available in this Messages implementation.',
      );
    }
    content.add(AnthropicTextBlock(part.text));
  }
  if (content.isEmpty) {
    return const UnsupportedFeatureError(
      'Empty assistant messages are not accepted by Anthropic Messages.',
    );
  }
  return AnthropicInputMessage(role: AnthropicMessageRole.assistant, content: content);
}

String _nonEmpty(String value, String name) {
  if (value.isEmpty) throw ArgumentError.value(value, name, 'must not be empty');
  return value;
}

Uri _directoryBaseUrl(Uri value) =>
    value.path.endsWith('/') ? value : value.replace(path: '${value.path}/');
