import 'package:artificer_core/json.dart';

/// Native metadata for one Gemini model.
final class GoogleModel {
  GoogleModel._({
    required this.name,
    required this.baseModelId,
    required this.version,
    required this.displayName,
    required this.description,
    required this.inputTokenLimit,
    required this.outputTokenLimit,
    required this.supportedGenerationMethods,
    required this.thinking,
    required this.temperature,
    required this.maxTemperature,
    required this.topP,
    required this.topK,
    required this.extensions,
    required this.raw,
  });

  /// Decodes the 2026-09-12 model snapshot while retaining unknown fields.
  factory GoogleModel.fromJson(JsonObject json) {
    final value = json.toDart();
    final methods = value['supportedGenerationMethods'];
    if (methods != null &&
        (methods is! List<Object?> || methods.any((method) => method is! String))) {
      throw const FormatException('supportedGenerationMethods must contain strings.');
    }
    return GoogleModel._(
      name: _requiredString(value, 'name'),
      baseModelId: _optionalString(value, 'baseModelId'),
      version: _optionalString(value, 'version'),
      displayName: _optionalString(value, 'displayName'),
      description: _optionalString(value, 'description'),
      inputTokenLimit: _optionalInt(value, 'inputTokenLimit'),
      outputTokenLimit: _optionalInt(value, 'outputTokenLimit'),
      supportedGenerationMethods: List.unmodifiable(
        (methods as List<Object?>? ?? const []).cast<String>(),
      ),
      thinking: _optionalBool(value, 'thinking'),
      temperature: _optionalDouble(value, 'temperature'),
      maxTemperature: _optionalDouble(value, 'maxTemperature'),
      topP: _optionalDouble(value, 'topP'),
      topK: _optionalInt(value, 'topK'),
      extensions: JsonObject(
        _without(value, {
          'name',
          'baseModelId',
          'version',
          'displayName',
          'description',
          'inputTokenLimit',
          'outputTokenLimit',
          'supportedGenerationMethods',
          'thinking',
          'temperature',
          'maxTemperature',
          'topP',
          'topK',
        }),
      ),
      raw: json,
    );
  }

  /// Authoritative `models/{id}` resource name.
  final String name;

  /// Provider-local base model ID.
  final String? baseModelId;

  /// Model version.
  final String? version;

  /// Human-readable model name.
  final String? displayName;

  /// Model description.
  final String? description;

  /// Maximum input token count.
  final int? inputTokenLimit;

  /// Maximum output token count.
  final int? outputTokenLimit;

  /// Native methods supported by the model.
  final List<String> supportedGenerationMethods;

  /// Whether the model declares thinking support.
  final bool? thinking;

  /// Default temperature.
  final double? temperature;

  /// Maximum accepted temperature.
  final double? maxTemperature;

  /// Default nucleus-sampling threshold.
  final double? topP;

  /// Default top-k value.
  final int? topK;

  /// Immutable fields outside the typed snapshot.
  final JsonObject extensions;

  /// Complete native model payload.
  final JsonObject raw;
}

/// One explicitly fetched page of native Gemini models.
final class GoogleModelPage {
  GoogleModelPage._({
    required this.models,
    required this.nextPageToken,
    required this.extensions,
    required this.raw,
  });

  /// Decodes a model page while retaining unknown page fields.
  factory GoogleModelPage.fromJson(JsonObject json) {
    final value = json.toDart();
    final models = value['models'];
    if (models != null && models is! List<Object?>) {
      throw const FormatException('models must be an array.');
    }
    return GoogleModelPage._(
      models: List.unmodifiable(
        (models as List<Object?>? ?? const []).map(
          (model) => GoogleModel.fromJson(JsonObject.fromDart(model)),
        ),
      ),
      nextPageToken: _optionalString(value, 'nextPageToken'),
      extensions: JsonObject(_without(value, {'models', 'nextPageToken'})),
      raw: json,
    );
  }

  /// Models returned on this page.
  final List<GoogleModel> models;

  /// Explicit cursor for a caller-selected next request.
  final String? nextPageToken;

  /// Immutable page fields outside the typed snapshot.
  final JsonObject extensions;

  /// Complete native page payload.
  final JsonObject raw;
}

String _requiredString(Map<String, Object?> value, String key) {
  final field = value[key];
  if (field is! String) throw FormatException('$key must be a string.');
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

bool? _optionalBool(Map<String, Object?> value, String key) {
  final field = value[key];
  if (field == null) return null;
  if (field is! bool) throw FormatException('$key must be a boolean.');
  return field;
}

double? _optionalDouble(Map<String, Object?> value, String key) {
  final field = value[key];
  if (field == null) return null;
  if (field is! num) throw FormatException('$key must be a number.');
  return field.toDouble();
}

Map<String, Object?> _without(Map<String, Object?> value, Set<String> keys) =>
    Map.fromEntries(value.entries.where((entry) => !keys.contains(entry.key)));
