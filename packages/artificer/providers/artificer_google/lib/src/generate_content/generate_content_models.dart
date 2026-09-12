import 'package:artificer_core/artificer_core.dart';
import 'package:artificer_core/json.dart';

/// One native Gemini content part from the pinned GenerateContent schema.
final class GooglePart {
  /// Creates a text part.
  GooglePart.text(String text, {JsonObject? extensions})
    : text = _nonEmpty(text, 'text'),
      extensions = extensions ?? JsonObject({});

  GooglePart._({required this.text, required this.extensions});

  /// Decodes a part while retaining fields outside this slice's typed surface.
  factory GooglePart.fromJson(JsonObject json) {
    final value = json.toDart();
    final text = value['text'];
    if (text != null && text is! String) {
      throw const FormatException('part.text must be a string.');
    }
    return GooglePart._(
      text: text as String?,
      extensions: JsonObject(_without(value, {'text'})),
    );
  }

  /// Text carried by this part, when it is a text part.
  final String? text;

  /// Immutable fields not yet modeled by this package snapshot.
  final JsonObject extensions;

  /// The complete native part.
  JsonObject toJson() => JsonObject({...extensions.toDart(), 'text': ?text});
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
    JsonObject? extraBody,
  }) : model = _modelName(model),
       contents = List.unmodifiable(contents),
       safetySettings = safetySettings == null ? null : List.unmodifiable(safetySettings),
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

const _requestFields = {
  'contents',
  'systemInstruction',
  'generationConfig',
  'safetySettings',
  'cachedContent',
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

Map<String, Object?> _without(Map<String, Object?> value, Set<String> keys) =>
    Map.fromEntries(value.entries.where((entry) => !keys.contains(entry.key)));
