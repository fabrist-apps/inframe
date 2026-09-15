import 'package:ack/ack.dart';
import 'package:conflux/flow.dart';
import 'package:conflux/src/validation.dart';
import 'package:test/test.dart';

void main() {
  group('Argument validation', () {
    test('should use Ack debug names for scalar arguments', () {
      expect(
        () => validateArgument(Ack.integer().positive(), 0, debugName: 'concurrency'),
        throwsA(
          isA<ArgumentError>()
              .having((error) => error.name, 'name', 'concurrency')
              .having((error) => error.invalidValue, 'value', 0)
              .having((error) => error.message, 'message', 'Must be positive, but got 0.'),
        ),
      );
    });

    test('should preserve scalar runtime values through codecs', () {
      const duration = Duration(microseconds: -1);
      expect(
        () => validateArgument(Flow.durationSchema(), duration, debugName: 'duration'),
        throwsA(
          isA<ArgumentError>()
              .having((error) => error.name, 'name', 'duration')
              .having((error) => error.invalidValue, 'value', duration),
        ),
      );
    });

    test('should retain Ack nested paths and constraint messages', () {
      final schema = Ack.object({
        'options': Ack.object({'capacity': Ack.integer().positive()}),
      });
      expect(
        () => validateArgument(schema, {
          'options': {'capacity': 0},
        }),
        throwsA(
          isA<ArgumentError>()
              .having((error) => error.name, 'path', '#/options/capacity')
              .having((error) => error.invalidValue, 'value', 0)
              .having((error) => error.message, 'message', 'Must be positive, but got 0.'),
        ),
      );
    });

    test('should preserve custom Ack messages and escaped list paths', () {
      final schema = Ack.object({
        'items/~': Ack.list(
          Ack.string().refine(
            (value) => value.startsWith('app_'),
            message: 'An App identifier must start with app_.',
          ),
        ),
      });
      expect(
        () => validateArgument(schema, {
          'items/~': ['invalid'],
        }),
        throwsA(
          isA<ArgumentError>()
              .having((error) => error.name, 'path', '#/items~1~0/0')
              .having((error) => error.invalidValue, 'value', 'invalid')
              .having(
                (error) => error.message,
                'message',
                'An App identifier must start with app_.',
              ),
        ),
      );
    });

    test('should retain runtime duration values when a codec rejects them', () {
      final schema = Ack.object({'duration': Flow.durationSchema()});
      const duration = Duration(microseconds: -1);
      expect(
        () => validateArgument(schema, {'duration': duration}),
        throwsA(
          isA<ArgumentError>()
              .having((error) => error.name, 'path', '#/duration')
              .having((error) => error.invalidValue, 'value', duration),
        ),
      );
    });
  });
}
