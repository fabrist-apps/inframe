import 'dart:async';

import 'package:conflux/result.dart';
import 'package:conflux/src/effect/cause.dart';
import 'package:conflux/src/effect/effect.dart';
import 'package:conflux/src/effect/execution.dart';
import 'package:conflux/src/effect/exit.dart';
import 'package:context/context.dart';

final class _BindSignal implements Exception {
  const _BindSignal();
}

/// Callback-local binding and resource operations for [Effect.build].
final class EffectBuilder<E> {
  EffectBuilder._(this._execution);

  final EffectExecution _execution;
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
    final exit = await EffectAccess.evaluate(effect, _execution);
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

  /// Registers [finalizer] for protected execution when this scope closes.
  void addFinalizer(Effect<void, Never> finalizer) {
    _checkUsable();
    if (!ScopeAccess.addFinalizer(
      _execution.scope,
      finalizer,
      _execution.context,
      _execution.clock,
    )) {
      throw StateError('Cannot add a finalizer to a closed Scope.');
    }
  }

  /// Acquires a resource and atomically transfers its cleanup to this scope.
  Future<A> acquireRelease<A>(
    Effect<A, E> acquire, {
    required Effect<void, Never> Function(A resource) release,
  }) async {
    _checkUsable();
    final exit = await EffectAccess.evaluate(acquire, _execution);
    return switch (exit) {
      Failed<A, E>(:final cause) => _abort(cause),
      Succeeded<A, E>(:final value) => await _registerRelease<A>(value, release),
    };
  }

  Future<A> _registerRelease<A>(
    A resource,
    Effect<void, Never> Function(A resource) release,
  ) async {
    final finalizer = Effect.defer<void, Never>(() => release(resource));
    if (ScopeAccess.addFinalizer(
      _execution.scope,
      finalizer,
      _execution.context,
      _execution.clock,
    )) {
      return resource;
    }

    final error = StateError('Cannot acquire a resource in a closed Scope.');
    final registrationCause = Defect<E>(error, StackTrace.current);
    final releaseExit = await EffectExecution.runProtected(
      finalizer,
      _execution.context,
      _execution.clock,
    );
    return switch (releaseExit) {
      Succeeded<void, Never>() => throw error,
      Failed<void, Never>(:final cause) => _abort(
        Sequential<E>([registrationCause, cause]),
      ),
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

/// Uses builder internals without widening its callback-facing API.
abstract final class EffectBuilderAccess {
  /// Creates a callback-local builder for [execution].
  static EffectBuilder<E> create<E>(EffectExecution execution) => EffectBuilder._(execution);

  /// Returns the cause that stopped [builder], if one was bound.
  static Cause<E>? terminalCause<E>(EffectBuilder<E> builder) => builder._terminalCause;

  /// Prevents [builder] from escaping its callback.
  static void deactivate<E>(EffectBuilder<E> builder) => builder._deactivate();
}
