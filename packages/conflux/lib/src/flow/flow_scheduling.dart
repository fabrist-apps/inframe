import 'dart:async';

import 'package:conflux/effect.dart';
import 'package:conflux/option.dart';
import 'package:conflux/src/effect/cause.dart' show CauseRuntimeOperations;
import 'package:conflux/src/effect/effect.dart' show EffectAccess;
import 'package:conflux/src/effect/execution.dart' show ScopeAccess;
import 'package:conflux/src/effect/exit.dart' show ExitRuntimeOperations;
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
      _pump(upstream, input),
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

  static Effect<void, E> _pump<A, E>(
    OpenFlowCursor<A, E> upstream,
    FlowMailbox<_Stamped<A>, E> input,
  ) => Effect.build((resolve) async {
    final cursor = await resolve(Effect.defer(upstream));
    while (true) {
      switch (await resolve(cursor.next())) {
        case Some<A>(:final value):
          await resolve(
            EffectAccess.create((execution) {
              return EffectAccess.evaluate(
                input.offer(_Stamped(value, execution.clock.monotonic())),
                execution,
              );
            }),
          );
        case None():
          return;
      }
    }
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
      final signal = await resolve(_nextOrElapsed(input, current.receivedAt + duration));
      switch (signal) {
        case _TimingNext<_Stamped<A>>(value: Some<_Stamped<A>>(:final value)):
          if (value.receivedAt >= current.receivedAt + duration) {
            await resolve(output.offer(current.value));
          }
          pending = value;
        case _TimingNext<_Stamped<A>>(value: None()):
          await resolve(output.offer(current.value));
          return;
        case _TimingElapsed<_Stamped<A>>():
          await resolve(output.offer(current.value));
          pending = null;
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

  static Effect<_TimingSignal<A>, E> _nextOrElapsed<A, E>(
    FlowMailbox<A, E> input,
    Duration deadline,
  ) => EffectAccess.create((execution) async {
    switch (input.poll()) {
      case Some<Exit<Option<A>, E>>(:final value):
        return switch (value) {
          Succeeded<Option<A>, E>(:final value) => Succeeded(_TimingNext(value)),
          Failed<Option<A>, E>(:final cause) => Failed(cause),
        };
      case None():
        break;
    }
    final remaining = deadline - execution.clock.monotonic();
    if (remaining <= Duration.zero) {
      return const Succeeded(_TimingElapsed());
    }
    final next = ScopeAccess.fork(
      execution.scope,
      input.take().map<_TimingSignal<A>>(_TimingNext.new),
      execution,
    );
    final timer = ScopeAccess.fork(
      execution.scope,
      Effect.sleep(remaining).map<_TimingSignal<A>>((_) => const _TimingElapsed()),
      execution,
    );
    final winner = await Future.any<_TimingRace<A, E>>([
      next.exit.then(_TimingNextFinished.new),
      timer.exit.then(_TimingTimerFinished.new),
    ]);

    return switch (winner) {
      _TimingNextFinished<A, E>(:final exit) => exit.appendCleanup(
        _defectsOnly(await timer.interrupt(const _TimingRaceLost())),
      ),
      _TimingTimerFinished<A, E>(
        exit: Succeeded<_TimingSignal<A>, Never>(:final value),
      ) =>
        Succeeded<_TimingSignal<A>, E>(value).appendCleanup(
          _defectsOnly(await next.interrupt(const _TimingRaceLost())),
        ),
      _TimingTimerFinished<A, E>(
        exit: Failed<_TimingSignal<A>, Never>(:final cause),
      ) =>
        Failed<_TimingSignal<A>, E>(
          cause.mapExpected<E>(_widenNever),
        ).appendCleanup(
          _defectsOnly(await next.interrupt(const _TimingRaceLost())),
        ),
    };
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

Cause<Never>? _defectsOnly<A, E>(Exit<A, E> exit) => switch (exit) {
  Succeeded<A, E>() => null,
  Failed<A, E>(:final cause) => cause.defectsOnly,
};

sealed class _TimingSignal<A> {
  const _TimingSignal();
}

final class _TimingNext<A> extends _TimingSignal<A> {
  const _TimingNext(this.value);

  final Option<A> value;
}

final class _TimingElapsed<A> extends _TimingSignal<A> {
  const _TimingElapsed();
}

sealed class _TimingRace<A, E> {
  const _TimingRace();
}

final class _TimingNextFinished<A, E> extends _TimingRace<A, E> {
  const _TimingNextFinished(this.exit);

  final Exit<_TimingSignal<A>, E> exit;
}

final class _TimingTimerFinished<A, E> extends _TimingRace<A, E> {
  const _TimingTimerFinished(this.exit);

  final Exit<_TimingSignal<A>, Never> exit;
}

final class _TimingRaceLost {
  const _TimingRaceLost();

  @override
  String toString() => 'Flow timing race lost';
}

E _widenNever<E>(Never error) => error;
