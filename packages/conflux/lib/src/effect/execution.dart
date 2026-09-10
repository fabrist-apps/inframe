import 'dart:async';

import 'package:conflux/src/effect/cause.dart';
import 'package:conflux/src/effect/clock.dart';
import 'package:conflux/src/effect/effect.dart';
import 'package:conflux/src/effect/exit.dart';
import 'package:context/context.dart';

/// Mutable state for one Effect evaluation tree.
final class EffectExecution {
  /// Creates the mutable state for one execution tree.
  EffectExecution({
    required this.context,
    required this.scope,
    required this.clock,
    required this.cancellation,
  });

  /// Number of evaluations between cooperative scheduling boundaries.
  static const schedulingInterval = 256;

  /// The context currently visible to this execution.
  Context context;

  /// The region that owns this execution's children and finalizers.
  final Scope scope;

  /// The time source visible to this execution.
  final Clock clock;

  /// Cooperative cancellation shared by this execution tree.
  final EffectCancellation cancellation;
  var _steps = 0;

  /// Returns an asynchronous fairness boundary at regular intervals.
  Future<void>? schedulingBoundary() {
    _steps += 1;
    return _steps % schedulingInterval == 0 ? Future<void>.delayed(Duration.zero) : null;
  }

  /// Evaluates [effect], closes this execution's scope, and appends cleanup failures.
  Future<Exit<A, E>> runScoped<A, E>(Effect<A, E> effect) async {
    final exit = await EffectAccess.evaluate(effect, this);
    final cleanup = await scope.close();
    return exit.appendCleanup(cleanup);
  }

  /// Runs a finalizer in a fresh scope protected from ordinary cancellation.
  static Future<Exit<void, Never>> runProtected(
    Effect<void, Never> finalizer,
    Context context,
    Clock clock,
  ) {
    final execution = EffectExecution(
      context: context,
      scope: Scope._(),
      clock: clock,
      cancellation: EffectCancellation(),
    );
    return execution.runScoped(finalizer);
  }
}

/// Cooperative cancellation shared by one execution tree.
final class EffectCancellation {
  var _nextListener = 0;
  final _listeners = <int, void Function(Object? reason)>{};
  Object? _reason;
  var _cancelled = false;

  /// Whether cancellation has been requested.
  bool get isCancelled => _cancelled;

  /// The first cancellation reason supplied to this tree.
  Object? get reason => _reason;

  /// Requests cancellation once and notifies current listeners.
  void cancel(Object? reason) {
    if (_cancelled) return;
    _cancelled = true;
    _reason = reason;
    final listeners = List.of(_listeners.values);
    _listeners.clear();
    for (final listener in listeners) {
      listener(reason);
    }
  }

  /// Registers [listener] and returns a callback that removes it.
  void Function() listen(void Function(Object? reason) listener) {
    if (_cancelled) {
      listener(_reason);
      return () {};
    }
    final id = _nextListener++;
    _listeners[id] = listener;
    return () => _listeners.remove(id);
  }
}

/// A running Effect with cooperative interruption and an eventual [Exit].
final class Fiber<A, E> {
  Fiber._(this._cancellation, this._exit);

  final EffectCancellation _cancellation;
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

/// Creates Fibers without exposing their runtime-only constructor.
abstract final class FiberAccess {
  /// Creates a Fiber around [exit] and its [cancellation] handle.
  static Fiber<A, E> create<A, E>(
    EffectCancellation cancellation,
    Future<Exit<A, E>> exit,
  ) => Fiber._(cancellation, exit);
}

/// Type-erased ownership callback for a running Effect.
final class OwnedEffect {
  /// Creates type-erased ownership around an interrupt callback.
  OwnedEffect(this._interrupt);

  final Future<Cause<Never>?> Function(Object? reason) _interrupt;

  /// Interrupts owned work and returns cleanup defects after it completes.
  Future<Cause<Never>?> interruptAndJoin(Object? reason) => _interrupt(reason);
}

/// Owns child fibers and finalizers for one execution region.
final class Scope {
  Scope._();

  var _closed = false;
  Future<Cause<Never>?>? _closing;
  final _children = <OwnedEffect>{};
  final _finalizers = <_RegisteredFinalizer>[];

  /// Whether this scope has stopped accepting work.
  bool get isClosed => _closed;

  bool _addFinalizer(
    Effect<void, Never> effect,
    Context context,
    Clock clock,
  ) {
    if (_closed) return false;
    _finalizers.add(_RegisteredFinalizer(effect, context, clock));
    return true;
  }

  Fiber<A, E> _fork<A, E>(Effect<A, E> effect, EffectExecution parent) {
    if (_closed) {
      final cancellation = EffectCancellation()..cancel(const ScopeClosed());
      return Fiber._(
        cancellation,
        Future.value(const Failed(Interrupted(ScopeClosed()))),
      );
    }

    final cancellation = EffectCancellation();
    final execution = EffectExecution(
      context: parent.context,
      scope: Scope._(),
      clock: parent.clock,
      cancellation: cancellation,
    );
    final stopParentCancellation = parent.cancellation.listen(
      cancellation.cancel,
    );
    late final Fiber<A, E> fiber;
    late final OwnedEffect ownedChild;
    final exit =
        Future<Exit<A, E>>.microtask(
          () => execution.runScoped(effect),
        ).whenComplete(() {
          stopParentCancellation();
          _children.remove(ownedChild);
        });
    fiber = Fiber._(cancellation, exit);
    ownedChild = OwnedEffect((reason) async {
      final childExit = await fiber.interrupt(reason);
      return switch (childExit) {
        Succeeded<A, E>() => null,
        Failed<A, E>(:final cause) => cause.defectsOnly,
      };
    });
    _children.add(ownedChild);
    return fiber;
  }

  /// Stops child work, then runs registered finalizers in reverse order.
  Future<Cause<Never>?> close() {
    final activeClose = _closing;
    if (activeClose != null) return activeClose;
    final close = _close();
    _closing = close;
    return close;
  }

  Future<Cause<Never>?> _close() async {
    _closed = true;
    final failures = <Cause<Never>>[];
    final children = List<OwnedEffect>.of(_children);
    final childFailures = await Future.wait(
      children.map(
        (child) => child
            .interruptAndJoin(const ScopeClosed())
            .then<Cause<Never>?>(
              (cause) => cause,
              onError: Defect<Never>.new,
            ),
      ),
    );
    failures.addAll(childFailures.whereType<Cause<Never>>());

    for (final finalizer in _finalizers.reversed) {
      final exit = await EffectExecution.runProtected(
        finalizer.effect,
        finalizer.context,
        finalizer.clock,
      );
      if (exit case Failed<void, Never>(:final cause)) failures.add(cause);
    }
    return CauseGroup.sequential(failures);
  }
}

/// Uses Scope internals without widening its public API.
abstract final class ScopeAccess {
  /// Creates an empty open scope.
  static Scope create() => Scope._();

  /// Registers [effect] for protected execution when [scope] closes.
  static bool addFinalizer(
    Scope scope,
    Effect<void, Never> effect,
    Context context,
    Clock clock,
  ) => scope._addFinalizer(effect, context, clock);

  /// Starts [effect] as a child owned by [scope].
  static Fiber<A, E> fork<A, E>(
    Scope scope,
    Effect<A, E> effect,
    EffectExecution parent,
  ) => scope._fork(effect, parent);
}

final class _RegisteredFinalizer {
  const _RegisteredFinalizer(this.effect, this.context, this.clock);

  final Effect<void, Never> effect;
  final Context context;
  final Clock clock;
}

/// Why a closing [Scope] interrupted an active child.
final class ScopeClosed {
  /// Creates the standard child-scope shutdown reason.
  const ScopeClosed();

  @override
  String toString() => 'Scope closed';
}
