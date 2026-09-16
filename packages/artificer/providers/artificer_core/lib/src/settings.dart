import 'package:dart_mappable/dart_mappable.dart';
part 'settings.mapper.dart';

/// An override that distinguishes inheritance, replacement and explicit removal.
@MappableClass(discriminatorKey: 'type')
sealed class Setting<T> with SettingMappable<T> {
  /// Creates an override.
  const Setting();

  /// Retains the inherited value.
  const factory Setting.inherit() = InheritSetting<T>;

  /// Replaces the inherited value, including a complete collection.
  const factory Setting.set(T value) = ValueSetting<T>;

  /// Removes the inherited field instead of sending JSON null.
  const factory Setting.clear() = ClearSetting<T>;

  /// Resolves without modifying or copying either value.
  T? resolve(T? inherited) => switch (this) {
    InheritSetting<T>() => inherited,
    ValueSetting<T>(:final value) => value,
    ClearSetting<T>() => null,
  };

  /// Decodes persisted map data.
  static const fromMap = SettingMapper.fromMap;

  /// Decodes a persisted JSON string.
  static const fromJson = SettingMapper.fromJson;
}

/// The inherit branch of an option override.
@MappableClass(discriminatorValue: 'inherit')
final class InheritSetting<T> extends Setting<T> with InheritSettingMappable<T> {
  /// Creates the inherit override.
  const InheritSetting();

  /// Decodes persisted map data.
  static const fromMap = InheritSettingMapper.fromMap;

  /// Decodes a persisted JSON string.
  static const fromJson = InheritSettingMapper.fromJson;
}

/// The set branch of an option override.
@MappableClass(discriminatorValue: 'set')
final class ValueSetting<T> extends Setting<T> with ValueSettingMappable<T> {
  /// Creates the set override.
  const ValueSetting(this.value);

  /// Replacement value, retained as supplied.
  final T value;

  /// Decodes persisted map data.
  static const fromMap = ValueSettingMapper.fromMap;

  /// Decodes a persisted JSON string.
  static const fromJson = ValueSettingMapper.fromJson;
}

/// The clear branch of an option override.
@MappableClass(discriminatorValue: 'clear')
final class ClearSetting<T> extends Setting<T> with ClearSettingMappable<T> {
  /// Creates the clear override.
  const ClearSetting();

  /// Decodes persisted map data.
  static const fromMap = ClearSettingMapper.fromMap;

  /// Decodes a persisted JSON string.
  static const fromJson = ClearSettingMapper.fromJson;
}

/// Presence in a native schema, independent of domain option inheritance.
@MappableClass()
final class NativeField<T> with NativeFieldMappable<T> {
  /// Creates an omitted or explicitly supplied field.
  NativeField({required this.isPresent, this.value}) {
    if (!isPresent && value != null) throw ArgumentError('An omitted field cannot carry a value.');
  }

  /// Omits the field from wire JSON.
  NativeField.omitted() : this(isPresent: false);

  /// Sends a present value, including an explicit JSON null.
  NativeField.present(T? value) : this(isPresent: true, value: value);

  /// Whether the wire object contains the key.
  final bool isPresent;

  /// The present value, or null.
  final T? value;

  /// Writes only native value/presence, never SDK persistence tags.
  void writeTo(Map<String, Object?> target, String key) {
    if (isPresent) target[key] = value;
  }

  /// Decodes persisted map data.
  static const fromMap = NativeFieldMapper.fromMap;

  /// Decodes a persisted JSON string.
  static const fromJson = NativeFieldMapper.fromJson;
}
