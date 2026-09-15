import 'dart:math';

import 'package:ack/ack.dart';
import 'package:conflux/cron.dart';
import 'package:conflux/effect.dart';
import 'package:conflux/moment.dart';
import 'package:conflux/option.dart';
import 'package:conflux/result.dart';
import 'package:conflux/src/effect/effect.dart' show EffectAccess;
import 'package:conflux/src/validation.dart';
import 'package:context/context.dart';

/// The result of stepping a [ScheduleDriver].
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

/// Fresh mutable iteration state for one schedule consumer.
final class ScheduleDriver<I, O, E> {
  /// Creates a driver from its stateful step operation.
  const ScheduleDriver(this._step);
  final Effect<ScheduleDecision<O>, E> Function(I input) _step;

  /// Consumes [input] and decides whether and when another execution may run.
  Effect<ScheduleDecision<O>, E> step(I input) => _step(input);
}

/// A reusable policy that creates fresh iteration state for each consumer.
final class Schedule<I, O, E> {
  /// Creates a policy from a fresh-driver factory.
  const Schedule.fromDriver(this._createDriver);
  final ScheduleDriver<I, O, E> Function() _createDriver;

  /// Validates the base delay and multiplier of an exponential schedule.
  static ObjectSchema exponentialArgumentsSchema() =>
      Ack.object({'base': durationSchema(), 'factor': factorSchema()});

  /// Encodes and decodes a non-negative duration as integer microseconds.
  static CodecSchema<int, Duration> durationSchema() => Ack.integer()
      .min(0)
      .codec<Duration>(
        decode: (microseconds) => Duration(microseconds: microseconds),
        encode: (duration) => duration.inMicroseconds,
      );

  /// Validates a non-negative count.
  static IntegerSchema recurrencesSchema() => Ack.integer().min(0);

  /// Validates an exponential delay multiplier.
  static DoubleSchema factorSchema() => Ack.double().finite().positive();

  /// Validates a random sample used for delay jitter.
  static DoubleSchema _randomSchema() => Ack.double().finite().min(0).lessThan(1);

  /// Validates a computed delay before converting to Duration.
  static NumberSchema _delayMicrosecondsSchema() =>
      Ack.number().finite().max(_maxDurationMicroseconds);

  /// Creates fresh iteration state for one consumer.
  ScheduleDriver<I, O, E> driver() => _createDriver();

  /// Permits [times] continuing decisions without adding delay.
  static Schedule<I, int, Never> recurs<I>(int times) {
    validateArgument(recurrencesSchema(), times, debugName: 'times');
    return Schedule.fromDriver(() {
      var recurrences = 0;
      return ScheduleDriver((_) {
        final output = recurrences;
        if (recurrences >= times) return Effect.succeed(ScheduleStop(output));
        recurrences += 1;
        return Effect.succeed(ScheduleContinue(output, Duration.zero));
      });
    });
  }

  /// Continues forever, spacing starts by [duration] from prior completion.
  static Schedule<I, int, Never> spaced<I>(Duration duration) {
    validateArgument(Schedule.durationSchema(), duration, debugName: 'duration');
    return Schedule.fromDriver(() {
      var recurrences = 0;
      return ScheduleDriver((_) {
        final output = recurrences++;
        return Effect.succeed(ScheduleContinue(output, duration));
      });
    });
  }

  /// Continues forever on the next anchored [interval], skipping missed ticks.
  static Schedule<I, int, Never> fixed<I>(Duration interval) {
    validateArgument(durationSchema(), interval, debugName: 'interval');
    return Schedule.fromDriver(() {
      Duration? anchor;
      var recurrence = 0;
      return ScheduleDriver(
        (_) => EffectAccess.create((execution) async {
          final now = execution.clock.monotonic();
          final startedAt = anchor;
          anchor ??= now;
          final delay = interval == Duration.zero
              ? Duration.zero
              : startedAt == null
              ? interval
              : _nextFixedDelay(startedAt, now, interval);
          return Succeeded(ScheduleContinue(recurrence++, delay));
        }),
      );
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
    validateArgument(exponentialArgumentsSchema(), {'base': base, 'factor': factor});
    return Schedule.fromDriver(() {
      var recurrence = 0;
      return ScheduleDriver(
        (_) => Effect.sync((_) {
          final delay = _scaledDuration(base, pow(factor, recurrence).toDouble());
          recurrence += 1;
          return ScheduleContinue<Duration>(delay, delay);
        }),
      );
    });
  }

  /// Continues forever at occurrences selected by [cron].
  ///
  /// Every step reads the runtime's current wall time and chooses the next
  /// occurrence strictly after it. The output and delay are both the duration
  /// until that occurrence. Search exhaustion is an expected [CronError].
  static Schedule<I, Duration, CronError> cron<I>(Cron cron) {
    return Schedule.fromDriver(
      () => ScheduleDriver(
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
      ),
    );
  }

  /// Continues while both policies continue and selects their later delay.
  static Schedule<I, ({O1 left, O2 right}), E> max<I, O1, O2, E>(
    Schedule<I, O1, E> left,
    Schedule<I, O2, E> right,
  ) {
    return Schedule.fromDriver(() {
      final leftDriver = left.driver();
      final rightDriver = right.driver();
      return ScheduleDriver(
        (input) => EffectAccess.create((execution) async {
          final leftExit = await EffectAccess.evaluate(leftDriver.step(input), execution);
          if (leftExit case Failed<ScheduleDecision<O1>, E>(:final cause)) {
            return Failed(cause);
          }
          final rightExit = await EffectAccess.evaluate(rightDriver.step(input), execution);
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
        }),
      );
    });
  }

  /// Continues while either policy continues and selects its earliest delay.
  ///
  /// A stopped branch has a None output and is not stepped again.
  static Schedule<I, ({Option<O1> left, Option<O2> right}), E> min<I, O1, O2, E>(
    Schedule<I, O1, E> left,
    Schedule<I, O2, E> right,
  ) {
    return Schedule.fromDriver(() {
      final leftDriver = left.driver();
      final rightDriver = right.driver();
      var leftActive = true;
      var rightActive = true;
      return ScheduleDriver(
        (input) => EffectAccess.create((execution) async {
          ScheduleContinue<O1>? leftDecision;
          ScheduleContinue<O2>? rightDecision;
          if (leftActive) {
            final exit = await EffectAccess.evaluate(leftDriver.step(input), execution);
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
            final exit = await EffectAccess.evaluate(rightDriver.step(input), execution);
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
        }),
      );
    });
  }
}

/// Expected-error adaptation for reusable schedules.
extension ScheduleErrorMapping<I, O, E> on Schedule<I, O, E> {
  /// Transforms only expected driver errors.
  Schedule<I, O, F> mapError<F>(F Function(E error, Context context) transform) {
    return Schedule.fromDriver(() {
      final source = driver();
      return ScheduleDriver(
        (input) => source.step(input).mapError(transform),
      );
    });
  }
}

/// Delay, input, sequencing, and observation transforms for a Schedule.
extension ScheduleOperations<I, O, E> on Schedule<I, O, E> {
  /// Replaces each continuing decision's computed delay.
  Schedule<I, O, E> modifyDelay(
    Duration Function(Duration delay, Context context) transform,
  ) {
    return Schedule.fromDriver(() {
      final source = driver();
      return ScheduleDriver(
        (input) => source.step(input).map((decision, context) {
          return switch (decision) {
            ScheduleStop<O>() => decision,
            ScheduleContinue<O>(:final output, :final delay) => () {
              final transformed = transform(delay, context);
              validateArgument(Schedule.durationSchema(), transformed, debugName: 'duration');
              return ScheduleContinue(output, transformed);
            }(),
          };
        }),
      );
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
      if (Schedule._randomSchema().safeParse(value).isFail) {
        throw StateError('Random values must be in [0, 1).');
      }
      return _scaledDuration(delay, 0.8 + (0.4 * value));
    });
  }

  /// Stops before another execution would start outside [duration].
  ///
  /// The budget uses monotonic elapsed time and does not interrupt work that
  /// already started.
  Schedule<I, O, E> within(Duration duration) {
    validateArgument(Schedule.durationSchema(), duration, debugName: 'duration');
    return Schedule.fromDriver(() {
      final source = driver();
      Duration? startedAt;
      return ScheduleDriver(
        (input) => EffectAccess.create((execution) async {
          startedAt ??= execution.clock.monotonic();
          final exit = await EffectAccess.evaluate(source.step(input), execution);
          final now = execution.clock.monotonic();
          return switch (exit) {
            Failed<ScheduleDecision<O>, E>(:final cause) => Failed(cause),
            Succeeded<ScheduleDecision<O>, E>(
              value: final ScheduleStop<O> stop,
            ) =>
              Succeeded(stop),
            Succeeded<ScheduleDecision<O>, E>(
              value: final ScheduleContinue<O> decision,
            ) =>
              now - startedAt! + decision.delay > duration
                  ? Succeeded(ScheduleStop(decision.output))
                  : Succeeded(decision),
          };
        }),
      );
    });
  }

  /// Stops before another execution when [predicate] rejects its input.
  Schedule<I, O, E> whileInput(
    bool Function(I input, Context context) predicate,
  ) {
    return Schedule.fromDriver(() {
      final source = driver();
      return ScheduleDriver(
        (input) => source.step(input).map((decision, context) {
          if (decision is ScheduleContinue<O> && !predicate(input, context)) {
            return ScheduleStop(decision.output);
          }
          return decision;
        }),
      );
    });
  }

  /// Runs [other] with fresh state after this policy stops.
  Schedule<I, O, E> concat(Schedule<I, O, E> other) {
    return Schedule.fromDriver(() {
      final first = driver();
      ScheduleDriver<I, O, E>? second;
      return ScheduleDriver((input) {
        final active = second;
        if (active != null) return active.step(input);
        return first.step(input).flatMap((decision, _) {
          if (decision is ScheduleContinue<O>) return Effect.succeed(decision);
          final next = other.driver();
          second = next;
          return next.step(input);
        });
      });
    });
  }

  /// Observes each continuing decision without changing it.
  Schedule<I, O, E> tap(
    Effect<void, Never> Function(ScheduleContinue<O> decision, Context context) observe,
  ) {
    return Schedule.fromDriver(() {
      final source = driver();
      return ScheduleDriver(
        (input) => source.step(input).flatMap((decision, context) {
          if (decision is! ScheduleContinue<O>) return Effect.succeed(decision);
          return observe(
            decision,
            context,
          ).mapError<E>((value, _) => _absurd(value! as Never)).map((_, _) => decision);
        }),
      );
    });
  }
}

Duration _nextFixedDelay(Duration anchor, Duration now, Duration interval) {
  final elapsed = now - anchor;
  final remainder = elapsed.inMicroseconds % interval.inMicroseconds;
  if (remainder == 0) return interval;
  return Duration(microseconds: interval.inMicroseconds - remainder);
}

const _maxDurationMicroseconds = 0x7FFFFFFFFFFFFFFF;

Duration _scaledDuration(Duration duration, double factor) {
  final microseconds = duration.inMicroseconds * factor;
  if (Schedule._delayMicrosecondsSchema().safeParse(microseconds).isFail) {
    throw RangeError('The computed delay exceeds the supported Duration range.');
  }
  return Duration(microseconds: microseconds.floor());
}

E _absurd<E>(Never value) => value;

Option<O> _continuedOutput<O>(ScheduleContinue<O>? decision) {
  return decision == null ? const None() : Some(decision.output);
}
