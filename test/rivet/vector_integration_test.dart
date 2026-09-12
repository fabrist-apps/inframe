import 'dart:io';
import 'dart:typed_data';

import 'package:postgres/postgres.dart' as pg;
import 'package:rivet/rivet.dart';
import 'package:test/test.dart';

import 'generated_consumer.dart';

void main() {
  group('Rivet vector integration', () {
    final databaseUrl = Platform.environment['RIVET_TEST_DATABASE_URL'];
    late pg.Connection fixture;
    late RivetDb database;

    test('should reject invalid dimensions and components', () {
      expect(() => RivetVectorCodec(0), throwsRangeError);
      final codec = RivetVectorCodec(3);
      expect(() => codec.encode(Float32List.fromList([1, 2])), throwsFormatException);
      expect(
        () => codec.encode(Float32List.fromList([1, double.infinity, 3])),
        throwsFormatException,
      );
    });

    test(
      'should round-trip fixed Float32List values without normalization',
      () async {
        fixture = await pg.Connection.openFromUrl(databaseUrl!);
        await fixture.execute('CREATE SCHEMA IF NOT EXISTS fbr121');
        await fixture.execute('DROP TABLE IF EXISTS fbr121."vectorValues"');
        await fixture.execute('''
          CREATE TABLE fbr121."vectorValues" (
            embedding vector(3) NOT NULL,
            "optionalEmbedding" vector(3)
          )
        ''');
        await fixture.execute(
          "INSERT INTO fbr121.\"vectorValues\" VALUES ('[1.25,-2.5,3.75]', NULL)",
        );
        database = await RivetTestDatabase().open(
          connection: RivetConnection.url(databaseUrl),
          pool: const RivetPoolOptions(maxConnections: 2),
        );
        addTearDown(() async {
          await database.close();
          await fixture.close();
        });

        final row = await VectorValues.db.find().getSingle(database);
        final filtered = await VectorValues.db
            .find(
              where: (values) => values.embedding.equals(Float32List.fromList([1.25, -2.5, 3.75])),
            )
            .getSingle(database);
        expect(row.embedding, Float32List.fromList([1.25, -2.5, 3.75]));
        expect(row.optionalEmbedding, isNull);
        expect(filtered.embedding, Float32List.fromList([1.25, -2.5, 3.75]));
      },
      skip: databaseUrl == null ? 'RIVET_TEST_DATABASE_URL is not configured.' : false,
    );
  });
}
