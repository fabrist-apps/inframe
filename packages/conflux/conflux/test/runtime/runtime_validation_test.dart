import 'package:conflux/conflux.dart';
import 'package:test/test.dart';

void main() {
  group('Effect argument validation', () {
    test('should report the argument name, value, and constraint', () {
      expect(
        () => Effect.all<int, Never>([], concurrency: 0),
        throwsA(
          isA<ArgumentError>()
              .having((error) => error.name, 'name', 'concurrency')
              .having((error) => error.invalidValue, 'invalidValue', 0)
              .having((error) => error.message, 'message', 'Must be positive'),
        ),
      );
    });

    test('should retain a rejected duration argument', () {
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
