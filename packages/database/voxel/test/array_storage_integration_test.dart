import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:turso/turso.dart';
import 'package:voxel/voxel.dart';
import 'package:voxel_fixture_schema/authors.dart';

import 'generated_consumer.dart';

void main() {
  test('round-trips every array codec through Turso TEXT storage', () async {
    final schema = ArrayValues.db.buildSchema();
    final table = schema.definition;
    final database = await TursoDatabase.open(TursoLocation.memory());
    addTearDown(database.close);
    await database.execute(
      'CREATE TABLE arrayValues (${schema.columns.map((column) => '"${column.physicalName}" TEXT').join(', ')})',
    );
    final timestamp = DateTime.fromMicrosecondsSinceEpoch(-1);
    final parameters = <Object?>[
      table.texts.codec.encode([]),
      table.nullableElements.codec.encode([null, 'value']),
      table.nullableArray.codec.encode(['present']),
      table.nullableElementsAndArray.codec.encode(null),
      table.integers.codec.encode([-2147483648, 2147483647]),
      table.reals.codec.encode([1.5]),
      table.booleans.codec.encode([true, false]),
      table.timestamps.codec.encode([timestamp]),
      table.jsonValues.codec.encode([
        const JsonNull(),
        JsonValue.from(const [1, null]),
      ]),
      table.nullableJsonValues.codec.encode([null, const JsonNull()]),
      table.statuses.codec.encode([PostStatus.draft, PostStatus.published]),
      table.vectors.codec.encode([
        Float32List.fromList([0.5, -2, 3.25]),
      ]),
      table.codes.codec.encode([const UserCode('ada')]),
      table.nullableCodes.codec.encode([null, const UserCode('grace')]),
      table.counts.codec.encode([const CountValue(7)]),
      table.preferencesList.codec.encode([const Preferences(darkMode: true)]),
    ];
    await database.execute(
      'INSERT INTO arrayValues VALUES (${List.filled(parameters.length, '?').join(', ')})',
      parameters: parameters,
    );
    final stored = (await database.query('SELECT * FROM arrayValues')).rows.single;
    final values = [for (final column in schema.columns) stored.value(column.physicalName)];
    final row = schema.decode(values, [for (final value in values) value == null]);

    expect(row.texts, isEmpty);
    expect(row.nullableElements, [null, 'value']);
    expect(row.nullableArray, ['present']);
    expect(row.nullableElementsAndArray, isNull);
    expect(row.integers, [-2147483648, 2147483647]);
    expect(row.booleans, [true, false]);
    expect(row.timestamps.single.microsecondsSinceEpoch, -1000);
    expect(row.jsonValues, [
      const JsonNull(),
      JsonValue.from(const [1, null]),
    ]);
    expect(row.nullableJsonValues, [null, const JsonNull()]);
    expect(row.statuses, [PostStatus.draft, PostStatus.published]);
    expect(row.vectors.single, Float32List.fromList([0.5, -2, 3.25]));
    expect(row.codes.single.value, 'ada');
    expect(row.nullableCodes.map((value) => value?.value), [null, 'grace']);
    expect(row.counts.single.value, 7);
    expect(row.preferencesList.single.darkMode, isTrue);

    for (final column in schema.columns) {
      expect(
        () => column.decodeValue('{}', isSqlNull: false),
        throwsA(
          isA<VoxelConversionException>()
              .having((error) => error.table, 'table', 'codec.arrayValues')
              .having((error) => error.column, 'column', column.physicalName),
        ),
      );
    }
  });
}
