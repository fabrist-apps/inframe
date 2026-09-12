import 'package:artificer_core/artificer_core.dart';
import 'package:artificer_core/json.dart';
import 'package:artificer_core/transport.dart';
import 'package:artificer_google/src/generate_content/generate_content_models.dart';
import 'package:artificer_google/src/generate_content/generate_content_resource.dart';
import 'package:artificer_google/src/generate_content/tool_models.dart';
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
      GoogleGenerateContentRequest() =>
        _resource.create(native).flatMap((response) => _normalizeCommon(response, native)),
      _ => throw StateError('Unexpected common Google request encoding result.'),
    };
  }

  Effect<GenerationResult, AiError> _normalizeCommon(
    NativeResponse<GoogleGenerateContentResponse> response,
    GoogleGenerateContentRequest request,
  ) {
    try {
      return Effect.succeed(_resource.normalize(response, request: request));
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
    final contents = <GoogleContent>[];
    final calls = <String, ApplicationToolCallPart>{};
    for (final message in request.messages) {
      switch (message) {
        case UserMessage(:final parts):
          final encoded = _encodeUserParts(parts);
          if (encoded is AiError) return encoded;
          contents.add(GoogleContent(role: 'user', parts: encoded as List<GooglePart>));
        case AssistantMessage(:final parts, :final replay):
          for (final call in parts.whereType<ApplicationToolCallPart>()) {
            calls[call.id] = call;
          }
          final replayContents = _replayContents(replay);
          if (replayContents.isNotEmpty) {
            contents.addAll(replayContents);
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
        case ToolMessage(:final results):
          final parts = <GooglePart>[];
          for (final result in results) {
            final call = calls[result.callId];
            if (call == null) {
              return InvalidRequestError(
                'Tool result ${result.callId} references a missing call.',
              );
            }
            final encoded = _encodeToolResult(result, call);
            if (encoded is AiError) return encoded;
            parts.add(encoded as GooglePart);
          }
          contents.add(GoogleContent(role: 'user', parts: parts));
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
    final applicationTools = [
      for (final tool in request.tools)
        GoogleFunctionDeclaration(
          name: tool.name,
          description: tool.description,
          parameters: tool.inputSchema,
        ),
    ];
    final nativeTools = options.resolveTools(callOptions) ?? const <GoogleToolDefinition>[];
    final declaredNames = <String>{};
    for (final name in [
      ...applicationTools.map((tool) => tool.name),
      ...nativeTools.expand((tool) => tool.functionNames),
    ]) {
      if (!declaredNames.add(name)) {
        return InvalidRequestError('Tool function $name is declared more than once.');
      }
    }
    final tools = <GoogleToolDefinition>[
      if (applicationTools.isNotEmpty) GoogleFunctionDeclarationsTool(applicationTools),
      ...nativeTools,
    ];
    final configuredToolConfig = options.resolveToolConfig(callOptions);
    final commonToolConfig = _encodeToolChoice(request.toolChoice, request.tools);
    if (configuredToolConfig != null && commonToolConfig != null) {
      return const InvalidRequestError(
        'Native toolConfig conflicts with the common tool choice.',
      );
    }
    final output = _encodeOutput(request.output);
    if (output is AiError) return output;
    final outputConfig = output as _GoogleOutputConfig;
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
        responseMimeType: outputConfig.mimeType,
        responseJsonSchema: outputConfig.schema,
      ),
      safetySettings: safetySettings,
      cachedContent: cachedContent,
      tools: tools.isEmpty ? null : tools,
      toolConfig: configuredToolConfig ?? commonToolConfig,
      extraBody: extraBody,
    );
  }

  Object _encodeUserParts(List<InputPart> parts) {
    final encoded = <GooglePart>[];
    for (final part in parts) {
      if (part case TextInputPart(:final text)) {
        encoded.add(GooglePart.text(text));
      } else if (part case MediaInputPart(:final mimeType, :final source)) {
        switch (source) {
          case BytesMediaSource(:final bytes):
            encoded.add(
              GooglePart.inlineData(GoogleInlineData(mimeType: mimeType, bytes: bytes)),
            );
          case ProviderFileSource(
            :final providerId,
            :final api,
            :final reference,
            :final mimeType,
          ):
            if (providerId != _providerId || api != 'files') {
              return const UnsupportedFeatureError(
                'Google generation requires a Google Files reference.',
              );
            }
            encoded.add(
              GooglePart.fileData(GoogleFileData(mimeType: mimeType, fileUri: reference)),
            );
          case UrlMediaSource():
            return const UnsupportedFeatureError(
              'Google generation does not accept arbitrary common media URLs.',
            );
        }
      }
    }
    return encoded;
  }

  List<GoogleContent> _replayContents(ProviderReplay? replay) {
    if (replay == null) return const [];
    final contents = <GoogleContent>[];
    for (final item in replay.items) {
      if (item.phase == 'content') {
        contents.add(GoogleContent.fromJson(item.data));
      } else if (item.phase == 'candidate') {
        final content = GoogleCandidate.fromJson(item.data).content;
        if (content != null) contents.add(content);
      } else if (item.phase == 'stream-chunk') {
        final response = GoogleGenerateContentResponse.fromJson(item.data);
        for (final candidate in response.candidates) {
          if (candidate.content case final content?) contents.add(content);
        }
      }
    }
    return contents;
  }
}

Object _encodeToolResult(ToolResult result, ApplicationToolCallPart call) {
  final nativeCall = call.arguments is NativeToolArguments;
  final response = switch (result) {
    JsonToolResult(:final value) when !nativeCall => JsonObject({'output': value.toDart()}),
    TextToolResult(:final content) when !nativeCall => JsonObject({
      'content': content.map((part) => part.toDart()).toList(),
    }),
    ApplicationErrorToolResult(:final message, :final details) => JsonObject({
      'error': message,
      if (details != null) 'details': details.toDart(),
    }),
    NativeToolResult(:final providerId, :final api, :final value)
        when nativeCall && providerId == _providerId && api == _api =>
      value,
    JsonToolResult() || TextToolResult() || NativeToolResult() => null,
  };
  if (response == null) {
    return const InvalidRequestError(
      'Tool result kind or native target does not match the Google call.',
    );
  }
  return GooglePart.functionResponse(
    GoogleFunctionResponse(
      id: call.id.startsWith('google-call-') ? null : call.id,
      name: call.name,
      response: response,
    ),
  );
}

GoogleToolConfig? _encodeToolChoice(ToolChoice choice, List<FunctionTool> tools) {
  if (tools.isEmpty && choice is AutoToolChoice) return null;
  final config = switch (choice) {
    AutoToolChoice() => GoogleFunctionCallingConfig(mode: GoogleFunctionCallingMode.auto),
    NoToolChoice() => GoogleFunctionCallingConfig(mode: GoogleFunctionCallingMode.none),
    RequiredToolChoice() => GoogleFunctionCallingConfig(mode: GoogleFunctionCallingMode.any),
    FunctionToolChoice(:final name) => GoogleFunctionCallingConfig(
      mode: GoogleFunctionCallingMode.any,
      allowedFunctionNames: [name],
    ),
  };
  return GoogleToolConfig(functionCallingConfig: config);
}

Object _encodeOutput(OutputFormat output) {
  if (output is TextOutputFormat) return const _GoogleOutputConfig();
  if (output is JsonObjectOutputFormat) {
    return const _GoogleOutputConfig(mimeType: 'application/json');
  }
  final schema = (output as JsonSchemaOutputFormat).schema;
  final unsupported = _unsupportedSchemaKeyword(schema.toDart(), isSchema: true);
  if (unsupported != null) {
    return UnsupportedFeatureError(
      'Google responseJsonSchema does not support $unsupported.',
      feature: 'structuredOutput',
    );
  }
  return _GoogleOutputConfig(mimeType: 'application/json', schema: schema);
}

String? _unsupportedSchemaKeyword(Object? value, {required bool isSchema}) {
  if (!isSchema || value is! Map<String, Object?>) return null;
  for (final entry in value.entries) {
    if (!_schemaKeywords.contains(entry.key)) return entry.key;
    switch (entry.key) {
      case 'properties' || r'$defs':
        if (entry.value case final Map<String, Object?> children) {
          for (final child in children.values) {
            final unsupported = _unsupportedSchemaKeyword(child, isSchema: true);
            if (unsupported != null) return unsupported;
          }
        }
      case 'items' || 'additionalProperties':
        final unsupported = _unsupportedSchemaKeyword(entry.value, isSchema: true);
        if (unsupported != null) return unsupported;
      case 'prefixItems' || 'anyOf' || 'oneOf':
        if (entry.value case final List<Object?> children) {
          for (final child in children) {
            final unsupported = _unsupportedSchemaKeyword(child, isSchema: true);
            if (unsupported != null) return unsupported;
          }
        }
    }
  }
  return null;
}

final class _GoogleOutputConfig {
  const _GoogleOutputConfig({this.mimeType, this.schema});

  final String? mimeType;
  final JsonObject? schema;
}

const _schemaKeywords = {
  r'$id',
  r'$defs',
  r'$ref',
  r'$anchor',
  'type',
  'format',
  'title',
  'description',
  'enum',
  'items',
  'prefixItems',
  'minItems',
  'maxItems',
  'minimum',
  'maximum',
  'anyOf',
  'oneOf',
  'properties',
  'additionalProperties',
  'required',
  'propertyOrdering',
};

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
