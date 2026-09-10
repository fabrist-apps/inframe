part of '../../effect.dart';

/// Why a [Runtime] interrupted its roots during shutdown.
final class RuntimeClosed {
  /// Creates the standard runtime shutdown reason.
  const RuntimeClosed();

  @override
  String toString() => 'Runtime closed';
}

/// Thrown by [EffectRunning.runFuture] when Effect execution fails.
final class EffectException<E> implements Exception {
  /// Creates an exception retaining the complete [cause].
  const EffectException(this.cause);

  /// The complete expected, defect, interruption, and cleanup diagnostics.
  final Cause<E> cause;

  @override
  String toString() => 'EffectException: $cause';
}

final class _OwnedRoot {
  _OwnedRoot(this._interrupt);

  final Future<Cause<Never>?> Function(Object? reason) _interrupt;

  Future<Cause<Never>?> interruptAndJoin(Object? reason) => _interrupt(reason);
}

/// A running Effect with cooperative interruption and an eventual [Exit].
final class Fiber<A, E> {
  Fiber._(this._cancellation, this._exit);

  final _Cancellation _cancellation;
  final Future<Exit<A, E>> _exit;

  /// The eventual execution outcome.
  Future<Exit<A, E>> get exit => _exit;

  /// Waits for this fiber's eventual outcome.
  Future<Exit<A, E>> join() => _exit;

  /// Requests cooperative interruption and waits for cleanup and completion.
  Future<Exit<A, E>> interrupt([Object? reason]) {
    _cancellation.cancel(reason);
    return _exit;
  }
}

/// Owns root [Effect] executions, their [Context], and their [Clock].
final class Runtime {
  /// Creates a runtime using an empty context when [context] is omitted.
  Runtime({Context? context, Clock? clock})
    : context = context ?? Context(),
      clock = clock ?? SystemClock();

  /// The context supplied to each root execution.
  final Context context;

  /// The time source shared by executions in this runtime.
  final Clock clock;

  var _closed = false;
  final _roots = <_OwnedRoot>{};

  /// Starts [effect] as a runtime-owned root execution.
  Fiber<A, E> fork<A, E>(Effect<A, E> effect) {
    if (_closed) throw StateError('Runtime is closed.');
    final scope = Scope._();
    final cancellation = _Cancellation();
    final execution = _Execution(
      context: context,
      scope: scope,
      clock: clock,
      cancellation: cancellation,
    );
    late final Fiber<A, E> fiber;
    late final _OwnedRoot root;
    final exit =
        Future<Exit<A, E>>.microtask(
          () => _runScoped(effect, execution),
        ).whenComplete(
          () => _roots.remove(root),
        );
    fiber = Fiber._(cancellation, exit);
    root = _OwnedRoot((reason) async {
      final exit = await fiber.interrupt(reason);
      return switch (exit) {
        Succeeded<A, E>() => null,
        Failed<A, E>(:final cause) => _defectsOnly(cause),
      };
    });
    _roots.add(root);
    return fiber;
  }

  /// Runs [effect] in a fresh root scope and returns after scope cleanup.
  Future<Exit<A, E>> run<A, E>(Effect<A, E> effect) async {
    return fork(effect).join();
  }

  /// Rejects future roots and waits for runtime-owned cleanup.
  Future<void> close() async {
    if (_closed && _roots.isEmpty) return;
    _closed = true;
    final roots = List<_OwnedRoot>.of(_roots);
    await Future.wait(
      roots.map((root) => root.interruptAndJoin(const RuntimeClosed())),
    );
  }
}
