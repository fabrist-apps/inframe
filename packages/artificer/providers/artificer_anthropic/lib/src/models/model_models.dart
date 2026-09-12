import 'package:artificer_core/json.dart';

/// Whether one model capability is supported.
final class AnthropicModelCapabilitySupport {
  /// Decodes one capability flag.
  factory AnthropicModelCapabilitySupport.fromJson(JsonObject raw) {
    final value = raw.toDart();
    return AnthropicModelCapabilitySupport._(
      supported: _boolean(value, 'supported'),
      raw: raw,
      extensions: JsonObject(_without(value, {'supported'})),
    );
  }

  const AnthropicModelCapabilitySupport._({
    required this.supported,
    required this.raw,
    required this.extensions,
  });

  /// Whether the capability is supported.
  final bool supported;

  /// Complete immutable capability object.
  final JsonObject raw;

  /// Fields outside the pinned typed shape.
  final JsonObject extensions;
}

/// Context-management features advertised by a model.
final class AnthropicContextManagementCapability {
  /// Decodes context-management capability details.
  factory AnthropicContextManagementCapability.fromJson(JsonObject raw) {
    final value = raw.toDart();
    return AnthropicContextManagementCapability._(
      clearThinking20251015: _nullableCapability(
        value,
        'clear_thinking_20251015',
      ),
      clearToolUses20250919: _nullableCapability(
        value,
        'clear_tool_uses_20250919',
      ),
      compact20260112: _nullableCapability(value, 'compact_20260112'),
      supported: _boolean(value, 'supported'),
      raw: raw,
      extensions: JsonObject(
        _without(value, {
          'clear_thinking_20251015',
          'clear_tool_uses_20250919',
          'compact_20260112',
          'supported',
        }),
      ),
    );
  }

  const AnthropicContextManagementCapability._({
    required this.clearThinking20251015,
    required this.clearToolUses20250919,
    required this.compact20260112,
    required this.supported,
    required this.raw,
    required this.extensions,
  });

  /// Support for the `clear_thinking_20251015` strategy.
  final AnthropicModelCapabilitySupport? clearThinking20251015;

  /// Support for the `clear_tool_uses_20250919` strategy.
  final AnthropicModelCapabilitySupport? clearToolUses20250919;

  /// Support for the `compact_20260112` strategy.
  final AnthropicModelCapabilitySupport? compact20260112;

  /// Whether context management is supported.
  final bool supported;

  /// Complete immutable capability object.
  final JsonObject raw;

  /// Fields outside the pinned typed shape.
  final JsonObject extensions;
}

/// Effort levels advertised by a model.
final class AnthropicEffortCapability {
  /// Decodes effort capability details.
  factory AnthropicEffortCapability.fromJson(JsonObject raw) {
    final value = raw.toDart();
    return AnthropicEffortCapability._(
      high: _capability(value, 'high'),
      low: _capability(value, 'low'),
      max: _capability(value, 'max'),
      medium: _capability(value, 'medium'),
      supported: _boolean(value, 'supported'),
      xhigh: _nullableCapability(value, 'xhigh'),
      raw: raw,
      extensions: JsonObject(
        _without(value, {'high', 'low', 'max', 'medium', 'supported', 'xhigh'}),
      ),
    );
  }

  const AnthropicEffortCapability._({
    required this.high,
    required this.low,
    required this.max,
    required this.medium,
    required this.supported,
    required this.xhigh,
    required this.raw,
    required this.extensions,
  });

  /// High-effort support.
  final AnthropicModelCapabilitySupport high;

  /// Low-effort support.
  final AnthropicModelCapabilitySupport low;

  /// Maximum-effort support.
  final AnthropicModelCapabilitySupport max;

  /// Medium-effort support.
  final AnthropicModelCapabilitySupport medium;

  /// Whether reasoning effort is supported.
  final bool supported;

  /// Extra-high-effort support, when reported.
  final AnthropicModelCapabilitySupport? xhigh;

  /// Complete immutable capability object.
  final JsonObject raw;

  /// Fields outside the pinned typed shape.
  final JsonObject extensions;
}

/// Thinking modes advertised by a model.
final class AnthropicThinkingTypes {
  /// Decodes supported thinking modes.
  factory AnthropicThinkingTypes.fromJson(JsonObject raw) {
    final value = raw.toDart();
    return AnthropicThinkingTypes._(
      adaptive: _capability(value, 'adaptive'),
      enabled: _capability(value, 'enabled'),
      raw: raw,
      extensions: JsonObject(_without(value, {'adaptive', 'enabled'})),
    );
  }

  const AnthropicThinkingTypes._({
    required this.adaptive,
    required this.enabled,
    required this.raw,
    required this.extensions,
  });

  /// Adaptive-thinking support.
  final AnthropicModelCapabilitySupport adaptive;

  /// Enabled-thinking support.
  final AnthropicModelCapabilitySupport enabled;

  /// Complete immutable modes object.
  final JsonObject raw;

  /// Fields outside the pinned typed shape.
  final JsonObject extensions;
}

/// Thinking features advertised by a model.
final class AnthropicThinkingCapability {
  /// Decodes thinking capability details.
  factory AnthropicThinkingCapability.fromJson(JsonObject raw) {
    final value = raw.toDart();
    return AnthropicThinkingCapability._(
      supported: _boolean(value, 'supported'),
      types: AnthropicThinkingTypes.fromJson(_object(value, 'types')),
      raw: raw,
      extensions: JsonObject(_without(value, {'supported', 'types'})),
    );
  }

  const AnthropicThinkingCapability._({
    required this.supported,
    required this.types,
    required this.raw,
    required this.extensions,
  });

  /// Whether thinking is supported.
  final bool supported;

  /// Supported thinking configurations.
  final AnthropicThinkingTypes types;

  /// Complete immutable capability object.
  final JsonObject raw;

  /// Fields outside the pinned typed shape.
  final JsonObject extensions;
}

/// Native capabilities returned for an Anthropic model.
final class AnthropicModelCapabilities {
  /// Decodes model capability metadata.
  factory AnthropicModelCapabilities.fromJson(JsonObject raw) {
    final value = raw.toDart();
    return AnthropicModelCapabilities._(
      batch: _capability(value, 'batch'),
      citations: _capability(value, 'citations'),
      codeExecution: _capability(value, 'code_execution'),
      contextManagement: AnthropicContextManagementCapability.fromJson(
        _object(value, 'context_management'),
      ),
      effort: AnthropicEffortCapability.fromJson(_object(value, 'effort')),
      imageInput: _capability(value, 'image_input'),
      pdfInput: _capability(value, 'pdf_input'),
      structuredOutputs: _capability(value, 'structured_outputs'),
      thinking: AnthropicThinkingCapability.fromJson(
        _object(value, 'thinking'),
      ),
      raw: raw,
      extensions: JsonObject(
        _without(value, {
          'batch',
          'citations',
          'code_execution',
          'context_management',
          'effort',
          'image_input',
          'pdf_input',
          'structured_outputs',
          'thinking',
        }),
      ),
    );
  }

  const AnthropicModelCapabilities._({
    required this.batch,
    required this.citations,
    required this.codeExecution,
    required this.contextManagement,
    required this.effort,
    required this.imageInput,
    required this.pdfInput,
    required this.structuredOutputs,
    required this.thinking,
    required this.raw,
    required this.extensions,
  });

  /// Batch API support.
  final AnthropicModelCapabilitySupport batch;

  /// Citation-generation support.
  final AnthropicModelCapabilitySupport citations;

  /// Code-execution tool support.
  final AnthropicModelCapabilitySupport codeExecution;

  /// Context-management support.
  final AnthropicContextManagementCapability contextManagement;

  /// Reasoning-effort support.
  final AnthropicEffortCapability effort;

  /// Image-input support.
  final AnthropicModelCapabilitySupport imageInput;

  /// PDF-input support.
  final AnthropicModelCapabilitySupport pdfInput;

  /// Structured-output support.
  final AnthropicModelCapabilitySupport structuredOutputs;

  /// Thinking support.
  final AnthropicThinkingCapability thinking;

  /// Complete immutable capabilities object.
  final JsonObject raw;

  /// Fields outside the pinned typed shape.
  final JsonObject extensions;
}

/// One model returned by native Anthropic discovery.
final class AnthropicModel {
  /// Decodes one native model object.
  factory AnthropicModel.fromJson(JsonObject raw) {
    final value = raw.toDart();
    if (_string(value, 'type') != 'model') {
      throw const FormatException('type must be model.');
    }
    return AnthropicModel._(
      id: _string(value, 'id'),
      capabilities: switch (_nullableObject(value, 'capabilities')) {
        final capabilities? => AnthropicModelCapabilities.fromJson(capabilities),
        null => null,
      },
      createdAt: _string(value, 'created_at'),
      displayName: _string(value, 'display_name'),
      maxInputTokens: _nullableNonnegativeInteger(value, 'max_input_tokens'),
      maxTokens: _nullableNonnegativeInteger(value, 'max_tokens'),
      raw: raw,
      extensions: JsonObject(
        _without(value, {
          'id',
          'capabilities',
          'created_at',
          'display_name',
          'max_input_tokens',
          'max_tokens',
          'type',
        }),
      ),
    );
  }

  const AnthropicModel._({
    required this.id,
    required this.capabilities,
    required this.createdAt,
    required this.displayName,
    required this.maxInputTokens,
    required this.maxTokens,
    required this.raw,
    required this.extensions,
  });

  /// Provider-local model identifier.
  final String id;

  /// Native capability metadata, when available.
  final AnthropicModelCapabilities? capabilities;

  /// Exact RFC 3339 release timestamp returned by Anthropic.
  final String createdAt;

  /// Human-readable model name.
  final String displayName;

  /// Maximum input context size, when reported.
  final int? maxInputTokens;

  /// Maximum `max_tokens` request value, when reported.
  final int? maxTokens;

  /// Complete immutable model object.
  final JsonObject raw;

  /// Fields outside the pinned typed shape.
  final JsonObject extensions;
}

/// One explicitly fetched Anthropic model page.
final class AnthropicModelPage {
  /// Decodes one model page without following its cursors.
  factory AnthropicModelPage.fromJson(JsonObject raw) {
    final value = raw.toDart();
    return AnthropicModelPage._(
      data: _list(value, 'data').map(
        (item) => AnthropicModel.fromJson(_jsonObject(item, 'data item')),
      ),
      hasMore: _boolean(value, 'has_more'),
      firstId: _nullableString(value, 'first_id'),
      lastId: _nullableString(value, 'last_id'),
      raw: raw,
      extensions: JsonObject(
        _without(value, {'data', 'has_more', 'first_id', 'last_id'}),
      ),
    );
  }

  AnthropicModelPage._({
    required Iterable<AnthropicModel> data,
    required this.hasMore,
    required this.firstId,
    required this.lastId,
    required this.raw,
    required this.extensions,
  }) : data = List.unmodifiable(data);

  /// Models in this page.
  final List<AnthropicModel> data;

  /// Whether Anthropic reports another page.
  final bool hasMore;

  /// First model cursor, when the page has one.
  final String? firstId;

  /// Last model cursor, when the page has one.
  final String? lastId;

  /// Complete immutable page object.
  final JsonObject raw;

  /// Fields outside the pinned typed shape.
  final JsonObject extensions;
}

AnthropicModelCapabilitySupport _capability(
  Map<String, Object?> value,
  String key,
) => AnthropicModelCapabilitySupport.fromJson(_object(value, key));

AnthropicModelCapabilitySupport? _nullableCapability(
  Map<String, Object?> value,
  String key,
) => switch (_nullableObject(value, key)) {
  final raw? => AnthropicModelCapabilitySupport.fromJson(raw),
  null => null,
};

JsonObject _object(Map<String, Object?> value, String key) => _jsonObject(value[key], key);

JsonObject _jsonObject(Object? value, String name) {
  if (value is! Map<String, Object?>) {
    throw FormatException('$name must be an object.');
  }
  return JsonObject(value);
}

JsonObject? _nullableObject(Map<String, Object?> value, String key) {
  final field = value[key];
  if (field == null) return null;
  return _jsonObject(field, key);
}

String _string(Map<String, Object?> value, String key) {
  final field = value[key];
  if (field is! String) throw FormatException('$key must be a string.');
  return field;
}

String? _nullableString(Map<String, Object?> value, String key) {
  final field = value[key];
  if (field == null) return null;
  if (field is! String) throw FormatException('$key must be a string or null.');
  return field;
}

bool _boolean(Map<String, Object?> value, String key) {
  final field = value[key];
  if (field is! bool) throw FormatException('$key must be a boolean.');
  return field;
}

int? _nullableNonnegativeInteger(Map<String, Object?> value, String key) {
  final field = value[key];
  if (field == null) return null;
  if (field is! int || field < 0) {
    throw FormatException('$key must be a nonnegative integer or null.');
  }
  return field;
}

List<Object?> _list(Map<String, Object?> value, String key) {
  final field = value[key];
  if (field is! List<Object?>) throw FormatException('$key must be an array.');
  return field;
}

Map<String, Object?> _without(Map<String, Object?> value, Set<String> keys) => {
  for (final entry in value.entries)
    if (!keys.contains(entry.key)) entry.key: entry.value,
};
