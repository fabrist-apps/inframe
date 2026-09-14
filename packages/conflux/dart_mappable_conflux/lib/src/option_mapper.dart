import 'package:conflux/option.dart';
import 'package:dart_mappable/dart_mappable.dart';

/// Serializes present values using the registered mapper for their contents.
///
/// None encodes to an internal marker removed by [OptionFieldsHook].
/// Unremoved markers remain in toValue/toMap output and are not JSON encodable.
/// dart_mappable handles raw null before invoking custom mappers; the class hook
/// preserves explicit null for decoding into Some(null).
final class OptionMapper extends SimpleMapper1<Option<dynamic>> {
  const OptionMapper();

  @override
  Function get typeFactory {
    // dart_mappable supplies a generic callback with a caller-specific return type.
    // ignore: avoid_dynamic_calls
    return <T>(Function f) => f<Option<T>>();
  }

  @override
  Option<T> decode<T>(Object value) =>
      Some(container.fromValue<T>(value is _PresentNull ? null : value));

  @override
  Object? encode<T>(Option<T> self) => switch (self) {
    Some<T>(value: None()) => throw const FormatException('Some(None()) cannot be serialized.'),
    Some<T>(:final value) => container.toValue<T>(value),
    None() => const _Absent(),
  };
}

/// Omits absent fields and preserves missing versus null during decoding.
///
/// Paths use serialized keys separated by dots, for example `profile.nickname`.
/// Traversal follows maps only; absent or non-map parents are left unchanged.
/// Literal dots in keys and array indexing are not supported.
/// Input maps are copied along each modified path.
final class OptionFieldsHook extends MappingHook {
  const OptionFieldsHook(this.keys);

  final List<String> keys;

  @override
  Object? beforeDecode(Object? value) => _transform(value, decoding: true);

  @override
  Object? afterEncode(Object? value) => _transform(value, decoding: false);

  Object? _transform(Object? value, {required bool decoding}) {
    if (value is! Map<String, dynamic>) return value;

    var result = value;
    for (final key in keys) {
      result = _transformPath(result, key.split('.'), decoding: decoding);
    }

    return result;
  }

  Map<String, dynamic> _transformPath(
    Map<String, dynamic> value,
    List<String> path, {
    required bool decoding,
  }) {
    final key = path.first;
    final result = Map<String, dynamic>.of(value);
    if (path.length > 1) {
      final child = value[key];
      if (child is Map<String, dynamic>) {
        result[key] = _transformPath(child, path.sublist(1), decoding: decoding);
      }
    } else if (decoding) {
      if (!value.containsKey(key)) {
        result[key] = const None();
      } else if (value[key] == null) {
        result[key] = const _PresentNull();
      }
    } else if (value[key] is _Absent) {
      result.remove(key);
    }

    return result;
  }
}

final class _Absent {
  const _Absent();
}

final class _PresentNull {
  const _PresentNull();
}
