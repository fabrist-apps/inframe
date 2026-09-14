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
      await fixture.execute('CREATE EXTENSION IF NOT EXISTS vectorscale');
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
      await fixture.execute('''
        CREATE INDEX vector_documents_l2_idx
        ON fbr195."vectorDocuments" USING hnsw (embedding vector_l2_ops)
      ''');
      await fixture.execute('''
        CREATE INDEX vector_documents_ip_idx
        ON fbr195."vectorDocuments" USING hnsw (embedding vector_ip_ops)
      ''');
      await fixture.execute('''
        CREATE INDEX vector_documents_cosine_ivf_idx
        ON fbr195."vectorDocuments" USING ivfflat (embedding vector_cosine_ops)
        WITH (lists = 1)
      ''');
      await fixture.execute('''
        CREATE INDEX vector_documents_l2_ivf_idx
        ON fbr195."vectorDocuments" USING ivfflat (embedding vector_l2_ops)
        WITH (lists = 1)
      ''');
      await fixture.execute('''
        CREATE INDEX vector_documents_ip_ivf_idx
        ON fbr195."vectorDocuments" USING ivfflat (embedding vector_ip_ops)
        WITH (lists = 1)
      ''');
      await fixture.execute('''
        CREATE INDEX vector_documents_cosine_diskann_idx
        ON fbr195."vectorDocuments" USING diskann (embedding vector_cosine_ops)
      ''');
      await fixture.execute('''
        CREATE INDEX vector_documents_l2_diskann_idx
        ON fbr195."vectorDocuments" USING diskann (embedding vector_l2_ops)
      ''');
      await fixture.execute('''
        CREATE INDEX vector_documents_ip_diskann_idx
        ON fbr195."vectorDocuments" USING diskann (embedding vector_ip_ops)
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
      'should keep full-population ordering for every exact distance with indexes',
      () async {
        final query = Float32List.fromList([1, 0, 0]);

        Future<List<int>> orderedIds(
          RivetVectorDistanceExpression<double?> Function(VectorDocuments document) distance,
        ) async =>
            (await VectorDocuments.db
                    .find(
                      orderBy: (document) => [distance(document).asc(), document.id.asc()],
                    )
                    .get(database))
                .map((row) => row.id)
                .toList();

        expect(
          await orderedIds((document) => document.embedding.cosineDistance(query)),
          [1, 2, 3, 6, 7, 4, 5],
        );
        expect(
          await orderedIds((document) => document.embedding.l2Distance(query)),
          [1, 2, 4, 3, 6, 7, 5],
        );
        expect(
          await orderedIds((document) => document.embedding.negativeInnerProduct(query)),
          [1, 2, 3, 4, 6, 7, 5],
        );
        expect(statements, hasLength(3));
        expect(
          statements,
          everyElement(startsWith('WITH "__rivet_roots" AS MATERIALIZED')),
        );
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
      'should retrieve and finally order candidates through every ANN method and distance',
      () async {
        final indexes = await fixture.execute('''
          SELECT quote_ident(schemaname) || '.' || quote_ident(indexname)
          FROM pg_indexes
          WHERE schemaname = 'fbr195'
            AND tablename = 'vectorDocuments'
            AND indexname NOT LIKE '%_pkey'
        ''');
        for (final row in indexes) {
          await fixture.execute('DROP INDEX ${row.first! as String}');
        }
        const combinations = [
          ('hnsw', 'vector_cosine_ops', '<=>'),
          ('hnsw', 'vector_l2_ops', '<->'),
          ('hnsw', 'vector_ip_ops', '<#>'),
          ('ivfflat', 'vector_cosine_ops', '<=>'),
          ('ivfflat', 'vector_l2_ops', '<->'),
          ('ivfflat', 'vector_ip_ops', '<#>'),
          ('diskann', 'vector_cosine_ops', '<=>'),
          ('diskann', 'vector_l2_ops', '<->'),
          ('diskann', 'vector_ip_ops', '<#>'),
        ];
        final query = Float32List.fromList([1, 0, 0]);
        await fixture.execute('SET enable_seqscan = off');
        addTearDown(() => fixture.execute('RESET enable_seqscan'));

        for (final (method, operatorClass, operator) in combinations) {
          final indexName = 'active_${method}_$operatorClass';
          final options = method == 'ivfflat' ? ' WITH (lists = 1)' : '';
          await fixture.execute('''
            CREATE INDEX $indexName ON fbr195."vectorDocuments"
            USING $method (embedding $operatorClass)$options
          ''');
          await fixture.execute('ANALYZE fbr195."vectorDocuments"');
          final plan = await fixture.execute('''
            EXPLAIN (COSTS OFF)
            WITH candidates AS MATERIALIZED (
              SELECT * FROM fbr195."vectorDocuments"
              WHERE "categoryId" = 1
              ORDER BY embedding $operator '[1,0,0]'::vector
              LIMIT 5
            )
            SELECT * FROM candidates
            ORDER BY embedding $operator '[1,0,0]'::vector, id DESC
          ''');
          expect(
            plan.map((row) => row.first).join('\n'),
            contains(indexName),
            reason: '$method $operatorClass should be planner-eligible',
          );

          RivetVectorDistanceExpression<double?> distance(
            VectorDocuments document,
          ) => switch (operator) {
            '<=>' => document.embedding.cosineDistance(query),
            '<->' => document.embedding.l2Distance(query),
            '<#>' => document.embedding.negativeInnerProduct(query),
            _ => throw StateError('Unexpected vector operator $operator.'),
          };
          statements.clear();
          final rows = await VectorDocuments.db
              .find(
                where: (document) => document.category.matches(
                  (category) => category.name.equals('science'),
                ),
                orderBy: (document) => [
                  distance(document).asc(),
                  document.id.desc(),
                ],
                limit: 5,
                include: (include) => [include.category()],
                vectorSearch: VectorSearchMode.approximate,
              )
              .withScore(distance)
              .get(database);

          expect(statements, hasLength(1));
          expect(statements.single, startsWith('WITH "__rivet_candidates" AS MATERIALIZED'));
          expect(rows, isNotEmpty);
          expect(
            rows.map(
              (row) => (row.row.category as LoadedRelation<VectorCategoriesRow?>).value?.name,
            ),
            everyElement('science'),
          );
          for (var index = 1; index < rows.length; index++) {
            final previous = rows[index - 1];
            final current = rows[index];
            final previousScore = previous.score;
            final currentScore = current.score;
            if (previousScore == null) {
              expect(currentScore, isNull);
            } else if (currentScore != null) {
              expect(previousScore, lessThanOrEqualTo(currentScore));
              if (previousScore == currentScore) {
                expect(previous.row.id, greaterThan(current.row.id));
              }
            }
          }
          await fixture.execute('DROP INDEX fbr195.$indexName');
        }
      },
      skip: databaseUrl == null ? 'RIVET_TEST_DATABASE_URL is not configured.' : false,
    );

    test(
      'should tune a transaction without changing exact or approximate query modes',
      () async {
        final query = Float32List.fromList([1, 0, 0]);
        statements.clear();

        await database.transaction((tx) async {
          await tx.setVectorSearchOptions(const HnswSearchOptions(efSearch: 80));
          await tx.setVectorSearchOptions(const IvfFlatSearchOptions(probes: 2));
          await tx.setVectorSearchOptions(
            const DiskAnnSearchOptions(searchListSize: 120, rescore: 60),
          );
          final setupCount = statements.length;

          final exact = await VectorDocuments.db
              .find(
                where: (document) => document.categoryId.equals(1),
                orderBy: (document) => [
                  document.embedding.l2Distance(query).asc(),
                  document.id.asc(),
                ],
                limit: 5,
                include: (include) => [include.category()],
              )
              .withScore((document) => document.embedding.l2Distance(query))
              .get(tx);
          expect(exact.map((row) => row.row.id), [1, 2, 4, 6, 7]);
          expect(statements, hasLength(setupCount + 1));
          expect(statements.last, startsWith('WITH "__rivet_roots" AS MATERIALIZED'));

          final approximate = await VectorDocuments.db
              .find(
                where: (document) => document.categoryId.equals(1),
                orderBy: (document) => [
                  document.embedding.l2Distance(query).asc(),
                  document.id.asc(),
                ],
                limit: 5,
                include: (include) => [include.category()],
                vectorSearch: VectorSearchMode.approximate,
              )
              .withScore((document) => document.embedding.l2Distance(query))
              .get(tx);
          expect(statements, hasLength(setupCount + 2));
          expect(statements.last, startsWith('WITH "__rivet_candidates" AS MATERIALIZED'));
          for (var index = 1; index < approximate.length; index++) {
            final previous = approximate[index - 1];
            final current = approximate[index];
            if (previous.score == current.score) {
              expect(previous.row.id, lessThan(current.row.id));
            } else if (previous.score != null && current.score != null) {
              expect(previous.score, lessThan(current.score!));
            }
          }
        });

        expect(statements.where((sql) => sql.contains('set_config')), hasLength(3));
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
        final queryCompilation = manifest['queryCompilation']! as Map<String, Object?>;
        final searchOptions = manifest['searchOptions']! as Map<String, Object?>;
        final indexes = manifest['indexes']! as Map<String, Object?>;
        final hnsw = indexes['hnsw']! as Map<String, Object?>;
        final ivfflat = indexes['ivfflat']! as Map<String, Object?>;
        final diskann = indexes['diskann']! as Map<String, Object?>;
        final server = await fixture.execute("SELECT current_setting('server_version')");
        final vector = await fixture.execute(
          "SELECT extversion FROM pg_extension WHERE extname = 'vector'",
        );
        final vectorscale = await fixture.execute(
          "SELECT extversion FROM pg_extension WHERE extname = 'vectorscale'",
        );
        final hnswOperatorClasses = await fixture.execute('''
          SELECT operator_class.opcname
          FROM pg_opclass AS operator_class
          JOIN pg_am AS access_method
            ON access_method.oid = operator_class.opcmethod
          WHERE access_method.amname = 'hnsw'
          ORDER BY operator_class.opcname
        ''');
        final ivfflatOperatorClasses = await fixture.execute('''
          SELECT operator_class.opcname
          FROM pg_opclass AS operator_class
          JOIN pg_am AS access_method
            ON access_method.oid = operator_class.opcmethod
          WHERE access_method.amname = 'ivfflat'
          ORDER BY operator_class.opcname
        ''');
        final diskannOperatorClasses = await fixture.execute('''
          SELECT operator_class.opcname
          FROM pg_opclass AS operator_class
          JOIN pg_am AS access_method
            ON access_method.oid = operator_class.opcmethod
          WHERE access_method.amname = 'diskann'
          ORDER BY operator_class.opcname
        ''');

        expect(server.single.first, startsWith(manifest['postgresql']! as String));
        expect(vector.single.first, extensions['vector']);
        expect(vectorscale.single.first, extensions['vectorscale']);
        expect(queryCompilation, {
          'exact': 'materializedEligibleRoots',
          'approximate': 'materializedIndexedCandidatesThenFinalSort',
          'candidateOrder': 'ascendingDistanceNullsLast',
          'singleStatement': true,
          'relaxedOrderOption': false,
        });
        expect(searchOptions['transactionLocal'], isTrue);
        expect(searchOptions['hnsw'], {
          'efSearch': {
            'setting': 'hnsw.ef_search',
            'minimum': 1,
            'maximum': 1000,
            'default': 40,
          },
        });
        expect(searchOptions['ivfflat'], {
          'probes': {
            'setting': 'ivfflat.probes',
            'minimum': 1,
            'maximum': 32768,
            'default': 1,
          },
        });
        expect(searchOptions['diskann'], {
          'searchListSize': {
            'setting': 'diskann.query_search_list_size',
            'minimum': 1,
            'maximum': 10000,
            'default': 100,
          },
          'rescore': {
            'setting': 'diskann.query_rescore',
            'minimum': 0,
            'maximum': 1000,
            'default': 50,
          },
        });
        expect(hnsw['extension'], 'vector');
        expect(hnsw['maximumDimensions'], 2000);
        expect(
          hnswOperatorClasses.map((row) => row.first),
          containsAll(hnsw['operatorClasses']! as List<Object?>),
        );
        expect(hnsw['buildOptions'], {
          'm': {'minimum': 2, 'maximum': 100},
          'efConstruction': {'minimum': 4, 'maximum': 1000},
        });
        expect(hnsw['concurrentBuild'], isFalse);
        expect(ivfflat['extension'], 'vector');
        expect(ivfflat['maximumDimensions'], 2000);
        expect(
          ivfflatOperatorClasses.map((row) => row.first),
          containsAll(ivfflat['operatorClasses']! as List<Object?>),
        );
        expect(ivfflat['buildOptions'], {
          'lists': {'minimum': 1, 'maximum': 32768, 'default': 100},
        });
        expect(ivfflat['concurrentBuild'], isFalse);
        expect(diskann['extension'], 'vectorscale');
        expect(diskann['maximumDimensions'], 16000);
        expect(diskann['plainMaximumDimensions'], 2000);
        expect(diskann['multiBitMaximumDimensions'], 930);
        expect(
          diskannOperatorClasses.map((row) => row.first),
          containsAll(diskann['operatorClasses']! as List<Object?>),
        );
        expect(diskann['storageLayouts'], ['memory_optimized', 'plain']);
        expect(diskann['buildOptions'], {
          'numNeighbors': {'minimum': 10, 'maximum': 1000, 'default': 50},
          'searchListSize': {'minimum': 10, 'maximum': 1000, 'default': 100},
          'maxAlpha': {'minimum': 1.0, 'maximum': 5.0, 'default': 1.2},
          'numDimensions': {
            'minimum': 1,
            'maximum': 'storedDimensions',
            'default': 'all',
          },
          'numBitsPerDimension': {
            'minimum': 1,
            'maximum': 32,
            'default': 'backendSelected',
          },
        });
        expect(diskann['concurrentBuild'], isFalse);
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
