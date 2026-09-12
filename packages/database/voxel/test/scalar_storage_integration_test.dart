import 'package:test/test.dart';
import 'package:turso/turso.dart';
import 'package:voxel/voxel.dart';

import 'generated_consumer.dart';

void main() {
  test('round-trips every scalar and mapped codec through Turso', () async {
    final schema = ScalarValues.db.buildSchema();
    final table = schema.definition;
    final database = await TursoDatabase.open(TursoLocation.memory());
    addTearDown(database.close);
    await database.execute('''
      CREATE TABLE scalarValues (
        count INTEGER, score REAL, active INTEGER, createdAt INTEGER,
        payload TEXT, optionalPayload TEXT, code TEXT, optionalCode TEXT, preferences TEXT
      )
    ''');
    final timestamp = DateTime.parse('1969-12-31T23:59:59.999999Z');
    final nested = JsonValue.from(const {
      'nested': [true, 1, null],
    });
    await database.execute(
      'INSERT INTO scalarValues VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
      parameters: [
        table.count.codec.encode(2147483647),
        table.score.codec.encode(2.5),
        table.active.codec.encode(true),
        table.createdAt.codec.encode(timestamp),
        table.payload.codec.encode(const JsonNull()),
        table.optionalPayload.codec.encode(nested),
        table.code.codec.encode(const UserCode('ada')),
        table.optionalCode.codec.encode(null),
        table.preferences.codec.encode(const Preferences(darkMode: true)),
      ],
    );
    final stored = (await database.query('SELECT * FROM scalarValues')).rows.single;
    final values = [
      for (final column in schema.columns) stored.value(column.physicalName),
    ];
    final row = schema.decode(values, [for (final value in values) value == null]);

    expect(row.count, 2147483647);
    expect(row.score, 2.5);
    expect(row.active, isTrue);
    expect(row.createdAt.microsecondsSinceEpoch, -1000);
    expect(row.payload, const JsonNull());
    expect(row.optionalPayload, nested);
    expect(row.code.value, 'ada');
    expect(row.optionalCode, isNull);
    expect(row.preferences.darkMode, isTrue);
  });
}
