import 'dart:convert';

import 'package:artificer_core/artificer_core.dart';
import 'package:artificer_core/json.dart';
import 'package:artificer_google/src/generate_content/tool_models.dart';

/// Inline media bytes in a native Gemini part.
final class GoogleInlineData {
  /// Creates inline media and copies its bytes.
  GoogleInlineData({required String mimeType, required Iterable<int> bytes})
    : mimeType = _nonEmpty(mimeType, 'mimeType'),
      bytes = List.unmodifiable(bytes);

  /// Decodes inline media.
  factory GoogleInlineData.fromJson(JsonObject json) {
    final value = json.toDart();
    final encoded = _requiredString(value, 'data');
    return GoogleInlineData(
      mimeType: _requiredString(value, 'mimeType'),
      bytes: base64Decode(encoded),
    );
  }

  /// Media type.
  final String mimeType;

  /// Copied bytes.
  final List<int> bytes;

  /// Encodes inline media.
  JsonObject toJson() => JsonObject({'mimeType': mimeType, 'data': base64Encode(bytes)});
}

/// A native Google file URI used in model input.
final class GoogleFileData {
  /// Creates a file reference.
  GoogleFileData({required String mimeType, required String fileUri})
    : mimeType = _nonEmpty(mimeType, 'mimeType'),
      fileUri = _nonEmpty(fileUri, 'fileUri');

  /// Decodes a file reference.
  factory GoogleFileData.fromJson(JsonObject json) {
    final value = json.toDart();
    return GoogleFileData(
      mimeType: _requiredString(value, 'mimeType'),
      fileUri: _requiredString(value, 'fileUri'),
    );
  }

  /// Media type.
  final String mimeType;

  /// Google file URI.
  final String fileUri;

  /// Encodes the reference.
  JsonObject toJson() => JsonObject({'mimeType': mimeType, 'fileUri': fileUri});
}

/// A native Gemini function call.
final class GoogleFunctionCall {
  /// Creates a function call.
  GoogleFunctionCall({
    required String name,
    required this.args,
    this.id,
    JsonObject? extensions,
  }) : name = _nonEmpty(name, 'name'),
       rawArgs = args,
       extensions = extensions ?? JsonObject({});

  GoogleFunctionCall._({
    required this.id,
    required this.name,
    required this.args,
    required this.rawArgs,
    required this.extensions,
  });

  /// Decodes a call while retaining unknown fields.
  factory GoogleFunctionCall.fromJson(JsonObject json) {
    final value = json.toDart();
    final args = value['args'];
    return GoogleFunctionCall._(
      id: _optionalString(value, 'id'),
      name: _requiredString(value, 'name'),
      args: args is Map<String, Object?> ? JsonObject(args) : JsonObject({}),
      rawArgs: JsonValue.fromDart(args),
      extensions: JsonObject(_without(value, {'id', 'name', 'args'})),
    );
  }

  /// Optional native call ID.
  final String? id;

  /// Function name.
  final String name;

  /// Native arguments.
  final JsonObject args;

  /// Arguments exactly as returned, including malformed non-object values.
  final JsonValue rawArgs;

  /// Unknown call fields.
  final JsonObject extensions;

  /// Encodes the call.
  JsonObject toJson() => JsonObject({
    ...extensions.toDart(),
    'id': ?id,
    'name': name,
    'args': rawArgs.toDart(),
  });
}

/// A native Gemini function result.
final class GoogleFunctionResponse {
  /// Creates a function response.
  GoogleFunctionResponse({
    required String name,
    required this.response,
    this.id,
    JsonObject? extensions,
  }) : name = _nonEmpty(name, 'name'),
       extensions = extensions ?? JsonObject({});

  /// Decodes a function response.
  factory GoogleFunctionResponse.fromJson(JsonObject json) {
    final value = json.toDart();
    return GoogleFunctionResponse(
      id: _optionalString(value, 'id'),
      name: _requiredString(value, 'name'),
      response: JsonObject.fromDart(value['response']),
      extensions: JsonObject(_without(value, {'id', 'name', 'response'})),
    );
  }

  /// Optional call ID.
  final String? id;

  /// Function name.
  final String name;

  /// Result object.
  final JsonObject response;

  /// Unknown response fields.
  final JsonObject extensions;

  /// Encodes the result.
  JsonObject toJson() => JsonObject({
    ...extensions.toDart(),
    'id': ?id,
    'name': name,
    'response': response.toDart(),
  });
}

/// One native Gemini content part from the pinned GenerateContent schema.
final class GooglePart {
  /// Creates a text part.
  GooglePart.text(String text, {this.thought, this.thoughtSignature, JsonObject? extensions})
    : text = _nonEmpty(text, 'text'),
      inlineData = null,
      fileData = null,
      functionCall = null,
      functionResponse = null,
      executableCode = null,
      codeExecutionResult = null,
      toolCall = null,
      toolResponse = null,
      extensions = extensions ?? JsonObject({});

  /// Creates an inline-media part.
  GooglePart.inlineData(GoogleInlineData data, {JsonObject? extensions})
    : text = null,
      inlineData = data,
      fileData = null,
      functionCall = null,
      functionResponse = null,
      executableCode = null,
      codeExecutionResult = null,
      toolCall = null,
      toolResponse = null,
      thought = null,
      thoughtSignature = null,
      extensions = extensions ?? JsonObject({});

  /// Creates a Google-file part.
  GooglePart.fileData(GoogleFileData data, {JsonObject? extensions})
    : text = null,
      inlineData = null,
      fileData = data,
      functionCall = null,
      functionResponse = null,
      executableCode = null,
      codeExecutionResult = null,
      toolCall = null,
      toolResponse = null,
      thought = null,
      thoughtSignature = null,
      extensions = extensions ?? JsonObject({});

  /// Creates an application function-call part.
  GooglePart.functionCall(GoogleFunctionCall call, {this.thoughtSignature, JsonObject? extensions})
    : text = null,
      inlineData = null,
      fileData = null,
      functionCall = call,
      functionResponse = null,
      executableCode = null,
      codeExecutionResult = null,
      toolCall = null,
      toolResponse = null,
      thought = null,
      extensions = extensions ?? JsonObject({});

  /// Creates an application function-result part.
  GooglePart.functionResponse(GoogleFunctionResponse response, {JsonObject? extensions})
    : text = null,
      inlineData = null,
      fileData = null,
      functionCall = null,
      functionResponse = response,
      executableCode = null,
      codeExecutionResult = null,
      toolCall = null,
      toolResponse = null,
      thought = null,
      thoughtSignature = null,
      extensions = extensions ?? JsonObject({});

  /// Creates a typed part from its complete pinned-schema JSON.
  factory GooglePart.raw(JsonObject json) => GooglePart.fromJson(json);

  GooglePart._({
    required this.text,
    required this.inlineData,
    required this.fileData,
    required this.functionCall,
    required this.functionResponse,
    required this.executableCode,
    required this.codeExecutionResult,
    required this.toolCall,
    required this.toolResponse,
    required this.thought,
    required this.thoughtSignature,
    required this.extensions,
  });

  /// Decodes a part while retaining fields outside this slice's typed surface.
  factory GooglePart.fromJson(JsonObject json) {
    final value = json.toDart();
    final text = value['text'];
    if (text != null && text is! String) {
      throw const FormatException('part.text must be a string.');
    }
    return GooglePart._(
      text: text as String?,
      inlineData: _optionalObject(value, 'inlineData', GoogleInlineData.fromJson),
      fileData: _optionalObject(value, 'fileData', GoogleFileData.fromJson),
      functionCall: _optionalObject(value, 'functionCall', GoogleFunctionCall.fromJson),
      functionResponse: _optionalObject(
        value,
        'functionResponse',
        GoogleFunctionResponse.fromJson,
      ),
      executableCode: _optionalJsonObject(value, 'executableCode'),
      codeExecutionResult: _optionalJsonObject(value, 'codeExecutionResult'),
      toolCall: _optionalJsonObject(value, 'toolCall'),
      toolResponse: _optionalJsonObject(value, 'toolResponse'),
      thought: _optionalBool(value, 'thought'),
      thoughtSignature: _optionalString(value, 'thoughtSignature'),
      extensions: JsonObject(
        _without(value, {
          'text',
          'inlineData',
          'fileData',
          'functionCall',
          'functionResponse',
          'executableCode',
          'codeExecutionResult',
          'toolCall',
          'toolResponse',
          'thought',
          'thoughtSignature',
        }),
      ),
    );
  }

  /// Text carried by this part, when it is a text part.
  final String? text;

  /// Inline bytes.
  final GoogleInlineData? inlineData;

  /// Google file URI.
  final GoogleFileData? fileData;

  /// Application or computer-use call.
  final GoogleFunctionCall? functionCall;

  /// Application or computer-use result.
  final GoogleFunctionResponse? functionResponse;

  /// Provider-executed code.
  final JsonObject? executableCode;

  /// Provider-executed code result.
  final JsonObject? codeExecutionResult;

  /// Provider-hosted tool activity.
  final JsonObject? toolCall;

  /// Provider-hosted tool result.
  final JsonObject? toolResponse;

  /// Whether this is provider-supplied thought content.
  final bool? thought;

  /// Opaque signature required for same-target replay.
  final String? thoughtSignature;

  /// Immutable fields not yet modeled by this package snapshot.
  final JsonObject extensions;

  /// The complete native part.
  JsonObject toJson() => JsonObject({
    ...extensions.toDart(),
    'text': ?text,
    if (inlineData case final value?) 'inlineData': value.toJson().toDart(),
    if (fileData case final value?) 'fileData': value.toJson().toDart(),
    if (functionCall case final value?) 'functionCall': value.toJson().toDart(),
    if (functionResponse case final value?) 'functionResponse': value.toJson().toDart(),
    if (executableCode case final value?) 'executableCode': value.toDart(),
    if (codeExecutionResult case final value?) 'codeExecutionResult': value.toDart(),
    if (toolCall case final value?) 'toolCall': value.toDart(),
    if (toolResponse case final value?) 'toolResponse': value.toDart(),
    'thought': ?thought,
    'thoughtSignature': ?thoughtSignature,
  });
}

/// One ordered native Gemini conversation turn.
final class GoogleContent {
  /// Creates native content.
  GoogleContent({required Iterable<GooglePart> parts, this.role, JsonObject? extensions})
    : parts = List.unmodifiable(parts),
      extensions = extensions ?? JsonObject({}) {
    if (this.parts.isEmpty) {
      throw ArgumentError.value(parts, 'parts', 'must not be empty');
    }
  }

  /// Decodes content while retaining unknown fields.
  factory GoogleContent.fromJson(JsonObject json) {
    final value = json.toDart();
    final parts = _list(value, 'parts');
    return GoogleContent(
      role: _optionalString(value, 'role'),
      parts: parts.map((part) => GooglePart.fromJson(JsonObject.fromDart(part))),
      extensions: JsonObject(_without(value, {'role', 'parts'})),
    );
  }

  /// `user` or `model` for conversation content; system instructions omit it.
  final String? role;

  /// Ordered native parts.
  final List<GooglePart> parts;

  /// Immutable fields outside the typed snapshot.
  final JsonObject extensions;

  /// Encodes the complete native content.
  JsonObject toJson() => JsonObject({
    ...extensions.toDart(),
    'role': ?role,
    'parts': parts.map((part) => part.toJson().toDart()).toList(),
  });
}

/// Native Gemini thinking configuration pinned to the 2026-09-12 reference.
final class GoogleThinkingConfig {
  /// Creates native thinking configuration.
  GoogleThinkingConfig({this.includeThoughts, this.thinkingBudget, this.thinkingLevel}) {
    if (thinkingBudget != null && thinkingLevel != null) {
      throw ArgumentError('thinkingBudget and thinkingLevel are mutually exclusive.');
    }
  }

  /// Whether thought summaries should be returned.
  final bool? includeThoughts;

  /// Token budget for models that support numeric thinking control.
  final int? thinkingBudget;

  /// Named thinking level for models that support it.
  final String? thinkingLevel;

  /// Encodes this native configuration.
  JsonObject toJson() => JsonObject({
    'includeThoughts': ?includeThoughts,
    'thinkingBudget': ?thinkingBudget,
    'thinkingLevel': ?thinkingLevel,
  });
}

/// One native Gemini safety setting.
final class GoogleSafetySetting {
  /// Creates a category/threshold safety rule.
  GoogleSafetySetting({required String category, required String threshold})
    : category = _nonEmpty(category, 'category'),
      threshold = _nonEmpty(threshold, 'threshold');

  /// Native harm category.
  final String category;

  /// Native blocking threshold.
  final String threshold;

  /// Encodes this rule.
  JsonObject toJson() => JsonObject({'category': category, 'threshold': threshold});
}

/// Native GenerateContent sampling and output configuration.
final class GoogleGenerationConfig {
  /// Creates native generation configuration.
  GoogleGenerationConfig({
    this.candidateCount,
    this.maxOutputTokens,
    this.temperature,
    this.topP,
    Iterable<String>? stopSequences,
    this.thinkingConfig,
    this.responseMimeType,
    this.responseJsonSchema,
    JsonObject? extensions,
  }) : stopSequences = stopSequences == null ? null : List.unmodifiable(stopSequences),
       extensions = extensions ?? JsonObject({}) {
    if (candidateCount != null && candidateCount! <= 0) {
      throw ArgumentError.value(candidateCount, 'candidateCount', 'must be positive');
    }
    if (maxOutputTokens != null && maxOutputTokens! <= 0) {
      throw ArgumentError.value(maxOutputTokens, 'maxOutputTokens', 'must be positive');
    }
  }

  /// Requested number of candidates.
  final int? candidateCount;

  /// Requested output-token limit.
  final int? maxOutputTokens;

  /// Native temperature.
  final double? temperature;

  /// Native nucleus-sampling threshold.
  final double? topP;

  /// Native stop sequences, when explicitly supplied.
  final List<String>? stopSequences;

  /// Native thinking configuration.
  final GoogleThinkingConfig? thinkingConfig;

  /// Requested response media type.
  final String? responseMimeType;

  /// Unmodified native JSON Schema.
  final JsonObject? responseJsonSchema;

  /// Immutable fields outside the typed snapshot.
  final JsonObject extensions;

  /// Encodes this native configuration.
  JsonObject toJson() => JsonObject({
    ...extensions.toDart(),
    'candidateCount': ?candidateCount,
    'maxOutputTokens': ?maxOutputTokens,
    'temperature': ?temperature,
    'topP': ?topP,
    'stopSequences': ?stopSequences,
    if (thinkingConfig case final value?) 'thinkingConfig': value.toJson().toDart(),
    'responseMimeType': ?responseMimeType,
    if (responseJsonSchema case final value?) 'responseJsonSchema': value.toDart(),
  });
}

/// One explicit native GenerateContent request.
final class GoogleGenerateContentRequest {
  /// Creates a native request for an authoritative `models/{id}` resource.
  GoogleGenerateContentRequest({
    required String model,
    required Iterable<GoogleContent> contents,
    this.systemInstruction,
    this.generationConfig,
    Iterable<GoogleSafetySetting>? safetySettings,
    this.cachedContent,
    Iterable<GoogleToolDefinition>? tools,
    this.toolConfig,
    this.serviceTier,
    this.store,
    JsonObject? extraBody,
  }) : model = _modelName(model),
       contents = List.unmodifiable(contents),
       safetySettings = safetySettings == null ? null : List.unmodifiable(safetySettings),
       tools = tools == null ? null : List.unmodifiable(tools),
       extraBody = extraBody ?? JsonObject({}) {
    if (this.contents.isEmpty) {
      throw ArgumentError.value(contents, 'contents', 'must not be empty');
    }
    final collision = this.extraBody.toDart().keys.where(_requestFields.contains).firstOrNull;
    if (collision != null) {
      throw ArgumentError.value(collision, 'extraBody', 'collides with a typed request field');
    }
  }

  /// Authoritative model resource name.
  final String model;

  /// Ordered conversation contents.
  final List<GoogleContent> contents;

  /// Optional system instruction.
  final GoogleContent? systemInstruction;

  /// Optional native generation configuration.
  final GoogleGenerationConfig? generationConfig;

  /// Optional replacement safety policy.
  final List<GoogleSafetySetting>? safetySettings;

  /// Optional authoritative `cachedContents/{id}` resource name.
  final String? cachedContent;

  /// Native tools.
  final List<GoogleToolDefinition>? tools;

  /// Native tool-selection configuration.
  final GoogleToolConfig? toolConfig;

  /// Native service tier.
  final String? serviceTier;

  /// Native request logging choice.
  final bool? store;

  /// Forward-compatible request fields.
  final JsonObject extraBody;

  /// Encodes the request body; the model remains in the resource path.
  JsonObject toJson() => JsonObject({
    ...extraBody.toDart(),
    'contents': contents.map((content) => content.toJson().toDart()).toList(),
    if (systemInstruction case final value?) 'systemInstruction': value.toJson().toDart(),
    if (generationConfig case final value?) 'generationConfig': value.toJson().toDart(),
    if (safetySettings case final values?)
      'safetySettings': values.map((value) => value.toJson().toDart()).toList(),
    'cachedContent': ?cachedContent,
    if (tools case final values?) 'tools': values.map((value) => value.toJson().toDart()).toList(),
    if (toolConfig case final value?) 'toolConfig': value.toJson().toDart(),
    'serviceTier': ?serviceTier,
    'store': ?store,
  });
}

/// One native candidate returned by GenerateContent.
final class GoogleCandidate {
  GoogleCandidate._({
    required this.content,
    required this.finishReason,
    required this.index,
    required this.extensions,
    required this.raw,
  });

  /// Decodes one candidate while retaining all fields.
  factory GoogleCandidate.fromJson(JsonObject json) {
    final value = json.toDart();
    return GoogleCandidate._(
      content: switch (value['content']) {
        null => null,
        final Map<String, Object?> content => GoogleContent.fromJson(JsonObject(content)),
        _ => throw const FormatException('candidate.content must be an object.'),
      },
      finishReason: _optionalString(value, 'finishReason'),
      index: _optionalInt(value, 'index'),
      extensions: JsonObject(_without(value, {'content', 'finishReason', 'index'})),
      raw: json,
    );
  }

  /// Generated native content.
  final GoogleContent? content;

  /// Native terminal reason, when present.
  final String? finishReason;

  /// Native candidate index, when present.
  final int? index;

  /// Immutable candidate fields outside the typed snapshot.
  final JsonObject extensions;

  /// Complete native candidate payload.
  final JsonObject raw;
}

/// Prompt-level feedback returned when generation is blocked.
final class GooglePromptFeedback {
  GooglePromptFeedback._({required this.blockReason, required this.extensions, required this.raw});

  /// Decodes prompt feedback while retaining all fields.
  factory GooglePromptFeedback.fromJson(JsonObject json) {
    final value = json.toDart();
    return GooglePromptFeedback._(
      blockReason: _optionalString(value, 'blockReason'),
      extensions: JsonObject(_without(value, {'blockReason'})),
      raw: json,
    );
  }

  /// Native block reason.
  final String? blockReason;

  /// Immutable feedback fields outside the typed snapshot.
  final JsonObject extensions;

  /// Complete native feedback payload.
  final JsonObject raw;
}

/// Native token accounting returned by GenerateContent.
final class GoogleUsageMetadata {
  GoogleUsageMetadata._({
    required this.promptTokenCount,
    required this.candidatesTokenCount,
    required this.totalTokenCount,
    required this.extensions,
    required this.raw,
  });

  /// Decodes usage while retaining provider-specific accounting.
  factory GoogleUsageMetadata.fromJson(JsonObject json) {
    final value = json.toDart();
    return GoogleUsageMetadata._(
      promptTokenCount: _optionalInt(value, 'promptTokenCount'),
      candidatesTokenCount: _optionalInt(value, 'candidatesTokenCount'),
      totalTokenCount: _optionalInt(value, 'totalTokenCount'),
      extensions: JsonObject(
        _without(value, {'promptTokenCount', 'candidatesTokenCount', 'totalTokenCount'}),
      ),
      raw: json,
    );
  }

  /// Input tokens.
  final int? promptTokenCount;

  /// Generated candidate tokens.
  final int? candidatesTokenCount;

  /// Total tokens.
  final int? totalTokenCount;

  /// Additional native accounting fields.
  final JsonObject extensions;

  /// Complete native usage payload.
  final JsonObject raw;

  /// Converts to common cumulative usage.
  Usage toCommon() => Usage(
    inputTokens: promptTokenCount,
    outputTokens: candidatesTokenCount,
    totalTokens: totalTokenCount,
  );
}

/// One decoded GenerateContent response.
final class GoogleGenerateContentResponse {
  GoogleGenerateContentResponse._({
    required this.candidates,
    required this.promptFeedback,
    required this.usageMetadata,
    required this.modelVersion,
    required this.responseId,
    required this.extensions,
    required this.raw,
  });

  /// Decodes the pinned response fields while retaining unknown fields.
  factory GoogleGenerateContentResponse.fromJson(JsonObject json) {
    final value = json.toDart();
    final candidates = value['candidates'];
    if (candidates != null && candidates is! List<Object?>) {
      throw const FormatException('candidates must be an array.');
    }
    return GoogleGenerateContentResponse._(
      candidates: List.unmodifiable(
        (candidates as List<Object?>? ?? const []).map(
          (candidate) => GoogleCandidate.fromJson(JsonObject.fromDart(candidate)),
        ),
      ),
      promptFeedback: switch (value['promptFeedback']) {
        null => null,
        final Map<String, Object?> feedback => GooglePromptFeedback.fromJson(JsonObject(feedback)),
        _ => throw const FormatException('promptFeedback must be an object.'),
      },
      usageMetadata: switch (value['usageMetadata']) {
        null => null,
        final Map<String, Object?> usage => GoogleUsageMetadata.fromJson(JsonObject(usage)),
        _ => throw const FormatException('usageMetadata must be an object.'),
      },
      modelVersion: _optionalString(value, 'modelVersion'),
      responseId: _optionalString(value, 'responseId'),
      extensions: JsonObject(
        _without(value, {
          'candidates',
          'promptFeedback',
          'usageMetadata',
          'modelVersion',
          'responseId',
        }),
      ),
      raw: json,
    );
  }

  /// Candidate responses in native order.
  final List<GoogleCandidate> candidates;

  /// Prompt-level block metadata.
  final GooglePromptFeedback? promptFeedback;

  /// Native usage accounting.
  final GoogleUsageMetadata? usageMetadata;

  /// Actual native model version.
  final String? modelVersion;

  /// Provider response identity.
  final String? responseId;

  /// Immutable response fields outside the typed snapshot.
  final JsonObject extensions;

  /// Complete native response payload.
  final JsonObject raw;
}

/// One typed native response record from a GenerateContent SSE stream.
final class GoogleGenerateContentChunk {
  /// Creates a chunk with its raw payload and HTTP metadata.
  const GoogleGenerateContentChunk({
    required this.value,
    required this.payload,
    required this.metadata,
  });

  /// Decoded native response fragment.
  final GoogleGenerateContentResponse value;

  /// Complete immutable native fragment.
  final NativePayload payload;

  /// HTTP metadata for the stream.
  final ResponseMetadata metadata;
}

/// One explicit native token-count request.
final class GoogleCountTokensRequest {
  /// Creates a token-count request with exactly one native input form.
  GoogleCountTokensRequest({
    required String model,
    Iterable<GoogleContent>? contents,
    this.generateContentRequest,
  }) : model = _modelName(model),
       contents = contents == null ? null : List.unmodifiable(contents) {
    if ((this.contents == null) == (generateContentRequest == null)) {
      throw ArgumentError('Exactly one of contents and generateContentRequest is required.');
    }
    if (this.contents?.isEmpty ?? false) {
      throw ArgumentError.value(contents, 'contents', 'must not be empty');
    }
    if (generateContentRequest != null && generateContentRequest!.model != this.model) {
      throw ArgumentError.value(
        generateContentRequest!.model,
        'generateContentRequest',
        'must target the same model',
      );
    }
  }

  /// Selected model resource.
  final String model;

  /// Content-only counting input.
  final List<GoogleContent>? contents;

  /// Full GenerateContent-shaped counting input.
  final GoogleGenerateContentRequest? generateContentRequest;

  /// Encodes the request body.
  JsonObject toJson() => JsonObject({
    if (contents case final values?)
      'contents': values.map((value) => value.toJson().toDart()).toList(),
    if (generateContentRequest case final value?) 'generateContentRequest': value.toJson().toDart(),
  });
}

/// Native token-count result.
final class GoogleCountTokensResponse {
  GoogleCountTokensResponse._({
    required this.totalTokens,
    required this.cachedContentTokenCount,
    required this.extensions,
    required this.raw,
  });

  /// Decodes a count while retaining modality details and future fields.
  factory GoogleCountTokensResponse.fromJson(JsonObject json) {
    final value = json.toDart();
    return GoogleCountTokensResponse._(
      totalTokens: _requiredInt(value, 'totalTokens'),
      cachedContentTokenCount: _optionalInt(value, 'cachedContentTokenCount'),
      extensions: JsonObject(_without(value, {'totalTokens', 'cachedContentTokenCount'})),
      raw: json,
    );
  }

  /// Total input tokens.
  final int totalTokens;

  /// Cached tokens, when reported.
  final int? cachedContentTokenCount;

  /// Native modality and future accounting.
  final JsonObject extensions;

  /// Complete response.
  final JsonObject raw;
}

const _requestFields = {
  'contents',
  'systemInstruction',
  'generationConfig',
  'safetySettings',
  'cachedContent',
  'tools',
  'toolConfig',
  'serviceTier',
  'store',
};

String _modelName(String value) {
  if (!value.startsWith('models/') ||
      value.length == 'models/'.length ||
      value.substring(7).contains('/')) {
    throw ArgumentError.value(value, 'model', 'must have the format models/{id}');
  }
  return value;
}

String _nonEmpty(String value, String name) {
  if (value.isEmpty) throw ArgumentError.value(value, name, 'must not be empty');
  return value;
}

List<Object?> _list(Map<String, Object?> value, String key) {
  final field = value[key];
  if (field is! List<Object?>) throw FormatException('$key must be an array.');
  return field;
}

String? _optionalString(Map<String, Object?> value, String key) {
  final field = value[key];
  if (field == null) return null;
  if (field is! String) throw FormatException('$key must be a string.');
  return field;
}

int? _optionalInt(Map<String, Object?> value, String key) {
  final field = value[key];
  if (field == null) return null;
  if (field is! int) throw FormatException('$key must be an integer.');
  return field;
}

int _requiredInt(Map<String, Object?> value, String key) {
  final field = value[key];
  if (field is! int) throw FormatException('$key must be an integer.');
  return field;
}

String _requiredString(Map<String, Object?> value, String key) {
  final field = value[key];
  if (field is! String || field.isEmpty) throw FormatException('$key must be a nonempty string.');
  return field;
}

bool? _optionalBool(Map<String, Object?> value, String key) {
  final field = value[key];
  if (field == null) return null;
  if (field is! bool) throw FormatException('$key must be a boolean.');
  return field;
}

JsonObject? _optionalJsonObject(Map<String, Object?> value, String key) {
  final field = value[key];
  if (field == null) return null;
  if (field is! Map<String, Object?>) throw FormatException('$key must be an object.');
  return JsonObject(field);
}

T? _optionalObject<T>(
  Map<String, Object?> value,
  String key,
  T Function(JsonObject) decode,
) {
  final field = value[key];
  if (field == null) return null;
  if (field is! Map<String, Object?>) throw FormatException('$key must be an object.');
  return decode(JsonObject(field));
}

Map<String, Object?> _without(Map<String, Object?> value, Set<String> keys) =>
    Map.fromEntries(value.entries.where((entry) => !keys.contains(entry.key)));
