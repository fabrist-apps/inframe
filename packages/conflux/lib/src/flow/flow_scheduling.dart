import 'dart:async';

import 'package:conflux/effect.dart';
import 'package:conflux/option.dart';
import 'package:conflux/src/effect/cause.dart' show CauseGroup, CauseRuntimeOperations;
import 'package:conflux/src/effect/effect.dart' show EffectAccess;
import 'package:conflux/src/effect/execution.dart' show ScopeAccess;
import 'package:conflux/src/flow/flow_buffer.dart';
import 'package:conflux/src/flow/protocol.dart';
import 'package:context/context.dart';

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
    E mapOverflow(FlowBufferOverflow event, Context _) => onOverflow!(event);
    final callback = onOverflow == null ? null : mapOverflow;
    final input = FlowMailbox<_Stamped<A>, E>(capacity, overflow, callback);
    final output = FlowMailbox<A, E>(capacity, overflow, callback);
    final registered = ScopeAccess.addFinalizer(
      execution.scope,
      Effect.sync((_) {
        input.close();
        output.close();
      }),
      execution.context,
      execution.clock,
    );
    if (!registered) {
      input.close();
      output.close();
      return const Failed(Interrupted(ScopeClosed()));
    }
    var sourceFinished = false;
    var terminalizing = false;

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
        sourceFinished = true;
        if (execution.cancellation.isCancelled || terminalizing) return;
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
      processor.exit.then((exit) async {
        if (execution.cancellation.isCancelled || terminalizing) return;
        switch (exit) {
          case Succeeded<void, E>():
            output.complete();
          case Failed<void, E>(:final cause):
            terminalizing = true;
            final cleanup = sourceFinished
                ? null
                : switch (await source.interrupt(const _SchedulingFailed())) {
                    Succeeded<void, E>() => null,
                    Failed<void, E>(:final cause) => cause.defectsOnly,
                  };
            output.fail(CauseGroup.sequential([cause, ?cleanup])!);
        }
      }),
    );
    return Succeeded(output);
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

final class _Stamped<A> {
  const _Stamped(this.value, this.receivedAt);

  final A value;
  final Duration receivedAt;
}

final class _SchedulingFailed {
  const _SchedulingFailed();

  @override
  String toString() => 'Flow scheduling failed';
}
