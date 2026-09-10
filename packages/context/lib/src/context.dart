/// An immutable set of typed bindings passed explicitly between operations.
///
/// Use [withBinding] to derive a context and pass its return value onward.
/// Contexts borrow their values: they neither copy nor dispose stored objects.
/// Binding replacement is local to a branch, while mutations to shared values
/// remain visible to every context borrowing them within the same isolate.
final class Context {
  /// Creates an empty context. Values must be supplied explicitly.
  Context() : _values = Map<ContextKey<Object>, Object>.identity();

  Context._(this._values);

  final Map<ContextKey<Object>, Object> _values;

  /// Returns a new context containing [binding] and the existing bindings.
  ///
  /// Replaces only the binding for the exact same key in the returned context.
  /// The original and any siblings remain unchanged. Unrelated values retain
  /// their object identities. Copying the bindings costs time and storage
  /// proportional to the number of existing bindings.
  Context withBinding(ContextBinding<Object> binding) {
    final values = Map<ContextKey<Object>, Object>.identity()..addAll(_values);
    values[binding._key] = binding._value;
    return Context._(values);
  }

  /// Returns the value for this exact [key], or null when absent.
  ///
  /// Debug names do not participate in lookup. Values cannot be null, so a null
  /// result always means that no binding is present.
  T? read<T extends Object>(ContextKey<T> key) {
    final value = _values[key];
    return value is T ? value : null;
  }

  /// Returns the value for [key], or throws [MissingContextValue] when absent.
  ///
  /// Missing setup fails on access, without supplying a default capability.
  T require<T extends Object>(ContextKey<T> key) =>
      read(key) ?? (throw MissingContextValue(key._debugName));
}

/// A typed identity used to bind and retrieve a non-null value.
///
/// Keep a feature's key private beside its named extension on [Context].
/// Each construction creates a distinct key, even with the same debug name.
final class ContextKey<T extends Object> {
  /// Creates a fresh key whose [debugName] is used only in diagnostics.
  ContextKey(String debugName) : _debugName = debugName;

  final String _debugName;

  /// Binds [value] to this key without modifying a context.
  ///
  /// Pass the binding to [Context.withBinding]. Dart checks the value against
  /// this key's actual type argument on entry, including through a covariantly
  /// widened key reference, before a binding can be created.
  ContextBinding<T> bind(T value) => ContextBinding._(this, value);
}

/// An immutable key/value association created only by [ContextKey.bind].
///
/// Its private constructor prevents callers from bypassing the key's value
/// type check. The value itself is borrowed and may be mutable.
final class ContextBinding<T extends Object> {
  ContextBinding._(this._key, this._value);

  final ContextKey<T> _key;
  final T _value;
}

/// Failure to access a required value that has not been supplied to a context.
final class MissingContextValue implements Exception {
  /// Identifies the absent key using its diagnostic [debugName].
  MissingContextValue(this.debugName);

  /// The missing key's diagnostic label, which need not be unique.
  final String debugName;

  @override
  String toString() => 'MissingContextValue: No value bound for "$debugName".';
}
