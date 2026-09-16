import 'package:artificer_core/src/errors.dart';
import 'package:artificer_core/src/json/json_value.dart';
import 'package:conflux/result.dart';

/// An endpoint's text-only request boundary, shared by native and common calls.
/// Provider packages supply their pinned field and hosted-tool inventory.
final class TextRequestPolicy {
  /// Creates a policy without making network requests.
  const TextRequestPolicy({
    required this.typedFields,
    this.hostedToolTypes = const {},
    this.unsupportedFields = const {},
    this.readOnlyFields = const {'id', 'created_at', 'usage', 'status', 'output'},
    this.storageField,
  });

  /// Authoritative typed keys that extras may never replace, even when omitted.
  final Set<String> typedFields;

  /// Pinned provider-hosted tool discriminators allowed by this endpoint.
  final Set<String> hostedToolTypes;

  /// Common options that this endpoint cannot represent faithfully.
  final Set<String> unsupportedFields;

  /// Response-only keys that cannot become request configuration.
  final Set<String> readOnlyFields;

  /// Storage option forced to false for foreground inference when supported.
  final String? storageField;

  static const _deferredFields = {
    'files',
    'file',
    'file_id',
    'file_ids',
    'file_data',
    'file_uri',
    'file_url',
    'image_url',
    'input_image',
    'input_audio',
    'input_video',
    'input_file',
    'document',
    'documents',
    'inline_data',
    'inlineData',
    'fileData',
    'audio',
    'video',
    'image',
    'images',
    'session',
    'session_id',
    'previous_response_id',
    'previous_interaction_id',
    'conversation',
    'background',
    'modalities',
    'response_modalities',
    'responseModalities',
  };
  static const _deferredTypes = {
    'image',
    'image_url',
    'input_image',
    'audio',
    'input_audio',
    'video',
    'input_video',
    'document',
    'file',
    'input_file',
    'image_generation',
  };

  /// Resolves a native body and extras, returning expected failures as data.
  /// No caller collection is modified. Neutral new text fields remain intact.
  Result<Map<String, Object?>, AiError> prepare({
    required Map<String, Object?> native,
    Map<String, Object?> extraBody = const {},
  }) {
    try {
      JsonValues.validate(native);
      JsonValues.validate(extraBody);
    } on FormatException {
      return const Failure(InvalidRequestError('Request contains invalid JSON values.'));
    }
    for (final key in extraBody.keys) {
      if (typedFields.contains(key) || native.containsKey(key)) {
        return Failure(InvalidRequestError('extraBody collides with typed field: $key.'));
      }
    }
    final body = <String, Object?>{...native, ...extraBody};
    for (final key in body.keys) {
      if (readOnlyFields.contains(key)) {
        return Failure(InvalidRequestError('Response-only field is not a request option: $key.'));
      }
      if (unsupportedFields.contains(key)) {
        return Failure(
          UnsupportedFeatureError('Endpoint cannot represent this option.', feature: key),
        );
      }
    }
    final deferred = _findDeferred(body);
    if (deferred != null) {
      return Failure(
        UnsupportedFeatureError('Deferred text-inference feature.', feature: deferred),
      );
    }
    if (body['tools'] case final List<Object?> tools) {
      for (final tool in tools) {
        if (tool is! Map<String, Object?> || tool['type'] is! String) {
          return const Failure(InvalidRequestError('Tools require a typed discriminator.'));
        }
        final type = tool['type'];
        if (type != 'function' && !hostedToolTypes.contains(type)) {
          return const Failure(
            UnsupportedFeatureError('Tool is outside the pinned endpoint inventory.'),
          );
        }
      }
    }
    if (storageField case final key?) {
      if (body.containsKey(key) && body[key] != false) {
        return const Failure(UnsupportedFeatureError('Stored inference is deferred.'));
      }
      body[key] = false;
    }
    return Success(body);
  }

  String? _findDeferred(Object? value) {
    if (value is Map<String, Object?>) {
      for (final entry in value.entries) {
        // These dictionaries describe application JSON, not native input fields.
        if (entry.key == 'schema' || entry.key == 'parameters') continue;
        if (_deferredFields.contains(entry.key)) return entry.key;
        if (entry.key == 'type' && _deferredTypes.contains(entry.value)) return '${entry.value}';
        final nested = _findDeferred(entry.value);
        if (nested != null) return nested;
      }
    } else if (value is List<Object?>) {
      for (final item in value) {
        final nested = _findDeferred(item);
        if (nested != null) return nested;
      }
    }
    return null;
  }
}
