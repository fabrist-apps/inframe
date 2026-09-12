import 'dart:io';
import 'dart:typed_data';

import 'package:postgres/postgres.dart' as pg;
import 'package:rivet/rivet.dart';
import 'package:test/test.dart';

import 'generated_consumer.dart';

void main() {
  group('generated Rivet consumer', () {
    final databaseUrl = Platform.environment['RIVET_TEST_DATABASE_URL'];
    late pg.Connection fixture;
    late RivetDb database;
    late List<String> statements;

    setUp(() async {
      if (databaseUrl == null) return;
      fixture = await pg.Connection.openFromUrl(databaseUrl);
      await fixture.execute('CREATE SCHEMA IF NOT EXISTS fbr116');
      await fixture.execute('''
        CREATE TABLE IF NOT EXISTS fbr116."userProfiles" (
          "displayName" text NOT NULL
        )
      ''');
      await fixture.execute('TRUNCATE fbr116."userProfiles"');
      statements = [];
      database = await RivetTestDatabase().open(
        connection: RivetConnection.url(databaseUrl, onStatement: statements.add),
        pool: const RivetPoolOptions(maxConnections: 2),
      );
    });

    tearDown(() async {
      if (databaseUrl == null) return;
      await database.close();
      await fixture.close();
    });

    test(
      'should read zero, one, and multiple rows through generated APIs',
      () async {
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
      'should expose and validate generated schema metadata without analyzer dependencies',
      () async {
        final users = UserProfiles.db.buildSchema();
        final posts = Posts.db.buildSchema();

        expect(users.formatVersion, 1);
        expect(users.renamedFrom, 'profiles');
        expect(users.indexes.single.name, 'display_name_idx');
        expect(users.constraints.single.name, 'display_name_present');
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

    test('should reject duplicate and missing schema registrations before connecting', () async {
      final connection = RivetConnection.url(
        'postgresql://localhost/unused',
        sslMode: RivetSslMode.disable,
      );
      final users = UserProfiles.db.buildSchema() as RivetTableSchema<Object?, Object?>;
      final posts = Posts.db.buildSchema() as RivetTableSchema<Object?, Object?>;

      await expectLater(
        RivetDb.open(
          connection: connection,
          pool: const RivetPoolOptions(),
          tables: [users, users],
        ),
        throwsArgumentError,
      );
      await expectLater(
        RivetDb.open(connection: connection, pool: const RivetPoolOptions(), tables: [posts]),
        throwsArgumentError,
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

    test('should reject incompatible foreign-key storage before connecting', () async {
      final connection = RivetConnection.url(
        'postgresql://localhost/unused',
        sslMode: RivetSslMode.disable,
      );
      final target = TextTargets.db.buildSchema() as RivetTableSchema<Object?, Object?>;
      final source = InvalidReferences.db.buildSchema() as RivetTableSchema<Object?, Object?>;

      await expectLater(
        RivetDb.open(
          connection: connection,
          pool: const RivetPoolOptions(),
          tables: [target, source],
        ),
        throwsArgumentError,
      );
    });
  });
}
