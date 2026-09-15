import 'package:ack/ack.dart';

/// Translates an Ack failure, retaining its diagnostic and original value.
///
/// Scalar arguments use Ack’s [debugName]; nested fields use their JSON Pointer.
void validateArgument<B extends Object, T extends Object>(
  AckSchema<B, T> schema,
  T value, {
  String? debugName,
}) {
  final result = schema.safeEncode(value, debugName: debugName);
  if (result.isOk) return;
  var error = result.getError();
  while (error is SchemaNestedError && error.errors.isNotEmpty) {
    error = error.errors.first;
  }
  final message = switch (error) {
    SchemaConstraintsError(:final constraints) when constraints.isNotEmpty =>
      constraints.first.message,
    _ => error.message,
  };
  throw ArgumentError.value(
    error.argumentValue(value),
    error.path == '#' ? error.name : error.path,
    message,
  );
}

extension on SchemaError {
  // Codec failures can carry encoded values. Recover the original argument
  // from the runtime object so a Duration error still reports a Duration.
  Object? argumentValue(Object root) {
    Object? current = root;
    for (final encoded in path.split('/').skip(1)) {
      final segment = encoded.replaceAll('~1', '/').replaceAll('~0', '~');
      switch (current) {
        case Map<Object?, Object?>():
          if (!current.containsKey(segment)) return value;
          current = current[segment];
        case List<Object?>():
          final index = int.tryParse(segment);
          if (index == null || index < 0 || index >= current.length) return value;
          current = current[index];
        default:
          return value;
      }
    }
    return current;
  }
}
