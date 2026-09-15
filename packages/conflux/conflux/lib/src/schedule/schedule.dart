import 'dart:math';

import 'package:conflux/cron.dart';
import 'package:conflux/effect.dart';
import 'package:conflux/moment.dart';
import 'package:conflux/option.dart';
import 'package:conflux/result.dart';
import 'package:conflux/src/effect/effect.dart' show EffectAccess;
import 'package:conflux/val.dart';
import 'package:context/context.dart';

/// The result of stepping a [ScheduleStep].
sealed class ScheduleDecision<O> {
  const ScheduleDecision(this.output);

  /// The policy output for this decision.
  final O output;
}

/// A decision that ends scheduling with [output].
final class ScheduleStop<O> extends ScheduleDecision<O> {
  /// Creates a stopping decision with its final policy output.
  const ScheduleStop(super.output);
}

/// A decision that permits another execution after [delay].
final class ScheduleContinue<O> extends ScheduleDecision<O> {
  /// Creates a continuing decision with its output and next delay.
  const ScheduleContinue(super.output, this.delay);

  /// How long the driver must wait before the next execution.
  final Duration delay;
}

/// Stateful step function created separately for each schedule consumer.
typedef ScheduleStep<I, O, E> = Effect<ScheduleDecision<O>, E> Function(I input);

/// A reusable policy that creates fresh iteration state for each consumer.
final class Schedule<I, O, E> {
  /// Creates a policy from a factory that creates a fresh stateful step function.
  const Schedule(this._createStep);

  final ScheduleStep<I, O, E> Function() _createStep;

  /// Validates a non-negative duration without converting it.
  static Schema<Duration> durationSchema() => Val.instance<Duration>().refine(
    (value) => !value.isNegative,
    message: 'Must be non-negative',
  );

  /// Validates a non-negative recurrence count.
  static Schema<int> recurrencesSchema() => Val.int().min(0);

  /// Validates a finite positive exponential multiplier.
  static Schema<double> factorSchema() => Val.double().positive();

  /// Creates fresh iteration state for one consumer.
  ScheduleStep<I, O, E> createStep() => _createStep();

  /// Permits [times] continuing decisions without adding delay.
  static Schedule<I, int, Never> recurs<I>(int times) {
    _validateArgument(recurrencesSchema(), times, debugName: 'times');
    return Schedule(() {
      var recurrences = 0;
      return (_) {
        final output = recurrences;
        if (recurrences >= times) return Effect.succeed(ScheduleStop(output));
        recurrences += 1;
        return Effect.succeed(ScheduleContinue(output, Duration.zero));
      };
    });
  }

  /// Continues forever, spacing starts by [duration] from prior completion.
  static Schedule<I, int, Never> spaced<I>(Duration duration) {
    _validateArgument(Schedule.durationSchema(), duration, debugName: 'duration');
    return Schedule(() {
      var recurrences = 0;
      return (_) {
        final output = recurrences++;
        return Effect.succeed(ScheduleContinue(output, duration));
      };
    });
  }

  /// Continues forever on the next anchored [interval], skipping missed ticks.
  static Schedule<I, int, Never> fixed<I>(Duration interval) {
    _validateArgument(durationSchema(), interval, debugName: 'interval');
    return Schedule(() {
      Duration? anchor;
      var recurrence = 0;
      return (_) => EffectAccess.create((execution) async {
        final now = execution.clock.monotonic();
        final startedAt = anchor;
        anchor ??= now;
        final delay = interval == Duration.zero
            ? Duration.zero
            : startedAt == null
            ? interval
            : _nextFixedDelay(startedAt, now, interval);
        return Succeeded(ScheduleContinue(recurrence++, delay));
      });
    });
  }

  /// Continues forever with exponentially increasing delays.
  ///
  /// Computed delays are rounded down to whole microseconds. Exceeding the
  /// signed 64-bit Duration range is a defect rather than an automatic cap.
  static Schedule<I, Duration, Never> exponential<I>(
    Duration base, {
    double factor = 2,
  }) {
    _validateArgument(durationSchema(), base, debugName: 'base');
    _validateArgument(factorSchema(), factor, debugName: 'factor');
    return Schedule(() {
      var recurrence = 0;
      return (_) => Effect.sync((_) {
        final delay = _scaledDuration(base, pow(factor, recurrence).toDouble());
        recurrence += 1;
        return ScheduleContinue<Duration>(delay, delay);
      });
    });
  }

  /// Continues forever at occurrences selected by [cron].
  ///
  /// Every step reads the runtime's current wall time and chooses the next
  /// occurrence strictly after it. The output and delay are both the duration
  /// until that occurrence. Search exhaustion is an expected [CronError].
  static Schedule<I, Duration, CronError> cron<I>(Cron cron) {
    return Schedule(
      () =>
          (_) => EffectAccess.create((execution) async {
            final now = execution.clock.wallTime();
            switch (cron.next(now)) {
              case Success<ZonedMoment, CronError>(:final value):
                return switch (value.difference(now)) {
                  Success<Duration, MomentError>(:final value) => Succeeded(
                    ScheduleContinue(value, value),
                  ),
                  Failure<Duration, MomentError>(:final error) => Failed(
                    Expected(CronError(error.message)),
                  ),
                };
              case Failure<ZonedMoment, CronError>(:final error):
                return Failed(Expected(error));
            }
          }),
    );
  }

  /// Continues while both policies continue and selects their later delay.
  static Schedule<I, ({O1 left, O2 right}), E> max<I, O1, O2, E>(
    Schedule<I, O1, E> left,
    Schedule<I, O2, E> right,
  ) {
    return Schedule(() {
      final leftDriver = left.createStep();
      final rightDriver = right.createStep();
      return (input) => EffectAccess.create((execution) async {
        final leftExit = await EffectAccess.evaluate(leftDriver(input), execution);
        if (leftExit case Failed<ScheduleDecision<O1>, E>(:final cause)) {
          return Failed(cause);
        }
        final rightExit = await EffectAccess.evaluate(rightDriver(input), execution);
        if (rightExit case Failed<ScheduleDecision<O2>, E>(:final cause)) {
          return Failed(cause);
        }
        final leftDecision = (leftExit as Succeeded<ScheduleDecision<O1>, E>).value;
        final rightDecision = (rightExit as Succeeded<ScheduleDecision<O2>, E>).value;
        final output = (left: leftDecision.output, right: rightDecision.output);
        if (leftDecision is ScheduleStop<O1> || rightDecision is ScheduleStop<O2>) {
          return Succeeded(ScheduleStop(output));
        }
        final leftDelay = (leftDecision as ScheduleContinue<O1>).delay;
        final rightDelay = (rightDecision as ScheduleContinue<O2>).delay;
        return Succeeded(
          ScheduleContinue(
            output,
            leftDelay > rightDelay ? leftDelay : rightDelay,
          ),
        );
      });
    });
  }

  /// Continues while either policy continues and selects its earliest delay.
  ///
  /// A stopped branch has a None output and is not stepped again.
  static Schedule<I, ({Option<O1> left, Option<O2> right}), E> min<I, O1, O2, E>(
    Schedule<I, O1, E> left,
    Schedule<I, O2, E> right,
  ) {
    return Schedule(() {
      final leftDriver = left.createStep();
      final rightDriver = right.createStep();
      var leftActive = true;
      var rightActive = true;
      return (input) => EffectAccess.create((execution) async {
        ScheduleContinue<O1>? leftDecision;
        ScheduleContinue<O2>? rightDecision;
        if (leftActive) {
          final exit = await EffectAccess.evaluate(leftDriver(input), execution);
          switch (exit) {
            case Failed<ScheduleDecision<O1>, E>(:final cause):
              return Failed(cause);
            case Succeeded<ScheduleDecision<O1>, E>(value: ScheduleStop<O1>()):
              leftActive = false;
            case Succeeded<ScheduleDecision<O1>, E>(
              value: final ScheduleContinue<O1> decision,
            ):
              leftDecision = decision;
          }
        }
        if (rightActive) {
          final exit = await EffectAccess.evaluate(rightDriver(input), execution);
          switch (exit) {
            case Failed<ScheduleDecision<O2>, E>(:final cause):
              return Failed(cause);
            case Succeeded<ScheduleDecision<O2>, E>(value: ScheduleStop<O2>()):
              rightActive = false;
            case Succeeded<ScheduleDecision<O2>, E>(
              value: final ScheduleContinue<O2> decision,
            ):
              rightDecision = decision;
          }
        }
        final leftOutput = _continuedOutput(leftDecision);
        final rightOutput = _continuedOutput(rightDecision);
        final output = (left: leftOutput, right: rightOutput);
        if (!leftActive && !rightActive) return Succeeded(ScheduleStop(output));
        final delay = switch ((leftDecision, rightDecision)) {
          (ScheduleContinue<O1>(:final delay), null) => delay,
          (null, ScheduleContinue<O2>(:final delay)) => delay,
          (
            ScheduleContinue<O1>(delay: final leftDelay),
            ScheduleContinue<O2>(delay: final rightDelay),
          ) =>
            leftDelay < rightDelay ? leftDelay : rightDelay,
          _ => throw StateError('An active schedule did not continue.'),
        };
        return Succeeded(ScheduleContinue(output, delay));
      });
    });
  }
}

/// Expected-error adaptation for reusable schedules.
extension ScheduleErrorMapping<I, O, E> on Schedule<I, O, E> {
  /// Transforms only expected driver errors.
  Schedule<I, O, F> mapError<F>(F Function(E error, Context context) transform) {
    return Schedule(() {
      final source = createStep();
      return (input) => source(input).mapError(transform);
    });
  }
}

/// Delay transforms for a Schedule.
extension ScheduleOperations<I, O, E> on Schedule<I, O, E> {
  /// Replaces each continuing decision's computed delay.
  Schedule<I, O, E> modifyDelay(
    Duration Function(Duration delay, Context context) transform,
  ) {
    return Schedule(() {
      final source = createStep();
      return (input) => source(input).map((decision, context) {
        if (decision is ScheduleStop<O>) return decision;

        final continued = decision as ScheduleContinue<O>;
        final delay = transform(continued.delay, context);
        _validateArgument(Schedule.durationSchema(), delay, debugName: 'duration');

        return ScheduleContinue(continued.output, delay);
      });
    });
  }

  /// Applies uniform delay jitter in the range [0.8, 1.2).
  ///
  /// [random] must return values in [0, 1). Delays are rounded down to whole
  /// microseconds and retain the source policy's stop and output behavior.
  Schedule<I, O, E> jittered({double Function()? random}) {
    final nextRandom = random ?? Random().nextDouble;
    return modifyDelay((delay, _) {
      final value = nextRandom();
      if (!value.isFinite || value < 0 || value >= 1) {
        throw StateError('Random values must be in [0, 1).');
      }
      return _scaledDuration(delay, 0.8 + (0.4 * value));
    });
  }
}

Duration _nextFixedDelay(Duration anchor, Duration now, Duration interval) {
  final elapsed = now - anchor;
  final remainder = elapsed.inMicroseconds % interval.inMicroseconds;
  if (remainder == 0) return interval;
  return Duration(microseconds: interval.inMicroseconds - remainder);
}

Duration _scaledDuration(Duration duration, double factor) {
  final microseconds = duration.inMicroseconds * factor;
  if (!microseconds.isFinite || microseconds < 0 || microseconds >= 9223372036854775808.0) {
    throw RangeError('The computed delay exceeds the supported Duration range.');
  }
  return Duration(microseconds: microseconds.floor());
}

void _validateArgument<T>(Schema<T> schema, T value, {required String debugName}) {
  if (schema.safeParse(value) case Failure(:final error)) {
    throw ArgumentError.value(value, debugName, error.first.message);
  }
}

Option<O> _continuedOutput<O>(ScheduleContinue<O>? decision) {
  return decision == null ? const None() : Some(decision.output);
}
