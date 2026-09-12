import 'package:test/test.dart';
import 'package:voxel/voxel.dart';

import 'generated_consumer.dart';

void main() {
  final schema = ScalarValues.db.buildSchema();
  final table = schema.definition;

  test('enforces signed 32-bit integers through Turso BigInt values', () {
    expect(table.count.codec.encode(-2147483648), BigInt.from(-2147483648));
    expect(table.count.codec.encode(2147483647), BigInt.from(2147483647));
    expect(() => table.count.codec.encode(2147483648), throwsRangeError);
    expect(
      () => table.count.codec.decode(BigInt.from(-2147483649), isSqlNull: false),
      throwsRangeError,
    );
    expect(() => table.count.codec.decode(1, isSqlNull: false), throwsFormatException);
  });

  test('normalizes timestamps to UTC milliseconds before and after the epoch', () {
    final beforeEpoch = DateTime.fromMicrosecondsSinceEpoch(-1);
    expect(table.createdAt.codec.encode(beforeEpoch), BigInt.from(-1));
    expect(
      table.createdAt.codec.decode(BigInt.from(-1), isSqlNull: false).microsecondsSinceEpoch,
      -1000,
    );
    final modern = DateTime.parse('2026-09-12T12:34:56.789999+05:30');
    final encoded = table.createdAt.codec.encode(modern)! as BigInt;
    final decoded = table.createdAt.codec.decode(encoded, isSqlNull: false);
    expect(decoded.isUtc, isTrue);
    expect(decoded.microsecond, 0);
    expect(decoded.millisecond, 789);
    expect(encoded, greaterThan(BigInt.from(2147483647)));
  });

  test('checks real and boolean storage encodings', () {
    expect(table.score.codec.encode(2.5), 2.5);
    expect(() => table.score.codec.encode(double.nan), throwsFormatException);
    expect(table.active.codec.encode(true), BigInt.one);
    expect(table.active.codec.decode(BigInt.zero, isSqlNull: false), isFalse);
    expect(() => table.active.codec.decode(BigInt.two, isSqlNull: false), throwsFormatException);
  });

  test('distinguishes SQL null from JSON null and validates nested JSON', () {
    const jsonNull = JsonNull();
    expect(table.payload.codec.encode(jsonNull), 'null');
    expect(table.payload.codec.decode('null', isSqlNull: false), jsonNull);
    expect(() => table.payload.codec.decode(null, isSqlNull: true), throwsFormatException);
    expect(table.optionalPayload.codec.decode(null, isSqlNull: true), isNull);
    final nested = JsonValue.from(const {
      'items': [true, 1, null],
    });
    expect(
      table.payload.codec.decode(table.payload.codec.encode(nested), isSqlNull: false),
      nested,
    );
    expect(() => table.payload.codec.decode('{', isSqlNull: false), throwsFormatException);
    expect(() => JsonValue.from(double.infinity), throwsFormatException);
  });

  test('maps domain values and redacts converter failures', () {
    expect(table.code.codec.encode(const UserCode('ada')), 'ada');
    expect(table.code.codec.decode('ada', isSqlNull: false).value, 'ada');
    expect(table.optionalCode.codec.encode(null), isNull);
    expect(table.optionalCode.codec.decode(null, isSqlNull: true), isNull);
    expect(table.code.storage.equals('ada').parameters, ['ada']);
    expect(table.code.equals(const UserCode('ada')).parameters, ['ada']);
    expect(table.preferences.codec.decode('{"darkMode":true}', isSqlNull: false).darkMode, isTrue);
    expect(
      () => table.code.decodeValue('secret', isSqlNull: false),
      throwsA(
        isA<VoxelConversionException>()
            .having((error) => error.table, 'table', 'codec.scalarValues')
            .having((error) => error.column, 'column', 'code')
            .having((error) => error.toString(), 'message', isNot(contains('secret')))
            .having((error) => error.cause, 'cause', isNull),
      ),
    );
  });
}
