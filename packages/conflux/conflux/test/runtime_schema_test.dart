import 'package:conflux/conflux.dart';
import 'package:test/test.dart';

void main() {
  group('Effect argument validation', () {
    test('should report the Ack field path and numeric constraint', () {
      expect(
        () => Effect.all<int, Never>([], concurrency: 0),
        throwsA(
          isA<ArgumentError>()
              .having((error) => error.name, 'name', 'concurrency')
              .having((error) => error.invalidValue, 'invalidValue', 0)
              .having((error) => error.message, 'message', 'Must be positive, but got 0.'),
        ),
      );
    });

    test('should identify a negative duration through its codec', () {
      expect(
        () => Effect.sleep(const Duration(microseconds: -1)),
        throwsA(
          isA<ArgumentError>()
              .having((error) => error.name, 'name', 'duration')
              .having(
                (error) => error.invalidValue,
                'invalidValue',
                const Duration(microseconds: -1),
              ),
        ),
      );
    });
  });

  group('Runtime duration schemas', () {
    for (final (name, schema) in [
      ('Effect', Effect.durationSchema()),
      ('CacheExpiry', CacheExpiry.durationSchema()),
    ]) {
      group(name, () {
        test('should preserve microsecond precision in both directions', () {
          const duration = Duration(microseconds: 1001);

          expect(schema.parse(1001), duration);
          expect(schema.encode(duration), 1001);
        });

        test('should reject negative microseconds in both directions', () {
          expect(schema.safeParse(-1).isFail, isTrue);
          expect(
            schema.safeEncode(const Duration(microseconds: -1)).isFail,
            isTrue,
          );
          expect(schema.encode(Duration.zero), 0);
        });
      });
    }
  });
  group('Schedule', () {
    test('should reject a computed delay above signed 64-bit microseconds', () async {
      final schedule = Schedule.exponential<void>(
        const Duration(microseconds: 0x7FFFFFFFFFFFFFFF),
      );

      final driver = schedule.createStep();
      await Runtime().run(driver(null));
      final exit = await Runtime().run(driver(null));

      expect(
        exit,
        isA<Failed<ScheduleDecision<Duration>, Never>>().having(
          (failure) => failure.cause,
          'cause',
          isA<Defect<Never>>().having((defect) => defect.error, 'error', isA<RangeError>()),
        ),
      );
    });
  });
}
