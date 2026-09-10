part of '../../effect.dart';

final class _Execution {
  _Execution({
    required this.context,
    required this.scope,
    required this.clock,
    required this.cancellation,
  });

  Context context;
  final Scope scope;
  final Clock clock;
  final _Cancellation cancellation;
  var _steps = 0;

  Future<void>? schedulingBoundary() {
    _steps += 1;
    return _steps % 256 == 0 ? Future<void>.delayed(Duration.zero) : null;
  }
}

final class _Cancellation {
  var _nextListener = 0;
  final _listeners = <int, void Function(Object? reason)>{};
  Object? _reason;
  var _cancelled = false;

  bool get isCancelled => _cancelled;
  Object? get reason => _reason;

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

/// Owns child fibers and finalizers for one execution region.
final class Scope {
  Scope._();

  var _closed = false;
  Future<Cause<Never>?>? _closing;
  final _children = <_OwnedRoot>{};
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

  Fiber<A, E> _fork<A, E>(Effect<A, E> effect, _Execution parent) {
    if (_closed) {
      final cancellation = _Cancellation()..cancel(const ScopeClosed());
      return Fiber._(
        cancellation,
        Future.value(const Failed(Interrupted(ScopeClosed()))),
      );
    }

    final cancellation = _Cancellation();
    final childScope = Scope._();
    final execution = _Execution(
      context: parent.context,
      scope: childScope,
      clock: parent.clock,
      cancellation: cancellation,
    );
    final stopParentCancellation = parent.cancellation.listen(
      cancellation.cancel,
    );
    late final Fiber<A, E> fiber;
    late final _OwnedRoot ownedChild;
    final exit = _runScoped(effect, execution).whenComplete(() {
      stopParentCancellation();
      _children.remove(ownedChild);
    });
    fiber = Fiber._(cancellation, exit);
    ownedChild = _OwnedRoot((reason) async {
      final childExit = await fiber.interrupt(reason);
      return switch (childExit) {
        Succeeded<A, E>() => null,
        Failed<A, E>(:final cause) => _defectsOnly(cause),
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
    final children = List<_OwnedRoot>.of(_children);
    final childFailures = await Future.wait(
      children.map((child) => child.interruptAndJoin(const ScopeClosed())),
    );
    failures.addAll(childFailures.whereType<Cause<Never>>());

    for (final finalizer in _finalizers.reversed) {
      final exit = await _runProtected(
        finalizer.effect,
        finalizer.context,
        finalizer.clock,
      );
      if (exit case Failed<void, Never>(:final cause)) failures.add(cause);
    }
    return _combineCleanupCauses(failures, sequential: true);
  }
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

Future<Exit<A, E>> _runScoped<A, E>(
  Effect<A, E> effect,
  _Execution execution,
) async {
  final exit = await effect._evaluate(execution);
  final cleanup = await execution.scope.close();
  return _appendCleanup(exit, cleanup);
}

Future<Exit<void, Never>> _runProtected(
  Effect<void, Never> finalizer,
  Context context,
  Clock clock,
) async {
  final scope = Scope._();
  final execution = _Execution(
    context: context,
    scope: scope,
    clock: clock,
    cancellation: _Cancellation(),
  );
  return _runScoped(finalizer, execution);
}

Exit<A, E> _appendCleanup<A, E>(
  Exit<A, E> exit,
  Cause<Never>? cleanup,
) {
  if (cleanup == null) return exit;
  return switch (exit) {
    Succeeded<A, E>() => Failed(cleanup),
    Failed<A, E>(:final cause) => Failed(Sequential([cause, cleanup])),
  };
}
