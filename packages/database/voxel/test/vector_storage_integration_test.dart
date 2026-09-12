import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:turso/turso.dart';
import 'package:voxel/voxel.dart';

import 'generated_consumer.dart';

void main() {
  test('round-trips fixed-dimension float32 vectors through Turso storage', () async {
    final database = await TursoDatabase.open(TursoLocation.memory());
    addTearDown(database.close);
    final schema = VectorValues.db.buildSchema();
    final table = schema.definition;
    expect(database.capabilities.vectorFunctions, isTrue);
    await database.execute(
      'CREATE TABLE vectorValues (embedding F32_BLOB(3), optionalEmbedding F32_BLOB(3))',
    );
    final value = Float32List.fromList([0.1, -2.5, 3.25]);
    await database.execute(
      'INSERT INTO vectorValues VALUES (vector32(?), NULL)',
      parameters: [table.embedding.codec.encode(value)],
    );
    final stored = (await database.query(
      'SELECT ${table.embedding.selectionSql} AS embedding, '
      '${table.optionalEmbedding.selectionSql} AS optionalEmbedding FROM vectorValues',
    )).rows.single;
    final row = schema.decode(
      [stored.value('embedding'), stored.value('optionalEmbedding')],
      [false, true],
    );
    expect(row.embedding, value);
    expect(row.optionalEmbedding, isNull);
    expect(
      () => table.embedding.decodeValue('[1,2]', isSqlNull: false),
      throwsA(isA<VoxelConversionException>()),
    );
    expect(
      () => table.embedding.decodeValue('[1,NaN,3]', isSqlNull: false),
      throwsA(isA<VoxelConversionException>()),
    );
  });
}
