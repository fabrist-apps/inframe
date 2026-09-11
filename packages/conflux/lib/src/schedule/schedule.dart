import 'package:conflux/effect.dart';

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

  /// Creates fresh iteration state for one consumer.
  ScheduleDriver<I, O, E> driver() => _createDriver();

  /// Permits [times] continuing decisions without adding delay.
  static Schedule<I, int, Never> recurs<I>(int times) {
    if (times < 0) {
      throw ArgumentError.value(times, 'times', 'Must not be negative.');
    }
    return Schedule.fromDriver(() {
      var recurrences = 0;
      return ScheduleDriver((_) {
        final output = recurrences;
        if (recurrences >= times) {
          return Effect.succeed(ScheduleStop(output));
        }
        recurrences += 1;
        return Effect.succeed(
          ScheduleContinue(output, Duration.zero),
        );
      });
    });
  }

  /// Continues forever, spacing starts by [duration] from prior completion.
  static Schedule<I, int, Never> spaced<I>(Duration duration) {
    _requireNonNegativeDuration(duration);
    return Schedule.fromDriver(() {
      var recurrences = 0;
      return ScheduleDriver((_) {
        final output = recurrences++;
        return Effect.succeed(ScheduleContinue(output, duration));
      });
    });
  }
}

/// Expected-error adaptation for reusable schedules.
extension ScheduleErrorMapping<I, O, E> on Schedule<I, O, E> {
  /// Transforms only expected driver errors.
  Schedule<I, O, F> mapError<F>(F Function(E error) transform) {
    return Schedule.fromDriver(() {
      final source = driver();
      return ScheduleDriver(
        (input) => source.step(input).mapError(transform),
      );
    });
  }
}

void _requireNonNegativeDuration(Duration duration) {
  if (duration.isNegative) {
    throw ArgumentError.value(duration, 'duration', 'Must not be negative.');
  }
}
