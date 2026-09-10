import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:turso/turso.dart';

void main() {
  group('locations and options', () {
    test('should reject invalid caller-owned locations', () {
      expect(() => TursoLocation.file(''), throwsArgumentError);
      expect(() => TursoLocation.file(':memory:'), throwsArgumentError);
      expect(() => TursoLocation.file('https://example.com/database'), throwsArgumentError);
      expect(() => TursoLocation.file('libsql://example.com/database'), throwsArgumentError);
      expect(() => TursoLocation.file('database\u0000ignored.db'), throwsArgumentError);
      expect(TursoLocation.file(r'C:\data\app.db'), isA<TursoFileLocation>());
      expect(() => TursoLocation.browser('nested/database'), throwsArgumentError);
      expect(() => TursoLocation.browser(r'nested\database'), throwsArgumentError);
      expect(() => TursoLocation.browser(':memory:'), throwsArgumentError);
    });

    test('should defensively copy encryption keys', () {
      final source = Uint8List(32);
      final encryption = TursoEncryption(cipher: TursoCipher.aegis256, key: source);
      source[0] = 1;
      final exposed = encryption.key..[1] = 2;

      expect(exposed.take(2), [0, 2]);
      expect(encryption.key.take(2), [0, 0]);
      expect(
        () => TursoEncryption(cipher: TursoCipher.aes256gcm, key: Uint8List(31)),
        throwsArgumentError,
      );
      expect(
        () => TursoEncryption(
          cipher: TursoCipher.aes256gcm,
          key: Uint8List.fromList(List<int>.filled(31, 171)),
        ),
        throwsA(
          isA<ArgumentError>().having(
            (error) => error.toString(),
            'diagnostic',
            isNot(contains('171')),
          ),
        ),
      );
    });
  });

  group('TursoRow', () {
    late TursoRow row;

    setUp(() {
      row = TursoRow(
        const [
          TursoColumn(name: 'id', declaredType: 'INTEGER'),
          TursoColumn(name: 'title', declaredType: 'TEXT'),
          TursoColumn(name: 'payload', declaredType: 'BLOB'),
        ],
        [
          BigInt.from(42),
          'Hello',
          Uint8List.fromList([1, 2, 3]),
        ],
      );
    });

    test('should provide checked typed access', () {
      expect(row.getBigInt('id'), BigInt.from(42));
      expect(row.getInt('id'), 42);
      expect(row.getString('title'), 'Hello');
      expect(row.getBlob('payload'), [1, 2, 3]);
      expect(() => row.getDouble('id'), throwsStateError);
      expect(() => row.getString('missing'), throwsArgumentError);
    });

    test('should reject ambiguous column names', () {
      final duplicate = TursoRow(
        const [TursoColumn(name: 'id'), TursoColumn(name: 'id')],
        [BigInt.one, BigInt.two],
      );

      expect(duplicate.valueAt(0), BigInt.one);
      expect(duplicate.valueAt(1), BigInt.two);
      expect(() => duplicate.value('id'), throwsStateError);
    });

    test('should return defensive blob copies', () {
      final first = row.getBlob('payload')..[0] = 99;

      expect(first, [99, 2, 3]);
      expect(row.getBlob('payload'), [1, 2, 3]);
    });

    test('should enforce the portable integer range', () {
      final unsafe = TursoRow(
        const [TursoColumn(name: 'value')],
        [BigInt.from(9007199254740992)],
      );

      expect(() => unsafe.getInt('value'), throwsRangeError);
    });

    test('should expose immutable results and checked access failures', () {
      final nullRow = TursoRow(const [TursoColumn(name: 'value')], const [null]);
      final result = TursoQueryResult(
        columns: const [TursoColumn(name: 'value')],
        rows: [nullRow],
      );

      expect(() => result.columns.add(const TursoColumn(name: 'other')), throwsUnsupportedError);
      expect(result.rows.clear, throwsUnsupportedError);
      expect(() => nullRow.valueAt(1), throwsRangeError);
      expect(() => nullRow.getBigInt('value'), throwsStateError);
    });
  });
}
