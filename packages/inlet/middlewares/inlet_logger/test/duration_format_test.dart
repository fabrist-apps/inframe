import 'package:inlet_logger/src/duration_format.dart';
import 'package:test/test.dart';

void main() {
  group('DurationFormat', () {
    for (final (micros, text) in [
      (0, '0 µs'),
      (1, '1 µs'),
      (999, '999 µs'),
      (1000, '1.00 ms'),
      (12345, '12.35 ms'),
      (999000, '999.00 ms'),
      (1000000, '1.00 s'),
      (1234567, '1.23 s'),
      (65000000, '65.00 s'),
    ]) {
      test('should format $micros microseconds as $text', () {
        expect(Duration(microseconds: micros).logText, text);
      });
    }
  });
}
