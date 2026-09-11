import 'dart:async';

import 'package:conflux/effect.dart';
import 'package:conflux/option.dart';
import 'package:conflux/src/effect/cause.dart' show CauseRuntimeOperations;
import 'package:conflux/src/effect/effect.dart' show EffectAccess;
import 'package:conflux/src/effect/execution.dart' show ScopeAccess;
import 'package:conflux/src/effect/exit.dart' show ExitRuntimeOperations;
import 'package:conflux/src/flow/flow_buffer.dart';
import 'package:conflux/src/flow/protocol.dart';

/// Opens cursors for count-based and clock-based Flow batching.
abstract final class BatchingFlowSource {
  /// Opens a pull-based count batching cursor.
  static Effect<FlowSourceCursor<List<A>, E>, E> openCount<A, E>(
    OpenFlowCursor<A, E> upstream,
    int count,
  ) => upstream().map((cursor) => _CountBatchCursor(cursor, count));

  /// Opens a timed cursor backed by a bounded source read-ahead mailbox.
  static Effect<FlowSourceCursor<List<A>, E>, E> openTime<A, E>(
    OpenFlowCursor<A, E> upstream, {
    required Duration duration,
    required int maxSize,
    required int capacity,
    required FlowOverflowPolicy overflow,
    required E Function(FlowBufferOverflow overflow)? onOverflow,
  }) => EffectAccess.create((execution) async {
    final mailbox = FlowMailbox<A, E>(capacity, overflow, onOverflow)..registerClose(execution);
    final pump = ScopeAccess.fork(
      execution.scope,
      _pump(upstream, mailbox),
      execution,
    );
    unawaited(
      pump.exit.then((exit) {
        if (execution.cancellation.isCancelled) return;
        switch (exit) {
          case Succeeded<void, E>():
            mailbox.complete();
          case Failed<void, E>(:final cause):
            mailbox.fail(cause);
        }
      }),
    );
    return Succeeded(_TimeBatchCursor(mailbox, duration, maxSize));
  });

  static Effect<void, E> _pump<A, E>(
    OpenFlowCursor<A, E> upstream,
    FlowMailbox<A, E> mailbox,
  ) => Effect.build((resolve) async {
    final cursor = await resolve(Effect.defer(upstream));
    while (true) {
      switch (await resolve(cursor.next())) {
        case Some<A>(:final value):
          await resolve(mailbox.offer(value));
        case None():
          return;
      }
    }
  });
}

final class _CountBatchCursor<A, E> implements FlowSourceCursor<List<A>, E> {
  const _CountBatchCursor(this._upstream, this._count);

  final FlowSourceCursor<A, E> _upstream;
  final int _count;

  @override
  Effect<Option<List<A>>, E> next() => EffectAccess.create((execution) async {
    final batch = <A>[];
    while (batch.length < _count) {
      switch (await EffectAccess.evaluate(_upstream.next(), execution)) {
        case Succeeded<Option<A>, E>(value: Some<A>(:final value)):
          batch.add(value);
        case Succeeded<Option<A>, E>(value: None()):
          return Succeeded(
            batch.isEmpty ? const None() : Some(List<A>.unmodifiable(batch)),
          );
        case Failed<Option<A>, E>(:final cause):
          return Failed(cause);
      }
    }
    return Succeeded(Some(List<A>.unmodifiable(batch)));
  });
}

final class _TimeBatchCursor<A, E> implements FlowSourceCursor<List<A>, E> {
  const _TimeBatchCursor(this._mailbox, this._duration, this._maxSize);

  final FlowMailbox<A, E> _mailbox;
  final Duration _duration;
  final int _maxSize;

  @override
  Effect<Option<List<A>>, E> next() => EffectAccess.create((execution) async {
    final first = await EffectAccess.evaluate(_mailbox.take(), execution);
    switch (first) {
      case Failed<Option<A>, E>(:final cause):
        return Failed(cause);
      case Succeeded<Option<A>, E>(value: None()):
        return const Succeeded(None());
      case Succeeded<Option<A>, E>(value: Some<A>(:final value)):
        final batch = <A>[value];
        final deadline = execution.clock.monotonic() + _duration;
        while (batch.length < _maxSize) {
          final remaining = deadline - execution.clock.monotonic();
          if (remaining <= Duration.zero) {
            return Succeeded(Some(List<A>.unmodifiable(batch)));
          }
          switch (await EffectAccess.evaluate(_nextOrElapsed(remaining), execution)) {
            case Failed<_BatchSignal<A>, E>(:final cause):
              return Failed(cause);
            case Succeeded<_BatchSignal<A>, E>(value: _BatchElapsed<A>()):
              return Succeeded(Some(List<A>.unmodifiable(batch)));
            case Succeeded<_BatchSignal<A>, E>(
              value: _BatchNext<A>(value: None()),
            ):
              return Succeeded(Some(List<A>.unmodifiable(batch)));
            case Succeeded<_BatchSignal<A>, E>(
              value: _BatchNext<A>(value: Some<A>(:final value)),
            ):
              batch.add(value);
          }
        }
        return Succeeded(Some(List<A>.unmodifiable(batch)));
    }
  });

  Effect<_BatchSignal<A>, E> _nextOrElapsed(Duration remaining) =>
      EffectAccess.create((execution) async {
        final next = ScopeAccess.fork(
          execution.scope,
          _mailbox.take().map<_BatchSignal<A>>(_BatchNext.new),
          execution,
        );
        final timer = ScopeAccess.fork(
          execution.scope,
          Effect.sleep(remaining).map<_BatchSignal<A>>((_) => const _BatchElapsed()),
          execution,
        );
        final winner = await Future.any<_BatchRace<A, E>>([
          next.exit.then(_BatchNextFinished.new),
          timer.exit.then(_BatchTimerFinished.new),
        ]);

        return switch (winner) {
          _BatchNextFinished<A, E>(:final exit) => exit.appendCleanup(
            _defectsOnly(await timer.interrupt(const _BatchRaceLost())),
          ),
          _BatchTimerFinished<A, E>(exit: Succeeded<_BatchSignal<A>, Never>(:final value)) =>
            Succeeded<_BatchSignal<A>, E>(value).appendCleanup(
              _defectsOnly(await next.interrupt(const _BatchRaceLost())),
            ),
          _BatchTimerFinished<A, E>(exit: Failed<_BatchSignal<A>, Never>(:final cause)) =>
            Failed<_BatchSignal<A>, E>(cause.mapExpected<E>(_widenNever)).appendCleanup(
              _defectsOnly(await next.interrupt(const _BatchRaceLost())),
            ),
        };
      });
}

Cause<Never>? _defectsOnly<A, E>(Exit<A, E> exit) => switch (exit) {
  Succeeded<A, E>() => null,
  Failed<A, E>(:final cause) => cause.defectsOnly,
};

sealed class _BatchSignal<A> {
  const _BatchSignal();
}

final class _BatchNext<A> extends _BatchSignal<A> {
  const _BatchNext(this.value);

  final Option<A> value;
}

final class _BatchElapsed<A> extends _BatchSignal<A> {
  const _BatchElapsed();
}

sealed class _BatchRace<A, E> {
  const _BatchRace();
}

final class _BatchNextFinished<A, E> extends _BatchRace<A, E> {
  const _BatchNextFinished(this.exit);

  final Exit<_BatchSignal<A>, E> exit;
}

final class _BatchTimerFinished<A, E> extends _BatchRace<A, E> {
  const _BatchTimerFinished(this.exit);

  final Exit<_BatchSignal<A>, Never> exit;
}

final class _BatchRaceLost {
  const _BatchRaceLost();

  @override
  String toString() => 'Flow batch race lost';
}

E _widenNever<E>(Never error) => error;
