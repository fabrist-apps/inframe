import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:postgres/postgres.dart' as pg;
import 'package:rivet/rivet.dart';
import 'package:test/test.dart';

import 'generated_consumer.dart';

void main() {
  group('Rivet exact vector search', () {
    final databaseUrl = Platform.environment['RIVET_TEST_DATABASE_URL'];
    late pg.Connection fixture;
    late RivetDb database;
    late List<String> statements;

    setUp(() async {
      if (databaseUrl == null) return;
      fixture = await pg.Connection.openFromUrl(databaseUrl);
      await fixture.execute('DROP SCHEMA IF EXISTS fbr195 CASCADE');
      await fixture.execute('CREATE SCHEMA fbr195');
      await fixture.execute('CREATE EXTENSION IF NOT EXISTS vector');
      await fixture.execute('''
        CREATE TABLE fbr195."vectorCategories" (
          id integer PRIMARY KEY,
          name text NOT NULL
        )
      ''');
      await fixture.execute('''
        CREATE TABLE fbr195."vectorDocuments" (
          id integer PRIMARY KEY,
          "categoryId" integer NOT NULL,
          title text NOT NULL,
          embedding vector(3)
        )
      ''');
      await fixture.execute('''
        INSERT INTO fbr195."vectorCategories" VALUES (1, 'science'), (2, 'fiction')
      ''');
      await fixture.execute('''
        INSERT INTO fbr195."vectorDocuments" VALUES
          (1, 1, 'axis', '[1,0,0]'),
          (2, 1, 'near axis', '[0.9,0.1,0]'),
          (3, 2, 'other category', '[0,1,0]'),
          (4, 1, 'stored zero', '[0,0,0]'),
          (5, 1, 'missing', NULL),
          (6, 1, 'tie b', '[0,1,0]'),
          (7, 1, 'tie a', '[0,1,0]')
      ''');
      await fixture.execute('''
        CREATE INDEX vector_documents_cosine_idx
        ON fbr195."vectorDocuments" USING hnsw (embedding vector_cosine_ops)
      ''');
      statements = [];
      database = await RivetTestDatabase().open(
        connection: RivetConnection.url(databaseUrl, onStatement: statements.add),
        pool: const RivetPoolOptions(maxConnections: 1),
      );
    });

    tearDown(() async {
      if (databaseUrl == null) return;
      await database.close();
      await fixture.close();
    });

    test(
      'should match the full eligible population with an ANN index installed',
      () async {
        final query = Float32List.fromList([1, 0, 0]);
        final rows = await VectorDocuments.db
            .find(
              where: (document) => document.categoryId.equals(1),
              orderBy: (document) => [
                document.embedding.cosineDistance(query).asc(),
                document.id.asc(),
              ],
              limit: 5,
              include: (include) => [include.category()],
            )
            .withScore((document) => document.embedding.cosineDistance(query))
            .get(database);

        expect(rows.map((result) => result.row.id), [1, 2, 6, 7, 4]);
        expect(rows.take(2).map((result) => result.score), everyElement(isNotNull));
        expect(rows.last.score, isNull);
        expect(
          rows.map(
            (result) => (result.row.category as LoadedRelation<VectorCategoriesRow?>).value?.name,
          ),
          everyElement('science'),
        );
        expect(statements, hasLength(1));
        expect(statements.single, startsWith('WITH "__rivet_roots" AS MATERIALIZED'));

        final plan = await fixture.execute('''
          EXPLAIN (COSTS OFF)
          WITH roots AS MATERIALIZED (
            SELECT * FROM fbr195."vectorDocuments" WHERE "categoryId" = 1
          )
          SELECT * FROM roots
          ORDER BY embedding <=> '[1,0,0]'::vector, id
          LIMIT 5
        ''');
        expect(plan.map((row) => row.first).join('\n'), contains('CTE Scan on roots'));
      },
      skip: databaseUrl == null ? 'RIVET_TEST_DATABASE_URL is not configured.' : false,
    );

    test(
      'should preserve distance edge cases and lower negative inner product',
      () async {
        final query = Float32List.fromList([1, 0, 0]);
        final cosine = await VectorDocuments.db
            .find(
              where: (document) => document.id.equals(4) | document.id.equals(5),
              orderBy: (document) => [document.id.asc()],
            )
            .withScore((document) => document.embedding.cosineDistance(query))
            .get(database);
        final l2 = await VectorDocuments.db
            .find(
              where: (document) => document.id.equals(4),
            )
            .withScore((document) => document.embedding.l2Distance(query))
            .getSingle(database);
        final innerProduct = await VectorDocuments.db
            .find(
              where: (document) => document.id.equals(1) | document.id.equals(3),
              orderBy: (document) => [
                document.embedding.negativeInnerProduct(query).asc(),
              ],
            )
            .withScore((document) => document.embedding.negativeInnerProduct(query))
            .get(database);

        expect(cosine.map((result) => result.score), everyElement(isNull));
        expect(l2.score, 1);
        expect(innerProduct.map((result) => result.row.id), [1, 3]);
        expect(innerProduct.map((result) => result.score), [-1, 0]);
        expect(statements, hasLength(3));
      },
      skip: databaseUrl == null ? 'RIVET_TEST_DATABASE_URL is not configured.' : false,
    );

    test(
      'should match the pinned pgvector capability manifest',
      () async {
        final manifest = jsonDecode(
          await _capabilityManifest().readAsString(),
        ) as Map<String, Object?>;
        final extensions = manifest['extensions']! as Map<String, Object?>;
        final server = await fixture.execute("SELECT current_setting('server_version')");
        final vector = await fixture.execute(
          "SELECT extversion FROM pg_extension WHERE extname = 'vector'",
        );

        expect(server.single.first, startsWith(manifest['postgresql']! as String));
        expect(vector.single.first, extensions['vector']);
      },
      skip: databaseUrl == null ? 'RIVET_TEST_DATABASE_URL is not configured.' : false,
    );

    test(
      'should report a missing pgvector capability explicitly',
      () async {
        const databaseName = 'fbr195_missing_vector';
        await fixture.execute('DROP DATABASE IF EXISTS $databaseName WITH (FORCE)');
        await fixture.execute('CREATE DATABASE $databaseName');
        final missingUrl = Uri.parse(databaseUrl!).replace(path: '/$databaseName').toString();
        final setup = await pg.Connection.openFromUrl(missingUrl);
        await setup.execute('CREATE SCHEMA fbr195');
        await setup.execute('''
          CREATE TABLE fbr195."vectorDocuments" (
            id integer PRIMARY KEY,
            "categoryId" integer NOT NULL,
            title text NOT NULL,
            embedding text
          )
        ''');
        await setup.close();
        final missingDatabase = await RivetTestDatabase().open(
          connection: RivetConnection.url(missingUrl),
          pool: const RivetPoolOptions(maxConnections: 1),
        );
        addTearDown(() async {
          await missingDatabase.close();
          await fixture.execute('DROP DATABASE IF EXISTS $databaseName WITH (FORCE)');
        });

        await expectLater(
          VectorDocuments.db
              .find(
                orderBy: (document) => [
                  document.embedding.l2Distance(Float32List.fromList([1, 0, 0])).asc(),
                ],
              )
              .get(missingDatabase),
          throwsA(
            isA<RivetCapabilityException>().having(
              (error) => error.message,
              'message',
              contains('pgvector'),
            ),
          ),
        );
      },
      skip: databaseUrl == null ? 'RIVET_TEST_DATABASE_URL is not configured.' : false,
    );
  });
}

File _capabilityManifest() {
  final packagePath = File('test/fixtures/vector_capabilities.json');
  if (packagePath.existsSync()) return packagePath;
  return File('packages/database/rivet/test/fixtures/vector_capabilities.json');
}
