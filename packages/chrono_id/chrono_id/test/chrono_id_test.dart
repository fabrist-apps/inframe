import 'dart:math';

import 'package:chrono_id/src/chrono_id.dart';
import 'package:test/test.dart';

void main() {
  group('ChronoID', () {
    test('should generate a valid default ID', () {
      final id = ChronoID.generate();

      expect(id, hasLength(24));
      expect(ChronoID.isValid(id), isTrue);
    });

    test('should preserve body size when a prefix or custom size is used', () {
      final prefixed = ChronoID.generate(prefix: 'use');
      final minimum = ChronoID.generate(size: 16);
      final custom = ChronoID.generate(prefix: 'Use2', size: 32);

      expect(prefixed, hasLength(28));
      expect(prefixed, startsWith('use_'));
      expect(minimum, hasLength(16));
      expect(custom, hasLength(37));
      expect(ChronoID.isValid(custom, prefix: 'Use2', size: 32), isTrue);
    });

    test('should reject invalid configuration before checking a candidate', () {
      for (final invalidPrefix in ['', '1user', 'user_id', 'user-id', ' user']) {
        expect(
          () => ChronoID.generate(prefix: invalidPrefix),
          throwsArgumentError,
          reason: 'prefix: $invalidPrefix',
        );
        expect(
          () => ChronoID.isValid('invalid', prefix: invalidPrefix),
          throwsArgumentError,
          reason: 'prefix: $invalidPrefix',
        );
      }

      expect(() => ChronoID.generate(size: 15), throwsArgumentError);
      expect(() => ChronoID.isValid('invalid', size: 15), throwsArgumentError);
    });

    test('should reject candidates without normalization', () {
      const valid = 'use_0000000000000000';

      expect(ChronoID.isValid(valid, prefix: 'use', size: 16), isTrue);
      expect(ChronoID.isValid(valid, prefix: 'Use', size: 16), isFalse);
      expect(ChronoID.isValid(valid, size: 16), isFalse);
      expect(ChronoID.isValid('000000000000000', size: 16), isFalse);
      expect(ChronoID.isValid('00000000000000000', size: 16), isFalse);
      expect(ChronoID.isValid('000000000000000_', size: 16), isFalse);
      expect(ChronoID.isValid('000000000000000 ', size: 16), isFalse);
      expect(ChronoID.isValid(' use_0000000000000000', prefix: 'use', size: 16), isFalse);
      expect(ChronoID.isValid('use__000000000000000', prefix: 'use', size: 16), isFalse);
    });

    test('should accept any structurally valid eight-character timestamp', () {
      expect(ChronoID.isValid('zzzzzzzz00000000', size: 16), isTrue);
    });
  });

  group('ChronoIdGenerator', () {
    test('should encode timestamp fixtures with fixed-width base62', () {
      expect(_generateAt(0), startsWith('00000000'));
      expect(_generateAt(61), startsWith('0000000z'));
      expect(_generateAt(62), startsWith('00000010'));
      expect(_generateAt(3843), startsWith('000000zz'));
      expect(_generateAt(3844), startsWith('00000100'));
      expect(_generateAt(218340105584895), startsWith('zzzzzzzz'));
    });

    test('should reject timestamps outside the eight-character range', () {
      expect(() => _generateAt(-1), throwsRangeError);
      expect(() => _generateAt(218340105584896), throwsRangeError);
    });

    test('should read the clock once and sample every suffix character', () {
      var clockReads = 0;
      final random = _SequenceRandom(List.filled(16, 61));
      final generator = ChronoIdGenerator(
        clock: () {
          clockReads++;
          return 0;
        },
        randomFactory: () => random,
      );

      expect(generator.generate(), '00000000zzzzzzzzzzzzzzzz');
      expect(clockReads, 1);
      expect(random.nextIntCalls, 16);
    });

    test('should initialize one random source lazily and reuse it', () {
      var factoryCalls = 0;
      final random = _SequenceRandom(List.filled(32, 0));
      final generator = ChronoIdGenerator(
        clock: () => 0,
        randomFactory: () {
          factoryCalls++;
          return random;
        },
      );

      expect(factoryCalls, 0);
      generator
        ..generate()
        ..generate();
      expect(factoryCalls, 1);
      expect(random.nextIntCalls, 32);
    });

    test('should propagate a secure random source failure', () {
      final failure = StateError('secure randomness unavailable');
      final generator = ChronoIdGenerator(
        clock: () => 0,
        randomFactory: () => throw failure,
      );

      expect(generator.generate, throwsA(same(failure)));
    });

    test('should validate without reading the clock or creating randomness', () {
      final generator = ChronoIdGenerator(
        clock: () => throw StateError('clock read'),
        randomFactory: () => throw StateError('random created'),
      );

      expect(generator.isValid('0000000000000000', size: 16), isTrue);
    });

    test('should sample fresh randomly ordered suffixes within one millisecond', () {
      final random = _SequenceRandom([...List.filled(16, 0), ...List.filled(16, 1)]);
      final generator = ChronoIdGenerator(clock: () => 0, randomFactory: () => random);

      expect(generator.generate(), '000000000000000000000000');
      expect(generator.generate(), '000000001111111111111111');
    });

    test('should preserve timestamp ordering and expose clock rollback', () {
      final timestamps = [62, 61];
      final generator = ChronoIdGenerator(
        clock: () => timestamps.removeAt(0),
        randomFactory: () => _SequenceRandom(List.filled(32, 0)),
      );

      final laterTimestamp = generator.generate(prefix: 'use');
      final rolledBackTimestamp = generator.generate(prefix: 'use');

      expect(laterTimestamp.compareTo(rolledBackTimestamp), greaterThan(0));
      expect(laterTimestamp, startsWith('use_00000010'));
      expect(rolledBackTimestamp, startsWith('use_0000000z'));
    });
  });
}

String _generateAt(int timestamp) => ChronoIdGenerator(
  clock: () => timestamp,
  randomFactory: () => _SequenceRandom(List.filled(16, 0)),
).generate();

final class _SequenceRandom implements Random {
  _SequenceRandom(this._values);

  final List<int> _values;
  int nextIntCalls = 0;

  @override
  bool nextBool() => throw UnimplementedError();

  @override
  double nextDouble() => throw UnimplementedError();

  @override
  int nextInt(int max) {
    final value = _values[nextIntCalls++];
    if (value < 0 || value >= max) throw RangeError.range(value, 0, max - 1);
    return value;
  }
}
