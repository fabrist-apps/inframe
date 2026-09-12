import 'dart:io';

import 'package:postgres/postgres.dart' as pg;
import 'package:rivet/rivet.dart';
import 'package:test/test.dart';

import 'generated_consumer.dart';

void main() {
  group('Rivet through collections', () {
    final databaseUrl = Platform.environment['RIVET_TEST_DATABASE_URL'];
    late pg.Connection fixture;
    late RivetDb database;
    late List<String> statements;

    setUp(() async {
      if (databaseUrl == null) return;
      fixture = await pg.Connection.openFromUrl(databaseUrl);
      await fixture.execute('DROP SCHEMA IF EXISTS fbr147 CASCADE');
      await fixture.execute('CREATE SCHEMA fbr147');
      await fixture.execute('''
        CREATE TABLE fbr147."throughBooks" (
          tenant integer NOT NULL, id integer NOT NULL, title text NOT NULL
        )
      ''');
      await fixture.execute('''
        CREATE TABLE fbr147."throughTags" (
          namespace text NOT NULL, code text NOT NULL, name text NOT NULL
        )
      ''');
      await fixture.execute('''
        CREATE TABLE fbr147."throughBookTags" (
          "bookTenant" integer NOT NULL,
          "bookId" integer NOT NULL,
          "tagNamespace" text NOT NULL,
          "tagCode" text NOT NULL,
          position integer NOT NULL
        )
      ''');
      await fixture.execute('''
        CREATE TABLE fbr147."throughReviews" (
          id integer NOT NULL,
          "bookTenant" integer NOT NULL,
          "bookId" integer NOT NULL,
          body text NOT NULL
        )
      ''');
      await fixture.execute('''
        CREATE TABLE fbr147."throughTagNotes" (
          id integer NOT NULL,
          "tagNamespace" text NOT NULL,
          "tagCode" text NOT NULL,
          body text NOT NULL
        )
      ''');
      await fixture.execute('''
        INSERT INTO fbr147."throughBooks" VALUES
          (1, 10, 'First'), (1, 20, 'Second'), (2, 10, 'Empty')
      ''');
      await fixture.execute('''
        INSERT INTO fbr147."throughTags" VALUES
          ('n', 'a', 'Alpha'), ('n', 'b', 'Beta'), ('n', 'c', 'Gamma')
      ''');
      await fixture.execute('''
        INSERT INTO fbr147."throughBookTags" VALUES
          (1, 10, 'n', 'a', 1),
          (1, 10, 'n', 'b', 2),
          (1, 10, 'n', 'missing', 3),
          (1, 20, 'n', 'a', 1)
      ''');
      await fixture.execute('''
        INSERT INTO fbr147."throughReviews" VALUES
          (1, 1, 10, 'good'), (2, 1, 10, 'great'), (3, 1, 20, 'fine')
      ''');
      await fixture.execute('''
        INSERT INTO fbr147."throughTagNotes" VALUES
          (1, 'n', 'a', 'alpha note'), (2, 'n', 'b', 'beta note')
      ''');
      statements = [];
      database = await RivetTestDatabase().open(
        connection: RivetConnection.url(databaseUrl, onStatement: statements.add),
      );
    });

    tearDown(() async {
      if (databaseUrl == null) return;
      await database.close();
      await fixture.close();
    });

    test(
      'should load composite through paths beside ordinary collections',
      () async {
        final books = await ThroughBooks.db
            .find(
              orderBy: (book) => [book.tenant.asc(), book.id.asc()],
              include: (include) => [
                include.tags(
                  orderBy: (tag) => [tag.code.desc()],
                  limit: 2,
                  include: (include) => [include.notes()],
                ),
                include.reviews(orderBy: (review) => [review.id.asc()]),
              ],
            )
            .get(database);

        final firstTags = (books[0].tags as LoadedRelation<List<ThroughTagsRow>>).value;
        expect(firstTags.map((tag) => tag.code), ['b', 'a']);
        expect(
          (firstTags.first.notes as LoadedRelation<List<ThroughTagNotesRow>>).value.map(
            (note) => note.body,
          ),
          ['beta note'],
        );
        expect(
          (books[0].reviews as LoadedRelation<List<ThroughReviewsRow>>).value.map(
            (review) => review.id,
          ),
          [1, 2],
        );
        expect(
          (books[1].tags as LoadedRelation<List<ThroughTagsRow>>).value.map((tag) => tag.code),
          ['a'],
        );
        expect((books[2].tags as LoadedRelation<List<ThroughTagsRow>>).value, isEmpty);
        expect(statements, hasLength(1));

        final links = await ThroughBookTags.db
            .find(orderBy: (link) => [link.position.asc()])
            .get(database);
        expect(links, everyElement(isA<ThroughBookTagRecord>()));
        expect(links.map((link) => link.position), [1, 1, 2, 3]);
        expect(links.every((link) => !link.book.isLoaded && !link.tag.isLoaded), isTrue);
        expect(statements, hasLength(2));
      },
      skip: databaseUrl == null ? 'RIVET_TEST_DATABASE_URL is not configured.' : false,
    );

    test(
      'should filter and limit through targets independently for each parent',
      () async {
        final books = await ThroughBooks.db
            .find(
              orderBy: (book) => [book.tenant.asc(), book.id.asc()],
              include: (include) => [
                include.tags(
                  where: (tag) => tag.name.equals('Alpha'),
                  orderBy: (tag) => [tag.code.asc()],
                  limit: 1,
                ),
              ],
            )
            .get(database);

        expect(
          books.map(
            (book) => (book.tags as LoadedRelation<List<ThroughTagsRow>>).value.length,
          ),
          [1, 1, 0],
        );
        expect(statements, hasLength(1));
      },
      skip: databaseUrl == null ? 'RIVET_TEST_DATABASE_URL is not configured.' : false,
    );

    test(
      'should filter roots across nested through paths without loading them',
      () async {
        final books = await ThroughBooks.db
            .find(
              where: (book) => book.tags.any(
                (tag) => tag.notes.any((note) => note.body.equals('beta note')),
              ),
            )
            .get(database);

        expect(books.map((book) => book.title), ['First']);
        expect(books.single.tags.isLoaded, isFalse);
        expect(statements, hasLength(1));
      },
      skip: databaseUrl == null ? 'RIVET_TEST_DATABASE_URL is not configured.' : false,
    );

    test(
      'should mutate targets selected through composite junction paths',
      () async {
        final changed = await ThroughBooks.db
            .update(
              ThroughBooksCompanion.update(
                title: const RivetValue.present('matched'),
              ),
              where: (book) => book.tags.any(
                (tag) => tag.name.equals('Beta'),
              ),
            )
            .returning()
            .get(database);

        expect(changed.map((book) => book.id), [10]);
        expect(changed.single.title, 'matched');
        expect(changed.single.tags.isLoaded, isFalse);
        expect(statements, hasLength(1));
      },
      skip: databaseUrl == null ? 'RIVET_TEST_DATABASE_URL is not configured.' : false,
    );
  });
}
