/// An immutable override for a provider option with an inherited default.
sealed class Setting<T> {
  const Setting();

  const factory Setting.inherit() = InheritSetting<T>;
  const factory Setting.set(T value) = SetSetting<T>;
  const factory Setting.clear() = ClearSetting<T>;

  /// Resolve.
  T? resolve(T? inherited);
}

/// Keep the model-level value.
final class InheritSetting<T> extends Setting<T> {
  /// Creates an [InheritSetting].
  const InheritSetting();

  @override
  T? resolve(T? inherited) => inherited;
}

/// Replace the model-level value.
final class SetSetting<T> extends Setting<T> {
  /// Creates a [SetSetting].
  const SetSetting(this.value);

  /// The typed value.
  final T value;

  @override
  T resolve(T? inherited) => value;
}

/// Remove the provider field unless its native schema requires null.
final class ClearSetting<T> extends Setting<T> {
  /// Creates a [ClearSetting].
  const ClearSetting();

  @override
  T? resolve(T? inherited) => null;
}
