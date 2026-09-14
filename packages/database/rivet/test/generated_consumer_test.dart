// Hand-built schemas intentionally rely on inferred declaration DSL types.
// ignore_for_file: specify_nonobvious_property_types

import 'dart:io';
import 'dart:typed_data';

import 'package:postgres/postgres.dart' as pg;
import 'package:rivet/rivet.dart';
import 'package:test/test.dart';

import 'generated_consumer.dart';

void main() {
  group('generated Rivet consumer', () {
    final databaseUrl = Platform.environment['RIVET_TEST_DATABASE_URL'];

    test(
      'should read zero, one, and multiple rows through generated APIs',
      () async {
        final resolvedDatabaseUrl = databaseUrl!;
        final fixture = await pg.Connection.openFromUrl(resolvedDatabaseUrl);
        addTearDown(fixture.close);
        await fixture.execute('CREATE SCHEMA IF NOT EXISTS fbr116');
        await fixture.execute('''
          CREATE TABLE IF NOT EXISTS fbr116."userProfiles" (
            "displayName" text NOT NULL
          )
        ''');
        await fixture.execute('TRUNCATE fbr116."userProfiles"');
        final statements = <String>[];
        final database = await RivetTestDatabase().open(
          connection: RivetConnection.url(resolvedDatabaseUrl, onStatement: statements.add),
          pool: const RivetPoolOptions(maxConnections: 2),
        );
        addTearDown(database.close);

        expect(await UserProfiles.db.find().get(database), isEmpty);

        await fixture.execute('''
          INSERT INTO fbr116."userProfiles" ("displayName")
          VALUES ('Ada'), ('Grace')
        ''');

        final one = await UserProfiles.db
            .find(where: (users) => users.displayName.equals('Ada'))
            .get(database);
        final all = await UserProfiles.db.find().get(database);

        expect(one.single.displayName, 'Ada');
        expect(one.single.posts.isLoaded, isFalse);
        expect(all.map((row) => row.displayName), containsAll(['Ada', 'Grace']));
        expect(statements, hasLength(3));
        expect(
          statements.singleWhere((sql) => sql.contains('WHERE')),
          contains(r'"displayName" = $1'),
        );
      },
      skip: databaseUrl == null ? 'RIVET_TEST_DATABASE_URL is not configured.' : false,
    );

    test(
      'should load checked one relations in one statement',
      () async {
        final resolvedDatabaseUrl = databaseUrl!;
        final fixture = await pg.Connection.openFromUrl(resolvedDatabaseUrl);
        addTearDown(fixture.close);
        await fixture.execute('CREATE SCHEMA IF NOT EXISTS fbr116');
        await fixture.execute('DROP TABLE IF EXISTS fbr116.posts');
        await fixture.execute('DROP TABLE IF EXISTS fbr116."userProfiles"');
        await fixture.execute('''
          CREATE TABLE fbr116."userProfiles" (
            "displayName" text NOT NULL
          )
        ''');
        await fixture.execute('''
          CREATE TABLE fbr116.posts (
            "authorName" text NOT NULL
          )
        ''');
        await fixture.execute('''
          INSERT INTO fbr116."userProfiles" ("displayName") VALUES ('Ada')
        ''');
        await fixture.execute('''
          INSERT INTO fbr116.posts ("authorName") VALUES ('Ada'), ('Missing')
        ''');
        final statements = <String>[];
        final database = await RivetTestDatabase().open(
          connection: RivetConnection.url(resolvedDatabaseUrl, onStatement: statements.add),
          pool: const RivetPoolOptions(maxConnections: 2),
        );
        addTearDown(database.close);

        final rows = await Posts.db
            .find(
              orderBy: (post) => [post.authorName.asc()],
              include: (include) => [include.author()],
            )
            .get(database);
        final ada = rows.singleWhere((row) => row.authorName == 'Ada');
        final missing = rows.singleWhere((row) => row.authorName == 'Missing');

        expect((ada.author as LoadedRelation<UserProfilesRow?>).value?.displayName, 'Ada');
        expect((missing.author as LoadedRelation<UserProfilesRow?>).value, isNull);
        expect(ada.author.isLoaded, isTrue);
        expect((ada.author as LoadedRelation<UserProfilesRow?>).value?.posts.isLoaded, isFalse);
        expect(statements, hasLength(1));

        await database.transaction((tx) async {
          final row = await Posts.db
              .find(
                where: (post) => post.authorName.equals('Ada'),
                include: (include) => [include.author()],
              )
              .getSingle(tx);
          expect((row.author as LoadedRelation<UserProfilesRow?>).value, isNotNull);
        });
        expect(statements, hasLength(2));

        await fixture.execute('''
          INSERT INTO fbr116."userProfiles" ("displayName") VALUES ('Ada')
        ''');
        await expectLater(
          Posts.db
              .find(
                where: (post) => post.authorName.equals('Ada'),
                include: (include) => [include.author()],
              )
              .get(database),
          throwsA(
            isA<RivetCardinalityException>().having(
              (error) => error.relationPath,
              'relationPath',
              'author',
            ),
          ),
        );
        expect(statements, hasLength(3));
      },
      skip: databaseUrl == null ? 'RIVET_TEST_DATABASE_URL is not configured.' : false,
    );

    test(
      'should expose and validate generated schema metadata without analyzer dependencies',
      () async {
        final users = UserProfiles.db.buildSchema();
        final posts = Posts.db.buildSchema();

        expect(users.formatVersion, 1);
        expect(users.renamedFrom, 'profiles');
        expect(users.indexes.single.name, 'display_name_idx');
        expect(users.constraints.single.name, 'display_name_present');
        expect(users.constraints.single.predicate?.schemaExpression(), {
          'formatVersion': 1,
          'kind': 'operator',
          'operator': '=',
          'arguments': [
            {'formatVersion': 1, 'kind': 'reference', 'objectName': 'displayName'},
            {
              'formatVersion': 1,
              'kind': 'literal',
              'literalType': 'string',
              'value': '',
            },
          ],
        });
        expect(users.relations['posts']?.kind, RivetRelationKind.many);
        expect(posts.relations['author']?.kind, RivetRelationKind.one);
        expect(posts.columns.single.foreignKey?.targetTable, UserProfiles);

        final metadataDatabase = await RivetTestDatabase().open(
          connection: RivetConnection.url(
            'postgresql://localhost/unused',
            sslMode: RivetSslMode.disable,
          ),
        );
        addTearDown(metadataDatabase.close);
        expect(metadataDatabase.name, 'rivet_test');
        final registeredPosts = metadataDatabase.tables.singleWhere(
          (table) => table.definition is Posts,
        );
        final registeredUsers = metadataDatabase.tables.singleWhere(
          (table) => table.definition is UserProfiles,
        );
        final author = registeredPosts.relations['author']!;
        expect(author.fields.single.physicalName, 'authorName');
        expect(author.references.single.physicalName, 'displayName');
        expect(registeredUsers.relations['posts']?.inverseRelation, same(author));
        expect(
          registeredPosts.columns.single.foreignKey?.referencedColumn?.physicalName,
          'displayName',
        );
      },
    );

    test('should preserve explicit composite one-relation mapping order', () async {
      final parent = _compositeParentSchema();
      final child = _compositeChildSchema();
      final database = await RivetDb.open(
        name: 'composite_relation_test',
        connection: RivetConnection.url(
          'postgresql://localhost/unused',
          sslMode: RivetSslMode.disable,
        ),
        pool: const RivetPoolOptions(),
        tables: [parent, child],
      );
      addTearDown(database.close);

      final relation = child.relations['parent']!;
      expect(relation.fields.map((column) => column.dartName), ['second', 'first']);
      expect(relation.references.map((column) => column.dartName), ['second', 'first']);
      expect(child.columns.every((column) => column.foreignKey == null), isTrue);
    });

    test('should compile composite collection inverses in mapping order', () async {
      final parent = _compositeParentSchema();
      final child = _compositeChildSchema();
      final executor = _CaptureExecutor();
      final include = RivetInclude<Object?, Object?>(
        name: 'children',
        path: 'children',
        relation: parent.relations['children']!,
        targetSchema: child,
      );

      await RivetFind<Object?, Object?>(parent, includes: [include]).get(executor);

      expect(executor.query.sql, contains('"__rivet_t1"."second" = "__rivet_t0"."second"'));
      expect(executor.query.sql, contains('"__rivet_t1"."first" = "__rivet_t0"."first"'));
      expect(
        executor.query.sql.indexOf('"__rivet_t1"."second" = "__rivet_t0"."second"'),
        lessThan(
          executor.query.sql.indexOf('"__rivet_t1"."first" = "__rivet_t0"."first"'),
        ),
      );
      expect(parent.columns.every((column) => column.foreignKey == null), isTrue);
      expect(child.columns.every((column) => column.foreignKey == null), isTrue);
    });

    test('should reject duplicate and missing schema registrations before connecting', () async {
      final connection = RivetConnection.url(
        'postgresql://localhost/unused',
        sslMode: RivetSslMode.disable,
      );
      final users = UserProfiles.db.buildSchema() as RivetTableSchema<Object?, Object?>;
      final posts = Posts.db.buildSchema() as RivetTableSchema<Object?, Object?>;

      await expectLater(
        RivetDb.open(
          name: 'duplicate_test',
          connection: connection,
          pool: const RivetPoolOptions(),
          tables: [users, users],
        ),
        throwsArgumentError,
      );
      await expectLater(
        RivetDb.open(
          name: 'missing_test',
          connection: connection,
          pool: const RivetPoolOptions(),
          tables: [posts],
        ),
        throwsArgumentError,
      );
    });

    test('should reject null definitions and redact credentials in URL errors', () async {
      final nullDefinition = RivetTableSchema<Object?, Object?>(
        schemaName: 'invalid',
        tableName: 'nullDefinition',
        definition: null,
        columns: const [],
        columnNames: const [],
        decode: (_, _) => Object(),
      );
      await expectLater(
        RivetDb.open(
          name: 'null_definition_test',
          connection: RivetConnection.url(
            'postgresql://localhost/unused',
            sslMode: RivetSslMode.disable,
          ),
          pool: const RivetPoolOptions(),
          tables: [nullDefinition],
        ),
        throwsArgumentError,
      );

      final users = UserProfiles.db.buildSchema() as RivetTableSchema<Object?, Object?>;
      await expectLater(
        RivetDb.open(
          name: 'redaction_test',
          connection: RivetConnection.url(
            'mysql://builder:super-secret@localhost/inframe',
            sslMode: RivetSslMode.disable,
          ),
          pool: const RivetPoolOptions(),
          tables: [users],
        ),
        throwsA(
          isA<ArgumentError>()
              .having((error) => error.toString(), 'message', contains('mysql'))
              .having((error) => error.toString(), 'message', isNot(contains('super-secret'))),
        ),
      );
    });

    test('should retain metadata after column modifiers and attach names before expressions', () {
      final schema = MetadataColumns.db.buildSchema();
      final table = schema.definition;

      expect(schema.constraints.single.expression, contains('"count"'));
      expect(schema.indexes.single.predicate?.sql, contains('"count"'));
      expect(table.count.sqlDefault, '1');
      expect(table.count.defaultFn?.call(), 2);
      expect(table.payload.defaultFn?.call(), JsonValue.from(const {}));
      expect(table.embedding.onUpdateFn?.call(), isA<Float32List>());
      expect(table.values.defaultFn?.call(), [1]);
      expect((table.code.defaultFn!()! as UserCode).value, 'code_generated');
      expect((table.code.onUpdateFn!()! as UserCode).value, 'code_updated');
      expect(table.code.storage.asc(), isA<RivetOrder>());
    });

    test('should expose validated vector-index metadata without filling omitted defaults', () {
      final schema = VectorDocuments.db.buildSchema();
      final declaration = RivetDatabaseSchema(
        name: 'vector_indexes',
        tables: [schema as RivetTableSchema<Object?, Object?>],
      ).toJson();
      final table = (declaration['tables']! as List<Object?>).single! as Map<String, Object?>;
      final indexes = (table['indexes']! as List<Object?>).cast<Map<String, Object?>>();

      expect(indexes.take(3).map((index) => index['method']), everyElement('hnsw'));
      expect(indexes.first['options'], {'m': 8, 'efConstruction': 32});
      expect(indexes[1]['options'], isEmpty);
      expect(
        indexes
            .take(3)
            .map(
              (index) =>
                  ((index['terms']! as List<Object?>).single!
                      as Map<String, Object?>)['operatorClass'],
            ),
        ['vector_cosine_ops', 'vector_l2_ops', 'vector_ip_ops'],
      );
      expect(declaration['requirements'], [
        {
          'kind': 'extension',
          'name': 'vector',
          'minimumVersion': '0.8.6',
          'indexMethods': {
            'hnsw': ['vector_cosine_ops', 'vector_ip_ops', 'vector_l2_ops'],
            'ivfflat': ['vector_cosine_ops', 'vector_ip_ops', 'vector_l2_ops'],
          },
        },
        {
          'kind': 'extension',
          'name': 'vectorscale',
          'minimumVersion': '0.9.1',
          'indexMethods': {
            'diskann': ['vector_cosine_ops', 'vector_ip_ops', 'vector_l2_ops'],
          },
        },
      ]);
      expect(
        indexes.skip(3).take(3).map((index) => index['method']),
        everyElement('ivfflat'),
      );
      expect(indexes[3]['options'], {'lists': 4});
      expect(indexes[4]['options'], isEmpty);
      expect(
        indexes
            .skip(3)
            .take(3)
            .map(
              (index) =>
                  ((index['terms']! as List<Object?>).single!
                      as Map<String, Object?>)['operatorClass'],
            ),
        ['vector_cosine_ops', 'vector_l2_ops', 'vector_ip_ops'],
      );
      expect(indexes.skip(6).map((index) => index['method']), everyElement('diskann'));
      expect(indexes[6]['options'], {
        'storageLayout': 'memory_optimized',
        'numNeighbors': 20,
        'searchListSize': 30,
        'maxAlpha': 1.4,
        'numDimensions': 2,
        'numBitsPerDimension': 2,
      });
      expect(indexes[7]['options'], {'storageLayout': 'plain'});
      expect(indexes[8]['options'], isEmpty);
      expect(
        indexes
            .skip(6)
            .map(
              (index) =>
                  ((index['terms']! as List<Object?>).single!
                      as Map<String, Object?>)['operatorClass'],
            ),
        ['vector_cosine_ops', 'vector_l2_ops', 'vector_ip_ops'],
      );
    });

    test('should reject HNSW options that violate backend defaults', () {
      expect(() => _hnswSchema(const Hnsw(m: 16, efConstruction: 31)), throwsArgumentError);
      expect(() => _hnswSchema(const Hnsw(m: 100)), throwsArgumentError);
      expect(() => _hnswSchema(const Hnsw(efConstruction: 31)), throwsArgumentError);
      expect(() => _hnswSchema(const Hnsw(m: 16, efConstruction: 32)), returnsNormally);
    });

    test('should compose one native enum declaration for scalar and array storage', () {
      final declaration = RivetDatabaseSchema(
        name: 'enum_fixture',
        tables: [EnumValues.db.buildSchema()],
      ).toJson();
      final enumValue = (declaration['enums']! as List<Object?>).single! as Map<String, Object?>;
      final table = (declaration['tables']! as List<Object?>).single! as Map<String, Object?>;
      final columns = (table['columns']! as List<Object?>).cast<Map<String, Object?>>();

      expect(enumValue['schema'], 'fbr120');
      expect(enumValue['name'], 'workStatus');
      expect(enumValue['values'], [
        {'dartName': 'queued', 'label': 'zeta'},
        {'dartName': 'complete', 'label': 'alpha'},
      ]);
      expect(
        (columns.first['storage']! as Map<String, Object?>)['enum'],
        {'schema': 'fbr120', 'name': 'workStatus'},
      );
      final arrayStorage = columns[2]['storage']! as Map<String, Object?>;
      expect(arrayStorage['nullable'], false);
      expect((arrayStorage['element']! as Map<String, Object?>)['nullable'], true);
    });

    test('should discover a native enum used only inside array storage', () {
      final declaration = RivetDatabaseSchema(
        name: 'array_enum_fixture',
        tables: [ArrayValues.db.buildSchema()],
      ).toJson();

      final enumValue = (declaration['enums']! as List<Object?>).single! as Map<String, Object?>;
      expect(enumValue['name'], 'workStatus');
    });

    test('should compose relation predicates before rendering them', () {
      final relation = RivetPredicate.relation(
        renderSql: (_, nextAlias) => 'EXISTS (${nextAlias()})',
        parameters: const [],
        columns: const [],
      );

      final predicate = relation & ~relation;

      expect(
        predicate.renderWith((index) => '\$$index', () => 'SELECT 1'),
        '(EXISTS (SELECT 1)) AND (NOT (EXISTS (SELECT 1)))',
      );
      expect(predicate.schemaExpression, throwsUnsupportedError);
    });

    test('should reject incompatible foreign-key storage before connecting', () async {
      final connection = RivetConnection.url(
        'postgresql://localhost/unused',
        sslMode: RivetSslMode.disable,
      );
      final target = TextTargets.db.buildSchema() as RivetTableSchema<Object?, Object?>;
      final source = InvalidReferences.db.buildSchema() as RivetTableSchema<Object?, Object?>;

      await expectLater(
        RivetDb.open(
          name: 'foreign_key_test',
          connection: connection,
          pool: const RivetPoolOptions(),
          tables: [target, source],
        ),
        throwsArgumentError,
      );
    });
  });
}

final class _CompositeParent extends RivetTableDefinition<_CompositeParent> {
  late final first = integer()();
  late final second = integer()();
  late final children = many<_CompositeChild>(relation: (child) => child.parent)();
}

final class _HnswTable extends RivetTableDefinition<_HnswTable> {
  _HnswTable(this.method);

  final Hnsw method;
  late final embedding = vector(dimensions: 3)();
  late final indexes = [
    index('embedding_hnsw').using(method).on([embedding.l2Ops()]),
  ];
}

RivetTableSchema<_HnswTable, Object> _hnswSchema(Hnsw method) {
  final definition = _HnswTable(method);
  return RivetTableSchema<_HnswTable, Object>(
    schemaName: 'search',
    tableName: 'documents',
    definition: definition,
    columns: [definition.embedding],
    columnNames: const ['embedding'],
    decode: (_, _) => Object(),
    indexes: () => definition.indexes,
  );
}

final class _CompositeChild extends RivetTableDefinition<_CompositeChild> {
  late final first = integer()();
  late final second = integer()();
  late final parent = one<_CompositeParent>(
    fields: [second, first],
    references: (parent) => [parent.second, parent.first],
  )();
}

RivetTableSchema<Object?, Object?> _compositeParentSchema() {
  final definition = _CompositeParent();
  return RivetTableSchema<_CompositeParent, Object>(
    schemaName: 'composite',
    tableName: 'parents',
    definition: definition,
    columns: [definition.first, definition.second],
    columnNames: const ['first', 'second'],
    decode: (_, _) => Object(),
    relations: {
      'children': definition.children as RivetRelationDescriptor<Object?>,
    },
  ) as RivetTableSchema<Object?, Object?>;
}

RivetTableSchema<Object?, Object?> _compositeChildSchema() {
  final definition = _CompositeChild();
  return RivetTableSchema<_CompositeChild, Object>(
    schemaName: 'composite',
    tableName: 'children',
    definition: definition,
    columns: [definition.first, definition.second],
    columnNames: const ['first', 'second'],
    decode: (_, _) => Object(),
    relations: {
      'parent': definition.parent as RivetRelationDescriptor<Object?>,
    },
  ) as RivetTableSchema<Object?, Object?>;
}

final class _CaptureExecutor implements RivetExecutor {
  late RivetCompiledQuery query;

  @override
  Future<List<Row>> execute<Row>(
    RivetCompiledQuery query,
    RivetRowDecoder<Row> decode,
  ) async {
    this.query = query;
    return [];
  }

  @override
  Future<int> executeAffected(RivetCompiledQuery query) async {
    this.query = query;
    return 0;
  }
}
