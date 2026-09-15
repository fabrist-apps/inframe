import 'package:conflux/effect.dart';
import 'package:conflux/option.dart';
import 'package:conflux/src/effect/effect.dart' show EffectAccess;
import 'package:conflux/src/effect/execution.dart' show EffectExecution;
import 'package:conflux/src/schedule/schedule.dart';

/// Repetition and retry driven by reusable [Schedule] policies.
extension EffectScheduling<A, E> on Effect<A, E> {
  /// Retries this Effect after expected failures while [schedule] continues.
  Effect<A, E> retry<O>(Schedule<E, O, E> schedule) {
    return EffectAccess.create((execution) async {
      final driver = schedule.createStep();
      while (true) {
        final attempt = await _runAttempt(this, execution);
        switch (attempt) {
          case Succeeded<A, E>():
            return attempt;
          case Failed<A, E>(:final cause):
            final primary = cause.primaryError;
            if (primary is! Some<E>) return attempt;
            final value = primary.value;
            final stepped = await EffectAccess.evaluate(
              driver(value),
              execution,
            );
            switch (stepped) {
              case Failed<ScheduleDecision<O>, E>(:final cause):
                return Failed(cause);
              case Succeeded<ScheduleDecision<O>, E>(
                value: ScheduleStop<O>(),
              ):
                return attempt;
              case Succeeded<ScheduleDecision<O>, E>(
                value: ScheduleContinue<O>(:final delay),
              ):
                final waitFailure = await _wait<E>(delay, execution);
                if (waitFailure != null) return Failed(waitFailure);
            }
        }
      }
    });
  }

  /// Repeats this Effect after successes and returns the final policy output.
  Effect<O, E> repeat<O>(Schedule<A, O, E> schedule) {
    return EffectAccess.create((execution) async {
      final driver = schedule.createStep();
      while (true) {
        final attempt = await _runAttempt(this, execution);
        switch (attempt) {
          case Failed<A, E>(:final cause):
            return Failed(cause);
          case Succeeded<A, E>(:final value):
            final stepped = await EffectAccess.evaluate(
              driver(value),
              execution,
            );
            switch (stepped) {
              case Failed<ScheduleDecision<O>, E>(:final cause):
                return Failed(cause);
              case Succeeded<ScheduleDecision<O>, E>(
                value: ScheduleStop<O>(:final output),
              ):
                return Succeeded(output);
              case Succeeded<ScheduleDecision<O>, E>(
                value: ScheduleContinue<O>(:final delay),
              ):
                final waitFailure = await _wait<E>(delay, execution);
                if (waitFailure != null) return Failed(waitFailure);
            }
        }
      }
    });
  }
}

Future<Exit<A, E>> _runAttempt<A, E>(
  Effect<A, E> effect,
  EffectExecution execution,
) {
  return EffectAccess.evaluate(Effect.using(effect), execution);
}

Future<Cause<E>?> _wait<E>(
  Duration delay,
  EffectExecution execution,
) async {
  final waited = await EffectAccess.evaluate(Effect.sleep(delay), execution);
  return switch (waited) {
    Succeeded<void, Never>() => null,
    Failed<void, Never>(:final cause) => cause,
  };
}
