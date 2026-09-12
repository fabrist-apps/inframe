import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:turso/turso.dart';

import 'generated_consumer.dart';

void main() {
  test('round-trips fixed-dimension float32 vectors through Turso storage', () async {
    final table = VectorValues.db.buildSchema().definition;
    final database = await TursoDatabase.open(TursoLocation.memory());
    addTearDown(database.close);
    expect(database.capabilities.vectorFunctions, isTrue);
    await database.execute('CREATE TABLE vectorValues (embedding F32_BLOB(3))');
    final value = Float32List.fromList([0.1, -2.5, 3.25]);
    await database.execute(
      'INSERT INTO vectorValues VALUES (vector32(?))',
      parameters: [table.embedding.codec.encode(value)],
    );
    final stored = (await database.query(
      'SELECT vector_extract(embedding) AS embedding FROM vectorValues',
    )).rows.single;
    expect(table.embedding.codec.decode(stored.value('embedding'), isSqlNull: false), value);
  });
}
