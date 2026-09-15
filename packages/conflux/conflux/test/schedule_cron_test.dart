import 'dart:async';

import 'package:conflux/conflux.dart';
import 'package:context/context.dart';
import 'package:test/test.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'support/fake_clock.dart';

import 'support/moments.dart';

void main() {
  tz_data.initializeTimeZones();
  final utc = tz.UTC;

  Cron parse(String expression) {
    return (Cron.parse(expression, utc) as Success<Cron, CronError>).value;
  }

  Future<void> flush() async {
    for (var index = 0; index < 4; index += 1) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  group('Schedule.cron', () {
    test('should repeat immediately then wait until tomorrow at 9am', () async {
      final clock = FakeClock(wallTime: utcMoment(2026, 9, 11, 11));
      final executions = <UtcMoment>[];
      final Effect<void, CronError> operation = Effect.sync((_) {
        executions.add(clock.wallTime());
      });
      final fiber = Runtime(clock: clock).fork(
        operation.repeat(Schedule.cron<void>(parse('0 0 9 * * *'))),
      );
      await flush();

      expect(executions, [utcMoment(2026, 9, 11, 11)]);
      expect(clock.activeWaits, 1);
      clock.advance(const Duration(hours: 22));
      await flush();

      expect(executions, [utcMoment(2026, 9, 11, 11), utcMoment(2026, 9, 12, 9)]);
      await fiber.interrupt('test complete');
      expect(clock.activeWaits, 0);
    });

    test('should execute one overdue wait then skip the backlog', () async {
      final clock = FakeClock(wallTime: utcMoment(2026, 9, 11, 8));
      final executions = <UtcMoment>[];
      final Effect<void, CronError> operation = Effect.sync((_) {
        executions.add(clock.wallTime());
      });
      final fiber = Runtime(clock: clock).fork(
        operation.repeat(Schedule.cron<void>(parse('0 0 9 * * *'))),
      );
      await flush();

      clock.advance(const Duration(hours: 25));
      await flush();
      expect(executions, [utcMoment(2026, 9, 11, 8), utcMoment(2026, 9, 12, 9)]);
      expect(clock.activeWaits, 1);

      clock.advance(const Duration(hours: 23));
      await flush();
      expect(executions, hasLength(2));
      clock.advance(const Duration(hours: 1));
      await flush();
      expect(executions, hasLength(3));

      await fiber.interrupt('test complete');
    });

    test('should preserve nullable schedule inputs and current wall delays', () async {
      final clock = FakeClock(wallTime: utcMoment(2026, 9, 11, 8, 30));
      final driver = Schedule.cron<Option<int?>>(parse('0 0 9 * * *')).createStep();

      final first = await driver(const None()).runFuture(clock: clock);
      clock.adjustWall(const Duration(minutes: 15));
      final second = await driver(const Some<int?>(null)).runFuture(clock: clock);

      expect((first as ScheduleContinue<Duration>).delay, const Duration(minutes: 30));
      expect((second as ScheduleContinue<Duration>).delay, const Duration(minutes: 15));
    });

    test('should cancel its runtime wait without another execution', () async {
      final clock = FakeClock(wallTime: utcMoment(2026, 9, 11, 8));
      var executions = 0;
      final Effect<int, CronError> operation = Effect.sync((_) => ++executions);
      final fiber = Runtime(clock: clock).fork(
        operation.repeat(Schedule.cron<int>(parse('0 0 9 * * *'))),
      );
      await flush();

      final exit = await fiber.interrupt('cancel cron');
      clock.advance(const Duration(hours: 1));
      await flush();

      expect((exit as Failed<Duration, CronError>).cause, isA<Interrupted<CronError>>());
      expect(executions, 1);
      expect(clock.activeWaits, 0);
    });

    test('should map search failure into the operation domain', () async {
      final impossible = parse('0 0 0 31 feb *');
      final clock = FakeClock(wallTime: utcMoment(2026));
      var executions = 0;
      final Effect<int, _OperationError> operation = Effect.sync((_) => ++executions);
      final policy = Schedule.cron<int>(
        impossible,
      ).mapError<_OperationError>((error, _) => _CalendarError(error));

      final exit = await operation.repeat(policy).runFutureExit(clock: clock);

      final cause = (exit as Failed<Duration, _OperationError>).cause;
      expect((cause as Expected<_OperationError>).error, isA<_CalendarError>());
      expect(executions, 1);
    });

    test('should await cleanup and retain its defect after a failed Cron step', () async {
      final cleanupStarted = Completer<void>();
      final cleanupGate = Completer<void>();
      final impossible = parse('0 0 0 31 feb *');
      final program = Effect.build<Duration, CronError>(($) async {
        $.addFinalizer(
          Effect.tryFuture<void, Never>(
            (_) async {
              cleanupStarted.complete();
              await cleanupGate.future;
              throw StateError('cleanup failed');
            },
            onError: (error, stackTrace, _) => Error.throwWithStackTrace(error, stackTrace),
          ),
        );
        final operation = Effect.succeed<int, CronError>(1);
        return $(operation.repeat(Schedule.cron<int>(impossible)));
      });
      final fiber = Runtime(
        clock: FakeClock(wallTime: utcMoment(2026)),
      ).fork(program);
      var joined = false;
      final joining = fiber.join().then((exit) {
        joined = true;
        return exit;
      });

      await cleanupStarted.future;
      await flush();
      expect(joined, isFalse);
      cleanupGate.complete();
      final exit = await joining;

      final cause = (exit as Failed<Duration, CronError>).cause;
      expect(cause, isA<Sequential<CronError>>());
      expect(cause.containsFatal, isTrue);
    });

    test('should run operations in inherited Context and child Scopes', () async {
      final key = ContextKey<String>('service');
      final clock = FakeClock(wallTime: utcMoment(2026, 9, 11, 8));
      var cleanups = 0;
      final operation = Effect.build<String, CronError>(($) {
        $.addFinalizer(Effect.sync((_) => cleanups += 1));
        return $.context.require(key);
      });
      final values = <String>[];
      final fiber =
          Runtime(
            clock: clock,
            context: Context().withBinding(key.bind('inherited')),
          ).fork(
            operation
                .tap((value, _) => Effect.sync((_) => values.add(value)))
                .repeat(Schedule.cron<String>(parse('0 0 9 * * *'))),
          );
      await flush();
      clock.advance(const Duration(hours: 1));
      await flush();

      expect(values, ['inherited', 'inherited']);
      expect(cleanups, 2);
      await fiber.interrupt('test complete');
    });
  });
}

sealed class _OperationError {
  const _OperationError();
}

final class _CalendarError extends _OperationError {
  const _CalendarError(this.error);

  final CronError error;
}
