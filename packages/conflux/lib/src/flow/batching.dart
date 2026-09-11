import 'dart:async';

import 'package:conflux/effect.dart';
import 'package:conflux/option.dart';
import 'package:conflux/src/effect/effect.dart' show EffectAccess;
import 'package:conflux/src/effect/execution.dart' show ScopeAccess;
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
      pumpFlow(upstream, mailbox.offer),
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
          switch (await EffectAccess.evaluate(_mailbox.takeUntil(deadline), execution)) {
            case Failed<({bool elapsed, Option<A> value}), E>(:final cause):
              return Failed(cause);
            case Succeeded<({bool elapsed, Option<A> value}), E>(
              value: (elapsed: true, value: _),
            ):
              return Succeeded(Some(List<A>.unmodifiable(batch)));
            case Succeeded<({bool elapsed, Option<A> value}), E>(
              value: (elapsed: false, value: None()),
            ):
              return Succeeded(Some(List<A>.unmodifiable(batch)));
            case Succeeded<({bool elapsed, Option<A> value}), E>(
              value: (elapsed: false, value: Some<A>(:final value)),
            ):
              batch.add(value);
          }
        }
        return Succeeded(Some(List<A>.unmodifiable(batch)));
    }
  });
}
