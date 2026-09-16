import 'package:artificer_core/src/json/json_value.dart';
import 'package:dart_mappable/dart_mappable.dart';

/// Keeps raw JSON fields separate from dart_mappable's object serialization.
///
/// Without this field hook, registered Dart objects (including DateTime) can
/// silently become JSON strings or maps. This checks the JSON boundary only;
/// it neither copies collections nor validates an application's schema.
class JsonValueHook extends MappingHook {
  /// Creates a stateless JSON boundary check.
  const JsonValueHook();

  @override
  Object? beforeEncode(Object? value) {
    JsonValues.validate(value);
    return value;
  }

  @override
  Object? beforeDecode(Object? value) {
    JsonValues.validate(value);
    return value;
  }
}
