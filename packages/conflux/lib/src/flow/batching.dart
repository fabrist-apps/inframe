import 'dart:async';

import 'package:conflux/effect.dart';
import 'package:conflux/option.dart';
import 'package:conflux/src/effect/effect.dart' show EffectAccess;
import 'package:conflux/src/effect/execution.dart' show ScopeAccess;
import 'package:conflux/src/flow/flow_buffer.dart';
import 'package:conflux/src/flow/protocol.dart';
import 'package:context/context.dart';

/// Opens cursors for count-based and clock-based Flow batching.
abstract final class BatchingFlowSource {
  /// Opens a pull-based count batching cursor.
  static Effect<FlowSourceCursor<List<A>, E>, E> openCount<A, E>(
    OpenFlowCursor<A, E> upstream,
    int count,
  ) => upstream().map((cursor, _) => _CountBatchCursor(cursor, count));

  /// Opens a timed cursor backed by a bounded source read-ahead mailbox.
  static Effect<FlowSourceCursor<List<A>, E>, E> openTime<A, E>(
    OpenFlowCursor<A, E> upstream, {
    required Duration duration,
    required int maxSize,
    required int capacity,
    required FlowOverflowPolicy overflow,
    required E Function(FlowBufferOverflow overflow, Context context)? onOverflow,
  }) => EffectAccess.create((execution) async {
    final mailbox = FlowMailbox<_TimedValue<A>, E>(capacity, overflow, onOverflow);
    if (!mailbox.registerClose(execution)) {
      mailbox.close();
      return const Failed(Interrupted(ScopeClosed()));
    }
    final pump = ScopeAccess.fork(
      execution.scope,
      pumpFlow(
        upstream,
        (value) => mailbox.offer(
          _TimedValue(value, execution.clock.monotonic()),
        ),
      ),
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
}

final class _CountBatchCursor<A, E> implements FlowSourceCursor<List<A>, E> {
  const _CountBatchCursor(this._upstream, this._count);

  final FlowSourceCursor<A, E> _upstream;
  final int _count;

  @override
  Effect<Option<List<A>>, E> next() => Effect.build((resolve) async {
    final batch = <A>[];
    while (batch.length < _count) {
      switch (await resolve(_upstream.next())) {
        case Some(:final value):
          batch.add(value);
        case None():
          return batch.isEmpty ? const None() : Some(List<A>.unmodifiable(batch));
      }
    }
    return Some(List<A>.unmodifiable(batch));
  });
}

final class _TimeBatchCursor<A, E> implements FlowSourceCursor<List<A>, E> {
  _TimeBatchCursor(this._mailbox, this._duration, this._maxSize);

  final FlowMailbox<_TimedValue<A>, E> _mailbox;
  final Duration _duration;
  final int _maxSize;
  _TimedValue<A>? _pending;

  @override
  Effect<Option<List<A>>, E> next() => Effect.build((resolve) async {
    final pending = _pending;
    _pending = null;
    final first = pending == null ? await resolve(_mailbox.take()) : Some(pending);
    if (first case None()) return const None();

    final value = (first as Some<_TimedValue<A>>).value;
    final batch = <A>[value.value];
    final deadline = value.receivedAt + _duration;
    while (batch.length < _maxSize) {
      final next = await resolve(_mailbox.takeUntil(deadline));
      if (next.elapsed || next.value is None) break;

      final value = (next.value as Some<_TimedValue<A>>).value;
      if (value.receivedAt >= deadline) {
        _pending = value;
        break;
      }
      batch.add(value.value);
    }
    return Some(List<A>.unmodifiable(batch));
  });
}

final class _TimedValue<A> {
  const _TimedValue(this.value, this.receivedAt);

  final A value;
  final Duration receivedAt;
}
