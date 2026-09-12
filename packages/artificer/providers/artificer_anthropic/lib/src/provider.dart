import 'dart:convert';

import 'package:artificer_anthropic/src/messages/message_models.dart';
import 'package:artificer_anthropic/src/messages/messages_resource.dart';
import 'package:artificer_anthropic/src/options.dart';
import 'package:artificer_core/artificer_core.dart';
import 'package:artificer_core/json.dart';
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
    final messages = <AnthropicInputMessage>[];
    for (final message in request.messages) {
      final encoded = switch (message) {
        UserMessage(:final parts) => _userMessage(parts),
        AssistantMessage() => _assistantMessage(message),
        ToolMessage(:final results) => _toolMessage(results),
      };
      if (encoded is AiError) return encoded;
      messages.add(encoded as AnthropicInputMessage);
    }
    final tools = request.tools
        .map(
          (tool) => AnthropicClientTool(
            name: tool.name,
            description: tool.description,
            inputSchema: tool.inputSchema,
          ),
        )
        .toList();
    final toolChoice = switch (request.toolChoice) {
      AutoToolChoice() => tools.isEmpty ? null : const AnthropicAutoToolChoice(),
      NoToolChoice() => const AnthropicNoToolChoice(),
      RequiredToolChoice() => const AnthropicAnyToolChoice(),
      FunctionToolChoice(:final name) => AnthropicNamedToolChoice(name),
    };
    final outputConfig = switch (request.output) {
      TextOutputFormat() => null,
      JsonSchemaOutputFormat(:final schema) => AnthropicOutputConfig.jsonSchema(schema),
      JsonObjectOutputFormat() => const UnsupportedFeatureError(
        'Anthropic Messages requires a JSON Schema for structured output.',
      ),
    };
    if (outputConfig is AiError) return outputConfig;
    final extra = options.resolveExtraBody(callOptions);
    return AnthropicMessageRequest(
      model: modelId,
      maxTokens: request.options.maxOutputTokens,
      messages: messages,
      system: request.instructions == null ? const [] : [AnthropicTextBlock(request.instructions!)],
      temperature: request.options.temperature,
      topP: request.options.topP,
      stopSequences: request.options.stopSequences,
      tools: tools,
      toolChoice: toolChoice,
      outputConfig: outputConfig as AnthropicOutputConfig?,
      cacheControl: options.resolveCacheControl(callOptions),
      extraBody: extra,
    );
  }
}

Object _userMessage(Iterable<InputPart> parts) {
  final content = <AnthropicContentBlock>[];
  for (final part in parts) {
    final native = _inputPart(part);
    if (native is AiError) return native;
    content.add(native as AnthropicContentBlock);
  }
  return AnthropicInputMessage(role: AnthropicMessageRole.user, content: content);
}

Object _inputPart(InputPart part) {
  if (part case TextInputPart(:final text)) return AnthropicTextBlock(text);
  final media = part as MediaInputPart;
  if (media.kind == MediaKind.audio || media.kind == MediaKind.video) {
    return UnsupportedFeatureError(
      'Anthropic Messages does not support ${media.kind.name} common input.',
    );
  }
  final source = media.source;
  if (source case ProviderFileSource()) {
    if (source.providerId != _providerId || source.api != _messagesApi) {
      return const UnsupportedFeatureError(
        'Anthropic Messages accepts only its own provider file references.',
      );
    }
    if (source.mimeType != media.mimeType) {
      return const InvalidRequestError(
        'The provider file MIME type must match the media part MIME type.',
      );
    }
  }
  return switch (media.kind) {
    MediaKind.image => _image(media.mimeType, source),
    MediaKind.document => _document(media.mimeType, source),
    MediaKind.audio || MediaKind.video => throw StateError('Rejected above.'),
  };
}

Object _image(String mimeType, MediaSource source) {
  const supported = {'image/jpeg', 'image/png', 'image/gif', 'image/webp'};
  if (!supported.contains(mimeType)) {
    return UnsupportedFeatureError(
      'Anthropic Messages does not support image MIME type $mimeType.',
    );
  }
  return switch (source) {
    BytesMediaSource(:final bytes) => AnthropicImageBlock.bytes(bytes, mimeType: mimeType),
    UrlMediaSource(:final url) => AnthropicImageBlock.url(url),
    ProviderFileSource(:final reference) => AnthropicImageBlock.file(reference),
  };
}

Object _document(String mimeType, MediaSource source) {
  return switch (source) {
    BytesMediaSource(:final bytes) when mimeType == 'application/pdf' =>
      AnthropicDocumentBlock.pdfBytes(bytes),
    BytesMediaSource(:final bytes) when mimeType == 'text/plain' => _plainTextDocument(bytes),
    UrlMediaSource(:final url) when mimeType == 'application/pdf' => AnthropicDocumentBlock.url(
      url,
    ),
    ProviderFileSource(:final reference) => AnthropicDocumentBlock.file(reference),
    _ => UnsupportedFeatureError(
      'Anthropic Messages cannot forward document MIME type $mimeType from this source.',
    ),
  };
}

Object _plainTextDocument(List<int> bytes) {
  try {
    return AnthropicDocumentBlock.text(utf8.decode(bytes));
  } on FormatException {
    return const InvalidRequestError('Plain-text document bytes must be valid UTF-8.');
  }
}

Object _assistantMessage(AssistantMessage message) {
  final replay = message.replay;
  if (replay != null) {
    return AnthropicInputMessage(
      role: AnthropicMessageRole.assistant,
      content: replay.items
          .where((item) => item.phase != 'unknown-event')
          .map((item) => AnthropicContentBlock.fromJson(item.data)),
    );
  }
  final content = <AnthropicContentBlock>[];
  for (final part in message.parts) {
    final native = switch (part) {
      TextOutputPart(:final text) => AnthropicTextBlock(text),
      ApplicationToolCallPart(:final id, :final name, :final arguments) => _toolUse(
        id,
        name,
        arguments,
      ),
      OpaqueOutputPart(:final providerId, :final api, :final data)
          when providerId == _providerId && api == _messagesApi =>
        AnthropicContentBlock.fromJson(data),
      _ => const UnsupportedFeatureError(
        'This assistant content cannot be represented by Anthropic Messages.',
      ),
    };
    if (native is AiError) return native;
    content.add(native as AnthropicContentBlock);
  }
  if (content.isEmpty) {
    return const UnsupportedFeatureError(
      'Empty assistant messages are not accepted by Anthropic Messages.',
    );
  }
  return AnthropicInputMessage(role: AnthropicMessageRole.assistant, content: content);
}

Object _toolUse(String id, String name, ToolArguments arguments) => switch (arguments) {
  JsonToolArguments(:final value) => AnthropicToolUseBlock(id: id, name: name, input: value),
  MalformedToolArguments() => const UnsupportedFeatureError(
    'Malformed tool arguments can only be replayed from retained native blocks.',
  ),
  TextToolArguments() || NativeToolArguments() => const UnsupportedFeatureError(
    'This tool argument kind is not a native Anthropic client-tool input.',
  ),
};

Object _toolMessage(Iterable<ToolResult> results) {
  final content = <AnthropicContentBlock>[];
  for (final result in results) {
    final native = _toolResult(result);
    if (native is AiError) return native;
    content.add(native as AnthropicContentBlock);
  }
  return AnthropicInputMessage(role: AnthropicMessageRole.user, content: content);
}

Object _toolResult(ToolResult result) => switch (result) {
  JsonToolResult(:final callId, :final value) => AnthropicToolResultBlock(
    toolUseId: callId,
    content: value.encode(),
  ),
  TextToolResult(:final callId, :final content) => _contentToolResult(callId, content),
  ApplicationErrorToolResult(:final callId, :final message, :final details) =>
    AnthropicToolResultBlock(
      toolUseId: callId,
      content: JsonObject({'message': message, if (details != null) 'details': details.toDart()})
          .encode(),
      isError: true,
    ),
  NativeToolResult() => const UnsupportedFeatureError(
    'Native Anthropic action results require a matching typed native tool call.',
  ),
};

Object _contentToolResult(String callId, Iterable<InputPart> parts) {
  final content = <Object?>[];
  for (final part in parts) {
    final native = _inputPart(part);
    if (native is AiError) return native;
    content.add((native as AnthropicContentBlock).toDart());
  }
  return AnthropicToolResultBlock(toolUseId: callId, content: content);
}

String _nonEmpty(String value, String name) {
  if (value.isEmpty) throw ArgumentError.value(value, name, 'must not be empty');
  return value;
}

Uri _directoryBaseUrl(Uri value) =>
    value.path.endsWith('/') ? value : value.replace(path: '${value.path}/');
