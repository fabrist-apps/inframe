import 'dart:async';
import 'dart:collection';

import 'package:conflux/effect.dart';
import 'package:conflux/option.dart';
import 'package:conflux/src/coordination/waiter.dart';
import 'package:conflux/src/effect/cause.dart' show CauseRuntimeOperations;
import 'package:conflux/src/effect/effect.dart' show EffectAccess;
import 'package:conflux/src/effect/execution.dart' show EffectExecution, ScopeAccess;
import 'package:conflux/src/effect/exit.dart' show ExitRuntimeOperations;
import 'package:conflux/src/flow/protocol.dart';

/// The action a Flow operation takes when its owned buffer is full.
enum FlowOverflowPolicy {
  /// Waits for the consumer to make capacity available.
  backpressure,

  /// Discards the arriving value.
  dropNewest,

  /// Discards the oldest buffered value and retains the arriving value.
  dropOldest,

  /// Terminates through the configured expected-error mapper.
  fail,
}

/// Describes a full Flow-owned buffer.
final class FlowBufferOverflow {
  /// Creates an overflow for the configured positive [capacity].
  const FlowBufferOverflow(this.capacity);

  /// The maximum number of values retained by the Flow operation.
  final int capacity;

  @override
  String toString() => 'Flow buffer reached capacity $capacity';
}

/// Validates the shared bounded-buffer configuration used by Flow operators.
void validateFlowBuffer<E>(
  int capacity,
  FlowOverflowPolicy overflow,
  E Function(FlowBufferOverflow overflow)? onOverflow,
) {
  if (capacity <= 0) {
    throw ArgumentError.value(capacity, 'capacity', 'Must be positive.');
  }
  if (overflow == FlowOverflowPolicy.fail && onOverflow == null) {
    throw ArgumentError.value(
      onOverflow,
      'onOverflow',
      'Must be supplied when overflow is FlowOverflowPolicy.fail.',
    );
  }
}

/// A single-consumer bounded mailbox that retains terminal state after values.
///
/// One producer wait may retain one value while backpressured. Closing interrupts
/// every pending producer and consumer registration.
final class FlowMailbox<A, E> implements FlowSourceCursor<A, E> {
  /// Creates an open mailbox with already validated configuration.
  FlowMailbox(this.capacity, this.overflow, this._onOverflow);

  /// Maximum buffered values, excluding active producer calls.
  final int capacity;

  /// Behavior when [capacity] values are already buffered.
  final FlowOverflowPolicy overflow;

  final E Function(FlowBufferOverflow overflow)? _onOverflow;
  final ListQueue<A> _values = ListQueue();
  final ListQueue<_PendingMailboxOffer<A, E>> _offers = ListQueue();
  CoordinationWaiter<Exit<Option<A>, E>>? _taker;
  _MailboxTerminal<E>? _terminal;
  var _closed = false;

  /// Offers [value] according to [overflow].
  Effect<void, E> offer(A value) => EffectAccess.create((execution) async {
    final waiter = CoordinationWaiter<Exit<void, E>>();
    late final _PendingMailboxOffer<A, E> offer;
    offer = _PendingMailboxOffer(value, waiter);
    final waited = await EffectAccess.evaluate(
      waiter.awaitValue(
        onStart: () => _startOffer(offer),
        onCancel: () => _offers.remove(offer),
      ),
      execution,
    );
    return switch (waited) {
      Succeeded<Exit<void, E>, Never>(:final value) => value,
      Failed<Exit<void, E>, Never>(:final cause) => Failed(
        cause.mapExpected<E>(_widenNever),
      ),
    };
  });

  @override
  Effect<Option<A>, E> next() => take();

  /// Takes one value, retained terminal failure, or normal completion.
  Effect<Option<A>, E> take() => EffectAccess.create((execution) async {
    final waiter = CoordinationWaiter<Exit<Option<A>, E>>();
    final waited = await EffectAccess.evaluate(
      waiter.awaitValue(
        onStart: () {
          _taker = waiter;
          _drain();
        },
        onCancel: () {
          if (identical(_taker, waiter)) _taker = null;
        },
      ),
      execution,
    );
    return switch (waited) {
      Succeeded<Exit<Option<A>, E>, Never>(:final value) => value,
      Failed<Exit<Option<A>, E>, Never>(:final cause) => Failed(
        cause.mapExpected<E>(_widenNever),
      ),
    };
  });

  /// Takes a value or terminal outcome before the monotonic [deadline].
  ///
  /// An elapsed result has `elapsed: true` and an absent value. Ordinary
  /// completion has `elapsed: false` and an absent value. A queued outcome wins
  /// over an already reached deadline.
  Effect<({bool elapsed, Option<A> value}), E> takeUntil(Duration deadline) =>
      EffectAccess.create((execution) async {
        switch (_poll()) {
          case Some<Exit<Option<A>, E>>(:final value):
            return switch (value) {
              Succeeded<Option<A>, E>(:final value) => Succeeded((
                elapsed: false,
                value: value,
              )),
              Failed<Option<A>, E>(:final cause) => Failed(cause),
            };
          case None():
            break;
        }
        final remaining = deadline - execution.clock.monotonic();
        if (remaining <= Duration.zero) {
          return const Succeeded((elapsed: true, value: None()));
        }

        final next = ScopeAccess.fork(execution.scope, take(), execution);
        final timer = ScopeAccess.fork(
          execution.scope,
          Effect.sleep(remaining),
          execution,
        );
        final winner = await Future.any<_MailboxTimedRace<A, E>>([
          next.exit.then(_MailboxTakeFinished.new),
          timer.exit.then(_MailboxTimerFinished.new),
        ]);
        return switch (winner) {
          _MailboxTakeFinished<A, E>(:final exit) => switch (exit) {
            Succeeded<Option<A>, E>(:final value) =>
              Succeeded<({bool elapsed, Option<A> value}), E>((
                elapsed: false,
                value: value,
              )).appendCleanup(
                _defectsOnly(await timer.interrupt(const _MailboxRaceLost())),
              ),
            Failed<Option<A>, E>(:final cause) =>
              Failed<({bool elapsed, Option<A> value}), E>(cause).appendCleanup(
                _defectsOnly(await timer.interrupt(const _MailboxRaceLost())),
              ),
          },
          _MailboxTimerFinished<A, E>(exit: Succeeded<void, Never>()) => await _finishElapsed(next),
          _MailboxTimerFinished<A, E>(exit: Failed<void, Never>(:final cause)) =>
            Failed<({bool elapsed, Option<A> value}), E>(
              cause.mapExpected<E>(_widenNever),
            ).appendCleanup(
              _defectsOnly(await next.interrupt(const _MailboxRaceLost())),
            ),
        };
      });

  Future<Exit<({bool elapsed, Option<A> value}), E>> _finishElapsed(
    Fiber<Option<A>, E> next,
  ) async {
    final nextExit = await next.interrupt(const _MailboxRaceLost());
    return switch (nextExit) {
      Succeeded<Option<A>, E>(:final value) => Succeeded((
        elapsed: false,
        value: value,
      )),
      Failed<Option<A>, E>(
        cause: Interrupted<E>(reason: _MailboxRaceLost()),
      ) =>
        const Succeeded((elapsed: true, value: None())),
      Failed<Option<A>, E>(:final cause) => Failed(cause),
    };
  }

  Option<Exit<Option<A>, E>> _poll() {
    if (_values.isNotEmpty) {
      final value = _values.removeFirst();
      _acceptOffers();
      return Some(Succeeded(Some(value)));
    }
    final terminal = _terminal;
    if (terminal == null) return const None();
    return Some(
      switch (terminal) {
        _MailboxCompleted<E>() => const Succeeded(None()),
        _MailboxFailed<E>(:final cause) => Failed(cause),
      },
    );
  }

  void _startOffer(_PendingMailboxOffer<A, E> offer) {
    if (_closed || _terminal != null) {
      offer.waiter.interrupt(const FlowMailboxClosed());
      return;
    }
    final taker = _taker;
    if (taker != null) {
      _taker = null;
      taker.succeed(Succeeded(Some(offer.value)));
      offer.waiter.succeed(const Succeeded(null));
      return;
    }
    if (_values.length < capacity) {
      _values.addLast(offer.value);
      offer.waiter.succeed(const Succeeded(null));
      return;
    }

    switch (overflow) {
      case FlowOverflowPolicy.backpressure:
        _offers.addLast(offer);
      case FlowOverflowPolicy.dropNewest:
        offer.waiter.succeed(const Succeeded(null));
      case FlowOverflowPolicy.dropOldest:
        _values
          ..removeFirst()
          ..addLast(offer.value);
        offer.waiter.succeed(const Succeeded(null));
      case FlowOverflowPolicy.fail:
        try {
          offer.waiter.succeed(
            Failed(Expected(_onOverflow!(FlowBufferOverflow(capacity)))),
          );
        } on Object catch (error, stackTrace) {
          offer.waiter.succeed(Failed(Defect(error, stackTrace)));
        }
    }
  }

  /// Retains normal completion after already accepted values drain.
  void complete() => _terminate(const _MailboxCompleted());

  /// Retains [cause] after already accepted values drain.
  void fail(Cause<E> cause) => _terminate(_MailboxFailed(cause));

  void _terminate(_MailboxTerminal<E> terminal) {
    if (_closed || _terminal != null) return;
    _terminal = terminal;
    while (_offers.isNotEmpty) {
      _offers.removeFirst().waiter.interrupt(const FlowMailboxClosed());
    }
    _drain();
  }

  void _drain() {
    final taker = _taker;
    if (taker == null) return;
    if (_values.isNotEmpty) {
      _taker = null;
      taker.succeed(Succeeded(Some(_values.removeFirst())));
      _acceptOffers();
      return;
    }
    final terminal = _terminal;
    if (terminal != null) {
      _taker = null;
      taker.succeed(
        switch (terminal) {
          _MailboxCompleted<E>() => const Succeeded(None()),
          _MailboxFailed<E>(:final cause) => Failed(cause),
        },
      );
    }
  }

  void _acceptOffers() {
    while (_offers.isNotEmpty && _values.length < capacity && _terminal == null) {
      final offer = _offers.removeFirst();
      _values.addLast(offer.value);
      offer.waiter.succeed(const Succeeded(null));
    }
  }

  /// Interrupts and clears all retained state and waits.
  void close() {
    if (_closed) return;
    _closed = true;
    _values.clear();
    while (_offers.isNotEmpty) {
      _offers.removeFirst().waiter.interrupt(const FlowMailboxClosed());
    }
    _taker?.interrupt(const FlowMailboxClosed());
    _taker = null;
  }

  /// Registers [close] in [execution]'s scope.
  bool registerClose(EffectExecution execution) => ScopeAccess.addFinalizer(
    execution.scope,
    Effect.sync(close),
    execution.context,
    execution.clock,
  );
}

Cause<Never>? _defectsOnly<A, E>(Exit<A, E> exit) => switch (exit) {
  Succeeded<A, E>() => null,
  Failed<A, E>(:final cause) => cause.defectsOnly,
};

sealed class _MailboxTimedRace<A, E> {
  const _MailboxTimedRace();
}

final class _MailboxTakeFinished<A, E> extends _MailboxTimedRace<A, E> {
  const _MailboxTakeFinished(this.exit);

  final Exit<Option<A>, E> exit;
}

final class _MailboxTimerFinished<A, E> extends _MailboxTimedRace<A, E> {
  const _MailboxTimerFinished(this.exit);

  final Exit<void, Never> exit;
}

final class _MailboxRaceLost {
  const _MailboxRaceLost();

  @override
  String toString() => 'Flow mailbox timed take race lost';
}

final class _PendingMailboxOffer<A, E> {
  const _PendingMailboxOffer(this.value, this.waiter);

  final A value;
  final CoordinationWaiter<Exit<void, E>> waiter;
}

sealed class _MailboxTerminal<E> {
  const _MailboxTerminal();
}

final class _MailboxCompleted<E> extends _MailboxTerminal<E> {
  const _MailboxCompleted();
}

final class _MailboxFailed<E> extends _MailboxTerminal<E> {
  const _MailboxFailed(this.cause);

  final Cause<E> cause;
}

E _widenNever<E>(Never error) => error;

/// Why a Flow mailbox stopped accepting and delivering values.
final class FlowMailboxClosed {
  /// Creates the stable mailbox-closed interruption reason.
  const FlowMailboxClosed();

  @override
  String toString() => 'Flow mailbox closed';
}
