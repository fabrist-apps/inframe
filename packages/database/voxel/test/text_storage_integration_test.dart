import 'package:test/test.dart';
import 'package:turso/turso.dart';
import 'package:voxel/voxel.dart';

import 'generated_consumer.dart';

void main() {
  test('round-trips a generated text row through Turso', () async {
    final schema = Users.db.buildSchema();
    final table = schema.definition;
    final database = await TursoDatabase.open(TursoLocation.memory());
    addTearDown(database.close);
    await database.execute(
      'CREATE TABLE users (id TEXT NOT NULL, displayName TEXT NOT NULL, nickname TEXT)',
    );

    final id = table.id.defaultFn!()! as String;
    await database.execute(
      'INSERT INTO users VALUES (?, ?, ?)',
      parameters: [
        table.id.codec.encode(id),
        table.displayName.codec.encode('Ada'),
        table.nickname.codec.encode(null),
      ],
    );
    final stored = (await database.query(
      'SELECT id, displayName, nickname FROM users',
    )).rows.single;
    final row = schema.decode(
      [stored.value('id'), stored.value('displayName'), stored.value('nickname')],
      [false, false, true],
    );

    expect(row.id, id);
    expect(row.displayName, 'Ada');
    expect(row.nickname, isNull);
    expect(
      () => schema.decode([stored.value('id'), BigInt.one, null], [false, false, true]),
      throwsA(isA<VoxelConversionException>()),
    );
  });
}
