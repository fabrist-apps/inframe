import 'package:postgres/postgres.dart' as pg;
import 'package:rivet/rivet.dart';
import 'package:test/test.dart';

import 'generated_consumer.dart';

void main() {
  test('should decode relation counts without lossy numeric conversion', () {
    const codec = RivetCountCodec();

    expect(codec.decode('0', isSqlNull: false), 0);
    expect(codec.decode('9007199254740991', isSqlNull: false), 9007199254740991);
    expect(
      () => codec.decode('9007199254740992', isSqlNull: false),
      throwsRangeError,
    );
    expect(() => codec.decode('-1', isSqlNull: false), throwsRangeError);
    expect(
      () => codec.decode(1.0, isSqlNull: false),
      throwsFormatException,
    );
    expect(() => codec.encode(9007199254740992), throwsRangeError);
  });

  group('Rivet scalar codecs', () {
    late ScalarValues table;

    setUp(() => table = ScalarValues.db.buildSchema().definition);

    test('should enforce signed 32-bit integers', () {
      expect(table.count.codec.encode(-2147483648), -2147483648);
      expect(table.count.codec.encode(2147483647), 2147483647);
      expect(() => table.count.codec.encode(2147483648), throwsRangeError);
      expect(
        () => table.count.codec.decode(-2147483649, isSqlNull: false),
        throwsRangeError,
      );
    });

    test('should normalize timestamps to UTC millisecond precision', () {
      final beforeEpoch = DateTime.fromMicrosecondsSinceEpoch(-1);
      final encoded = table.createdAt.codec.encode(beforeEpoch)! as DateTime;

      expect(encoded.isUtc, isTrue);
      expect(encoded.microsecondsSinceEpoch, -1000);
    });

    test('should distinguish SQL null from JSON null', () {
      expect(
        table.payload.codec.decode(null, isSqlNull: false),
        const JsonNull(),
      );
      expect(
        () => table.payload.codec.decode(null, isSqlNull: true),
        throwsFormatException,
      );
      final jsonNullParameter = table.payload.equals(const JsonNull()).parameters.single;
      expect(jsonNullParameter, isA<pg.TypedValue<Object>>());
      expect((jsonNullParameter! as pg.TypedValue<Object>).isSqlNull, isFalse);
      expect(
        JsonValue.from(const {
          'nested': [true, 1, null],
        }).toDart(),
        {
          'nested': [true, 1, null],
        },
      );
    });

    test('should compare JSON objects structurally without depending on key order', () {
      final first = JsonValue.from(const {
        'name': 'Ada',
        'metadata': {
          'active': true,
          'scores': [1, 2],
        },
      });
      final reordered = JsonValue.from(const {
        'metadata': {
          'scores': [1, 2],
          'active': true,
        },
        'name': 'Ada',
      });

      expect(first, reordered);
      expect(first.hashCode, reordered.hashCode);
      expect(first, isNot(JsonValue.from(const {'name': 'Ada'})));
    });

    test('should bind mapped domains and expose storage operations', () {
      expect(table.code.equals(const UserCode('A')).parameters, ['A']);
      expect(table.code.storage.equals('A').parameters, ['A']);
      expect(table.code.storage.asc(), isA<RivetOrder>());
      expect(table.optionalCode.codec.encode(null), isNull);
      expect(
        table.optionalCode.codec.decode(null, isSqlNull: true),
        isNull,
      );
      expect(
        () => table.code.decodeValue(null, isSqlNull: true),
        throwsA(
          isA<RivetConversionException>()
              .having((error) => error.table, 'table', 'fbr119.scalarValues')
              .having((error) => error.column, 'column', 'code'),
        ),
      );
    });
  });
}
