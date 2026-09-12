import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:voxel/voxel.dart';

import 'generated_consumer.dart';

void main() {
  final schema = VectorValues.db.buildSchema();
  final table = schema.definition;

  test('requires positive dimensions and finite float32 components', () {
    expect(() => VoxelVectorCodec(0), throwsRangeError);
    expect(() => table.embedding.codec.encode(Float32List(2)), throwsFormatException);
    expect(
      () => table.embedding.codec.encode(Float32List.fromList([1, double.nan, 3])),
      throwsFormatException,
    );
    expect(
      () => table.embedding.codec.encode(Float32List.fromList([1, double.infinity, 3])),
      throwsFormatException,
    );
    expect(
      () => table.embedding.codec.decode('[1,2]', isSqlNull: false),
      throwsFormatException,
    );
    expect(
      () => table.embedding.codec.decode('[1,NaN,3]', isSqlNull: false),
      throwsFormatException,
    );
  });

  test('preserves supplied float32 values and generated metadata', () {
    final value = Float32List.fromList([0.1, -2.5, 3.25]);
    final encoded = table.embedding.codec.encode(value);
    final decoded = table.embedding.codec.decode(encoded, isSqlNull: false);
    expect(decoded, value);
    expect(table.embedding.codec.cast, 'f32_blob');
    expect(table.embedding.selectionSql, 'vector_extract("embedding")');
    expect(table.optionalEmbedding.codec.decode(null, isSqlNull: true), isNull);
  });
}
