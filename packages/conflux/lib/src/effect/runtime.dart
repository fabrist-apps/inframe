import 'dart:async';

import 'package:conflux/src/effect/cause.dart';
import 'package:conflux/src/effect/clock.dart';
import 'package:conflux/src/effect/effect.dart';
import 'package:conflux/src/effect/execution.dart';
import 'package:conflux/src/effect/exit.dart';
import 'package:context/context.dart';

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
  final _roots = <OwnedEffect>{};

  /// Starts [effect] as a runtime-owned root execution.
  Fiber<A, E> fork<A, E>(Effect<A, E> effect) {
    if (_closed) throw StateError('Runtime is closed.');
    final scope = ScopeAccess.create();
    final cancellation = EffectCancellation();
    final execution = EffectExecution(
      context: context,
      scope: scope,
      clock: clock,
      cancellation: cancellation,
    );
    late final Fiber<A, E> fiber;
    late final OwnedEffect root;
    final exit =
        Future<Exit<A, E>>.microtask(
          () => execution.runScoped(effect),
        ).whenComplete(
          () => _roots.remove(root),
        );
    fiber = FiberAccess.create(cancellation, exit);
    root = OwnedEffect((reason) async {
      final exit = await fiber.interrupt(reason);
      return switch (exit) {
        Succeeded<A, E>() => null,
        Failed<A, E>(:final cause) => cause.defectsOnly,
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
    final roots = List<OwnedEffect>.of(_roots);
    await Future.wait(
      roots.map((root) => root.interruptAndJoin(const RuntimeClosed())),
    );
  }
}

/// Convenience execution for callers that do not need a reusable [Runtime].
extension EffectRunning<A, E> on Effect<A, E> {
  /// Runs this Effect in a temporary Runtime and returns its complete [Exit].
  Future<Exit<A, E>> runFutureExit({Context? context, Clock? clock}) async {
    final runtime = Runtime(context: context, clock: clock);
    try {
      return await runtime.run(this);
    } finally {
      await runtime.close();
    }
  }

  /// Runs this Effect and returns its value or throws [EffectException].
  Future<A> runFuture({Context? context, Clock? clock}) async {
    return switch (await runFutureExit(context: context, clock: clock)) {
      Succeeded<A, E>(:final value) => value,
      Failed<A, E>(:final cause) => throw EffectException(cause),
    };
  }
}
