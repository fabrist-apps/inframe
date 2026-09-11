import 'dart:async';

import 'package:conflux/effect.dart';
import 'package:conflux/option.dart';
import 'package:conflux/src/effect/effect.dart' show EffectAccess;
import 'package:conflux/src/effect/execution.dart' show ScopeAccess;
import 'package:conflux/src/flow/flow_buffer.dart';
import 'package:conflux/src/flow/protocol.dart';

/// Opens runtime-clock Flow timing operators with bounded staging.
abstract final class FlowSchedulingSource {
  /// Opens a cursor that emits the latest value after a quiet [duration].
  static Effect<FlowSourceCursor<A, E>, E> openDebounce<A, E>(
    OpenFlowCursor<A, E> upstream, {
    required Duration duration,
    required int capacity,
    required FlowOverflowPolicy overflow,
    required E Function(FlowBufferOverflow overflow)? onOverflow,
  }) => _open(
    upstream,
    (input, output) => _debounce(input, output, duration),
    capacity: capacity,
    overflow: overflow,
    onOverflow: onOverflow,
  );

  /// Opens a cursor that emits the leading value in each [duration].
  static Effect<FlowSourceCursor<A, E>, E> openThrottle<A, E>(
    OpenFlowCursor<A, E> upstream, {
    required Duration duration,
    required int capacity,
    required FlowOverflowPolicy overflow,
    required E Function(FlowBufferOverflow overflow)? onOverflow,
  }) => _open(
    upstream,
    (input, output) => _throttle(input, output, duration),
    capacity: capacity,
    overflow: overflow,
    onOverflow: onOverflow,
  );

  static Effect<FlowSourceCursor<A, E>, E> _open<A, E>(
    OpenFlowCursor<A, E> upstream,
    Effect<void, E> Function(
      FlowMailbox<_Stamped<A>, E> input,
      FlowMailbox<A, E> output,
    )
    process, {
    required int capacity,
    required FlowOverflowPolicy overflow,
    required E Function(FlowBufferOverflow overflow)? onOverflow,
  }) => EffectAccess.create((execution) async {
    final input = FlowMailbox<_Stamped<A>, E>(capacity, overflow, onOverflow);
    final output = FlowMailbox<A, E>(capacity, overflow, onOverflow);
    ScopeAccess.addFinalizer(
      execution.scope,
      Effect.sync(() {
        input.close();
        output.close();
      }),
      execution.context,
      execution.clock,
    );

    final source = ScopeAccess.fork(
      execution.scope,
      pumpFlow(
        upstream,
        (value) => EffectAccess.create((execution) {
          return EffectAccess.evaluate(
            input.offer(_Stamped(value, execution.clock.monotonic())),
            execution,
          );
        }),
      ),
      execution,
    );
    unawaited(
      source.exit.then((exit) {
        if (execution.cancellation.isCancelled) return;
        switch (exit) {
          case Succeeded<void, E>():
            input.complete();
          case Failed<void, E>(:final cause):
            input.fail(cause);
        }
      }),
    );

    final processor = ScopeAccess.fork(
      execution.scope,
      process(input, output),
      execution,
    );
    unawaited(
      processor.exit.then((exit) {
        if (execution.cancellation.isCancelled) return;
        switch (exit) {
          case Succeeded<void, E>():
            output.complete();
          case Failed<void, E>(:final cause):
            output.fail(cause);
        }
      }),
    );
    return Succeeded(_ScheduledCursor(output));
  });

  static Effect<void, E> _debounce<A, E>(
    FlowMailbox<_Stamped<A>, E> input,
    FlowMailbox<A, E> output,
    Duration duration,
  ) => Effect.build((resolve) async {
    _Stamped<A>? pending;
    while (true) {
      if (pending == null) {
        switch (await resolve(input.take())) {
          case Some<_Stamped<A>>(:final value):
            pending = value;
          case None():
            return;
        }
        continue;
      }

      final current = pending;
      final taken = await resolve(
        input.takeUntil(current.receivedAt + duration),
      );
      if (taken.elapsed) {
        await resolve(output.offer(current.value));
        pending = null;
        continue;
      }
      switch (taken.value) {
        case Some<_Stamped<A>>(:final value):
          if (value.receivedAt >= current.receivedAt + duration) {
            await resolve(output.offer(current.value));
          }
          pending = value;
        case None():
          await resolve(output.offer(current.value));
          return;
      }
    }
  });

  static Effect<void, E> _throttle<A, E>(
    FlowMailbox<_Stamped<A>, E> input,
    FlowMailbox<A, E> output,
    Duration duration,
  ) => Effect.build((resolve) async {
    Duration? blockedUntil;
    while (true) {
      switch (await resolve(input.take())) {
        case Some<_Stamped<A>>(:final value):
          final deadline = blockedUntil;
          if (deadline != null && value.receivedAt < deadline) continue;
          blockedUntil = value.receivedAt + duration;
          await resolve(output.offer(value.value));
        case None():
          return;
      }
    }
  });
}

final class _ScheduledCursor<A, E> implements FlowSourceCursor<A, E> {
  const _ScheduledCursor(this._output);

  final FlowMailbox<A, E> _output;

  @override
  Effect<Option<A>, E> next() => _output.take();
}

final class _Stamped<A> {
  const _Stamped(this.value, this.receivedAt);

  final A value;
  final Duration receivedAt;
}
