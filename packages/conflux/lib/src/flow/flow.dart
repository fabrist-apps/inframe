import 'dart:async';

import 'package:conflux/effect.dart';
import 'package:conflux/option.dart';
import 'package:conflux/src/effect/effect.dart' show EffectAccess;
import 'package:conflux/src/effect/execution.dart'
    show EffectCancellation, EffectExecution, ScopeAccess, ScopeClosed;
import 'package:conflux/src/effect/exit.dart' show ExitRuntimeOperations;

typedef _OpenCursor<A, E> = Effect<_FlowCursor<A, E>, E> Function();

E _widenNever<E>(Never error) => error;

/// A lazy, reusable description of a typed sequence.
///
/// Constructing a Flow starts no work. Each [open], runner, or subscription
/// creates independent cursor state and a child resource scope.
final class Flow<A, E> {
  const Flow._(this._openCursor);

  final _OpenCursor<A, E> _openCursor;

  /// Creates a Flow that completes without emitting a value.
  static Flow<A, E> empty<A, E>() => Flow._(
    () => Effect.succeed(_EmptyCursor<A, E>()),
  );

  /// Creates a Flow that emits [value] once, including when it is `null`.
  static Flow<A, E> succeed<A, E>(A value) => Flow._(
    () => Effect.succeed(_ValueCursor<A, E>(value)),
  );

  /// Creates a Flow that terminates with expected [error].
  static Flow<A, E> fail<A, E>(E error) => Flow._(
    () => Effect.succeed(_FailureCursor<A, E>(error)),
  );

  /// Creates a cold Flow whose iterator is acquired for each consumption.
  static Flow<A, Never> fromIterable<A>(Iterable<A> values) => Flow._(
    () => Effect.defer(
      () => Effect.succeed(_IteratorCursor<A, Never>(values.iterator)),
    ),
  );

  /// Lazily chooses a Flow for each consumption.
  ///
  /// The factory runs inside the consumption boundary. A thrown object becomes
  /// a defect with its original stack trace.
  static Flow<A, E> defer<A, E>(Flow<A, E> Function() factory) => Flow._(
    () => Effect.defer(() => factory()._openCursor()),
  );

  /// Opens one scoped pull cursor.
  ///
  /// Only one [FlowCursor.next] may be outstanding. Completion or failure closes
  /// the cursor scope. The acquiring Effect scope also closes it if the caller
  /// stops pulling early.
  Effect<FlowCursor<A, E>, E> open() => EffectAccess.create((parent) async {
    final cancellation = EffectCancellation();
    final stopParentCancellation = parent.cancellation.listen(cancellation.cancel);
    final child = EffectExecution(
      context: parent.context,
      scope: ScopeAccess.create(),
      clock: parent.clock,
      cancellation: cancellation,
    );

    final opened = await EffectAccess.evaluate(Effect.defer(_openCursor), child);
    switch (opened) {
      case Failed<_FlowCursor<A, E>, E>(:final cause):
        stopParentCancellation();
        return Failed<FlowCursor<A, E>, E>(
          cause,
        ).appendCleanup(await child.scope.close());
      case Succeeded<_FlowCursor<A, E>, E>(:final value):
        final cursor = _ManagedFlowCursor<A, E>(
          value,
          child,
          cancellation,
          stopParentCancellation,
        );
        final registered = ScopeAccess.addFinalizer(
          parent.scope,
          cursor._closeEffect,
          parent.context,
          parent.clock,
        );
        if (registered) return Succeeded(cursor);

        final cleanup = await cursor._close(interrupt: true);
        return Failed<FlowCursor<A, E>, E>(
          const Interrupted(ScopeClosed()),
        ).appendCleanup(cleanup);
    }
  });

  /// Transforms each emitted value while preserving the failure channel.
  Flow<B, E> map<B>(B Function(A value) transform) => Flow._(
    () => _openCursor().map((cursor) => _MapCursor(cursor, transform)),
  );

  /// Emits at most the first [count] values and then closes upstream.
  Flow<A, E> take(int count) {
    if (count < 0) {
      throw ArgumentError.value(count, 'count', 'Must not be negative.');
    }
    if (count == 0) return Flow.empty();
    return Flow._(
      () => _openCursor().map((cursor) => _TakeCursor(cursor, count)),
    );
  }

  /// Collects every value into an immutable list.
  ///
  /// Calling this on an unbounded Flow does not provide a memory bound.
  Effect<List<A>, E> runCollect() => _consume((cursor, $) async {
    final values = <A>[];
    while (true) {
      switch (await $(cursor.next())) {
        case Some<A>(:final value):
          values.add(value);
        case None():
          return List<A>.unmodifiable(values);
      }
    }
  });

  /// Returns the first value, or [None] after normal empty completion.
  ///
  /// The consumer scope closes immediately after the first value.
  Effect<Option<A>, E> runFirst() => _consume((cursor, $) => $(cursor.next()));

  Effect<R, E> _consume<R>(
    FutureOr<R> Function(FlowCursor<A, E> cursor, EffectBuilder<E> $) consume,
  ) => Effect.using(
    Effect.build<R, E>(($) async {
      final cursor = await $(open());
      return consume(cursor, $);
    }),
  );
}

/// A scoped pull cursor for one Flow consumption.
abstract interface class FlowCursor<A, E> {
  /// Pulls the next value or [None] for normal completion.
  Effect<Option<A>, E> next();

  /// Stops consumption and awaits resource cleanup.
  Effect<void, Never> close();
}

// The cursor protocol keeps stateful sources and operators interchangeable.
// ignore: one_member_abstracts
abstract interface class _FlowCursor<A, E> {
  Effect<Option<A>, E> next();
}

final class _ManagedFlowCursor<A, E> implements FlowCursor<A, E> {
  _ManagedFlowCursor(
    this._cursor,
    this._execution,
    this._cancellation,
    this._stopParentCancellation,
  );

  final _FlowCursor<A, E> _cursor;
  final EffectExecution _execution;
  final EffectCancellation _cancellation;
  final void Function() _stopParentCancellation;
  Future<Exit<Option<A>, E>>? _activePull;
  Future<Cause<Never>?>? _closing;
  var _closed = false;

  @override
  Effect<Option<A>, E> next() => EffectAccess.create((caller) async {
    if (_closed) return const Succeeded(None());
    if (_activePull != null) {
      return Failed(
        Defect(StateError('Only one Flow cursor pull may be outstanding.'), StackTrace.current),
      );
    }

    final pull = EffectAccess.evaluate(_cursor.next(), _execution);
    _activePull = pull;
    final stopCallerCancellation = caller.cancellation.listen(_cancellation.cancel);
    late final Exit<Option<A>, E> exit;
    try {
      exit = await pull;
    } finally {
      stopCallerCancellation();
      _activePull = null;
    }

    if (exit case Failed<Option<A>, E>() || Succeeded<Option<A>, E>(value: None())) {
      return exit.appendCleanup(await _close(interrupt: false));
    }
    return exit;
  });

  @override
  Effect<void, Never> close() => _closeEffect;

  Effect<void, Never> get _closeEffect => EffectAccess.create((_) async {
    final cleanup = await _close(interrupt: true);
    return cleanup == null ? const Succeeded(null) : Failed(cleanup);
  });

  Future<Cause<Never>?> _close({required bool interrupt}) {
    final active = _closing;
    if (active != null) return active;
    final closing = _closeNow(interrupt: interrupt);
    _closing = closing;
    return closing;
  }

  Future<Cause<Never>?> _closeNow({required bool interrupt}) async {
    _closed = true;
    _stopParentCancellation();
    if (interrupt && !_cancellation.isCancelled) {
      _cancellation.cancel(const FlowCursorClosed());
    }
    if (interrupt) await _activePull;
    return _execution.scope.close();
  }
}

final class _EmptyCursor<A, E> implements _FlowCursor<A, E> {
  @override
  Effect<Option<A>, E> next() => Effect.succeed(const None());
}

final class _ValueCursor<A, E> implements _FlowCursor<A, E> {
  _ValueCursor(this._value);

  final A _value;
  var _emitted = false;

  @override
  Effect<Option<A>, E> next() => Effect.defer(() {
    if (_emitted) return Effect.succeed(const None());
    _emitted = true;
    return Effect.succeed(Some(_value));
  });
}

final class _FailureCursor<A, E> implements _FlowCursor<A, E> {
  _FailureCursor(this._error);

  final E _error;

  @override
  Effect<Option<A>, E> next() => Effect.fail(_error);
}

final class _IteratorCursor<A, E> implements _FlowCursor<A, E> {
  _IteratorCursor(this._iterator);

  final Iterator<A> _iterator;

  @override
  Effect<Option<A>, E> next() => EffectAccess.create((_) async {
    return _iterator.moveNext() ? Succeeded(Some(_iterator.current)) : const Succeeded(None());
  });
}

final class _MapCursor<A, B, E> implements _FlowCursor<B, E> {
  _MapCursor(this._upstream, this._transform);

  final _FlowCursor<A, E> _upstream;
  final B Function(A value) _transform;

  @override
  Effect<Option<B>, E> next() => _upstream.next().map((option) {
    return switch (option) {
      Some<A>(:final value) => Some(_transform(value)),
      None() => const None(),
    };
  });
}

final class _TakeCursor<A, E> implements _FlowCursor<A, E> {
  _TakeCursor(this._upstream, this._remaining);

  final _FlowCursor<A, E> _upstream;
  int _remaining;

  @override
  Effect<Option<A>, E> next() {
    if (_remaining == 0) return Effect.succeed(const None());
    return _upstream.next().map((option) {
      if (option case Some<A>()) _remaining -= 1;
      return option;
    });
  }
}

/// Safe expected-error widening for Flows that cannot fail as expected.
extension FlowNeverError<A> on Flow<A, Never> {
  /// Widens the uninhabited expected-error channel to [E].
  Flow<A, E> widenError<E>() => Flow._(
    () => _openCursor().map(_WidenErrorCursor<A, E>.new),
  );
}

final class _WidenErrorCursor<A, E> implements _FlowCursor<A, E> {
  _WidenErrorCursor(this._upstream);

  final _FlowCursor<A, Never> _upstream;

  @override
  Effect<Option<A>, E> next() => EffectAccess.create((execution) async {
    return switch (await EffectAccess.evaluate(_upstream.next(), execution)) {
      Succeeded<Option<A>, Never>(:final value) => Succeeded(value),
      Failed<Option<A>, Never>(:final cause) => Failed(
        cause.mapExpected<E>(_widenNever),
      ),
    };
  });
}

/// Uses Flow internals from integration libraries without reversing dependencies.
abstract final class FlowAccess {
  /// Creates a single-value Flow from [effect].
  static Flow<A, E> fromEffect<A, E>(Effect<A, E> effect) => Flow._(
    () => Effect.succeed(_EffectCursor(effect)),
  );
}

final class _EffectCursor<A, E> implements _FlowCursor<A, E> {
  _EffectCursor(this._effect);

  final Effect<A, E> _effect;
  var _emitted = false;

  @override
  Effect<Option<A>, E> next() {
    if (_emitted) return Effect.succeed(const None());
    _emitted = true;
    return _effect.map<Option<A>>(Some.new);
  }
}

/// Why a manually closed Flow cursor interrupted active work.
final class FlowCursorClosed {
  /// Creates the stable manual-close reason.
  const FlowCursorClosed();

  @override
  String toString() => 'Flow cursor closed';
}
