part of '../../effect.dart';

final class _BindSignal implements Exception {
  const _BindSignal();
}

/// Callback-local binding and resource operations for [Effect.build].
final class EffectBuilder<E> {
  EffectBuilder._(this._execution);

  final _Execution _execution;
  Cause<E>? _terminalCause;
  var _active = true;

  /// The current execution context.
  Context get context {
    _checkActive();
    return _execution.context;
  }

  /// Runs [effect] and returns its successful value.
  Future<A> call<A>(Effect<A, E> effect) async {
    _checkUsable();
    final exit = await effect._evaluate(_execution);
    _checkUsable();
    return switch (exit) {
      Succeeded<A, E>(:final value) => value,
      Failed<A, E>(:final cause) => _abort(cause),
    };
  }

  /// Immediately extracts a successful [Result] or aborts with its error.
  A sync<A>(Result<A, E> result) {
    _checkUsable();
    return switch (result) {
      Success<A, E>(:final value) => value,
      Failure<A, E>(:final error) => _abort(Expected(error)),
    };
  }

  Never _abort(Cause<E> cause) {
    _terminalCause ??= cause;
    throw const _BindSignal();
  }

  void _checkActive() {
    if (!_active) {
      throw StateError('EffectBuilder cannot be used after its callback ends.');
    }
  }

  void _checkUsable() {
    _checkActive();
    if (_terminalCause != null) throw const _BindSignal();
  }

  void _deactivate() => _active = false;
}
