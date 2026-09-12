import 'dart:io';

import 'package:postgres/postgres.dart' as pg;
import 'package:rivet/rivet.dart';
import 'package:test/test.dart';

import 'generated_consumer.dart';

void main() {
  group('Rivet relational collections', () {
    final databaseUrl = Platform.environment['RIVET_TEST_DATABASE_URL'];
    late pg.Connection fixture;
    late RivetDb database;
    late List<String> statements;

    setUp(() async {
      if (databaseUrl == null) return;
      fixture = await pg.Connection.openFromUrl(databaseUrl);
      await fixture.execute('DROP SCHEMA IF EXISTS fbr146 CASCADE');
      await fixture.execute('CREATE SCHEMA fbr146');
      await fixture.execute('''
        CREATE TABLE fbr146."relationalUsers" (
          id integer NOT NULL,
          name text NOT NULL,
          "managerId" integer
        )
      ''');
      await fixture.execute('''
        CREATE TABLE fbr146."relationalPosts" (
          id integer PRIMARY KEY,
          "authorId" integer NOT NULL,
          "reviewerId" integer,
          title text NOT NULL,
          rank integer NOT NULL,
          weight double precision NOT NULL,
          quality double precision
        )
      ''');
      await fixture.execute('''
        CREATE TABLE fbr146."relationalComments" (
          id integer PRIMARY KEY,
          "postId" integer NOT NULL,
          body text NOT NULL
        )
      ''');
      await fixture.execute('''
        INSERT INTO fbr146."relationalUsers" VALUES
          (1, 'Ada', NULL), (2, 'Grace', 1), (3, 'Linus', NULL)
      ''');
      await fixture.execute('''
        INSERT INTO fbr146."relationalPosts" VALUES
          (11, 1, 2, 'Ada first', 1, 1.0, 1.5),
          (12, 1, NULL, 'Ada third', 3, 3.0, NULL),
          (13, 1, 2, 'Ada second', 2, 2.0, 2.5),
          (14, 2, 1, 'Grace only', 4, 4.0, 4.5)
      ''');
      await fixture.execute('''
        INSERT INTO fbr146."relationalComments" VALUES
          (101, 11, 'old'),
          (102, 11, 'new'),
          (103, 12, 'only')
      ''');
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
      'should load nested and sibling collections with per-parent limits',
      () async {
        final users = await RelationalUsers.db
            .find(
              orderBy: (user) => [user.id.asc()],
              include: (include) => [
                include.authoredPosts(
                  orderBy: (post) => [post.rank.desc()],
                  limit: 2,
                  include: (include) => [
                    include.comments(
                      orderBy: (comment) => [comment.id.desc()],
                      limit: 1,
                    ),
                    include.author(
                      include: (include) => [
                        include.reviewedPosts(
                          orderBy: (post) => [post.rank.desc()],
                          limit: 1,
                        ),
                      ],
                    ),
                  ],
                ),
                include.reviewedPosts(orderBy: (post) => [post.rank.asc()]),
              ],
            )
            .get(database);

        final ada = users[0];
        final grace = users[1];
        final linus = users[2];
        final adaPosts = (ada.authoredPosts as LoadedRelation<List<RelationalPostsRow>>).value;
        final gracePosts = (grace.authoredPosts as LoadedRelation<List<RelationalPostsRow>>).value;

        expect(adaPosts.map((post) => post.id), [12, 13]);
        expect(gracePosts.map((post) => post.id), [14]);
        expect(
          (linus.authoredPosts as LoadedRelation<List<RelationalPostsRow>>).value,
          isEmpty,
        );
        expect(
          (ada.reviewedPosts as LoadedRelation<List<RelationalPostsRow>>).value.map(
            (post) => post.id,
          ),
          [14],
        );
        expect(
          (grace.reviewedPosts as LoadedRelation<List<RelationalPostsRow>>).value.map(
            (post) => post.id,
          ),
          [11, 13],
        );

        final comments =
            (adaPosts.first.comments as LoadedRelation<List<RelationalCommentsRow>>).value;
        expect(comments.map((comment) => comment.id), [103]);
        final author = (adaPosts.first.author as LoadedRelation<RelationalUsersRow?>).value!;
        expect(author.name, 'Ada');
        expect(
          (author.reviewedPosts as LoadedRelation<List<RelationalPostsRow>>).value.map(
            (post) => post.id,
          ),
          [14],
        );
        expect(statements, hasLength(1));
      },
      skip: databaseUrl == null ? 'RIVET_TEST_DATABASE_URL is not configured.' : false,
    );

    test(
      'should apply collection filters independently for each parent',
      () async {
        final users = await RelationalUsers.db
            .find(
              orderBy: (user) => [user.id.asc()],
              include: (include) => [
                include.authoredPosts(where: (post) => post.title.equals('Ada second')),
              ],
            )
            .get(database);

        expect(
          (users[0].authoredPosts as LoadedRelation<List<RelationalPostsRow>>).value.map(
            (post) => post.id,
          ),
          [13],
        );
        expect(
          (users[1].authoredPosts as LoadedRelation<List<RelationalPostsRow>>).value,
          isEmpty,
        );
        expect(statements, hasLength(1));
      },
      skip: databaseUrl == null ? 'RIVET_TEST_DATABASE_URL is not configured.' : false,
    );

    test(
      'should keep root pagination separate from stable child pagination',
      () async {
        final rootPage = await RelationalUsers.db
            .find(
              orderBy: (user) => [user.id.desc()],
              limit: 1,
              offset: 1,
              include: (include) => [include.authoredPosts()],
            )
            .get(database);
        expect(rootPage.map((user) => user.name), ['Grace']);
        expect(
          (rootPage.single.authoredPosts as LoadedRelation<List<RelationalPostsRow>>).value.map(
            (post) => post.id,
          ),
          [14],
        );

        final ada = await RelationalUsers.db
            .find(
              where: (user) => user.name.equals('Ada'),
              include: (include) => [
                include.authoredPosts(
                  orderBy: (post) => [
                    post.reviewerId.asc(nulls: NullsOrder.first),
                    post.id.asc(),
                  ],
                  limit: 2,
                ),
              ],
            )
            .getSingle(database);
        expect(
          (ada.authoredPosts as LoadedRelation<List<RelationalPostsRow>>).value.map(
            (post) => post.id,
          ),
          [12, 11],
        );
        expect(statements, hasLength(2));
      },
      skip: databaseUrl == null ? 'RIVET_TEST_DATABASE_URL is not configured.' : false,
    );

    test(
      'should reject nested duplicate includes before execution',
      () {
        expect(
          () => RelationalUsers.db.find(
            include: (include) => [
              include.authoredPosts(
                include: (include) => [include.comments(), include.comments()],
              ),
            ],
          ),
          throwsA(
            isA<RivetUnsupportedQueryException>().having(
              (error) => error.message,
              'message',
              contains('authoredPosts.comments'),
            ),
          ),
        );
        expect(statements, isEmpty);
      },
      skip: databaseUrl == null ? 'RIVET_TEST_DATABASE_URL is not configured.' : false,
    );

    test(
      'should report the full path for duplicate nested one matches',
      () async {
        await fixture.execute('''
          INSERT INTO fbr146."relationalUsers" VALUES (1, 'Ada duplicate', NULL)
        ''');

        await expectLater(
          RelationalUsers.db
              .find(
                where: (user) => user.name.equals('Ada'),
                include: (include) => [
                  include.authoredPosts(
                    include: (include) => [include.author()],
                  ),
                ],
              )
              .get(database),
          throwsA(
            isA<RivetCardinalityException>().having(
              (error) => error.relationPath,
              'relationPath',
              'authoredPosts.author',
            ),
          ),
        );
        expect(statements, hasLength(1));
      },
      skip: databaseUrl == null ? 'RIVET_TEST_DATABASE_URL is not configured.' : false,
    );

    test(
      'should filter roots with one matches and many any or none',
      () async {
        final authored = await RelationalPosts.db
            .find(
              where: (post) => post.author.matches((user) => user.name.equals('Ada')),
              orderBy: (post) => [post.id.asc()],
            )
            .get(database);
        expect(authored.map((post) => post.id), [11, 12, 13]);
        expect(authored.every((post) => !post.author.isLoaded), isTrue);

        final any = await RelationalUsers.db
            .find(
              where: (user) => user.authoredPosts.any(
                (post) => post.title.equals('Ada second'),
              ),
              include: (include) => [
                include.authoredPosts(
                  where: (post) => post.title.equals('Ada first'),
                  limit: 1,
                ),
              ],
            )
            .getSingle(database);
        expect(any.name, 'Ada');
        expect(
          (any.authoredPosts as LoadedRelation<List<RelationalPostsRow>>).value.map(
            (post) => post.id,
          ),
          [11],
        );

        final none = await RelationalUsers.db
            .find(
              where: (user) => user.reviewedPosts.none(
                (post) => post.title.equals('Grace only'),
              ),
              orderBy: (user) => [user.id.asc()],
            )
            .get(database);
        expect(none.map((user) => user.name), ['Grace', 'Linus']);
        expect(none.every((user) => !user.reviewedPosts.isLoaded), isTrue);
        expect(statements, hasLength(3));
      },
      skip: databaseUrl == null ? 'RIVET_TEST_DATABASE_URL is not configured.' : false,
    );

    test(
      'should compose nested relation predicates in a transaction',
      () async {
        await database.transaction((tx) async {
          final users = await RelationalUsers.db
              .find(
                where: (user) => user.authoredPosts.any(
                  (post) => post.comments.any(
                    (comment) => comment.body.equals('old'),
                  ),
                ),
              )
              .get(tx);
          expect(users.map((user) => user.name), ['Ada']);
          expect(users.single.authoredPosts.isLoaded, isFalse);
        });
        expect(statements, hasLength(1));
      },
      skip: databaseUrl == null ? 'RIVET_TEST_DATABASE_URL is not configured.' : false,
    );

    test(
      'should traverse self relations in both directions',
      () async {
        final manager = await RelationalUsers.db
            .find(
              where: (user) => user.reports.any(
                (report) => report.name.equals('Grace'),
              ),
            )
            .getSingle(database);
        final report = await RelationalUsers.db
            .find(
              where: (user) => user.manager.matches(
                (manager) => manager.name.equals('Ada'),
              ),
            )
            .getSingle(database);

        expect(manager.name, 'Ada');
        expect(report.name, 'Grace');
        expect(manager.reports.isLoaded, isFalse);
        expect(report.manager.isLoaded, isFalse);
        expect(statements, hasLength(2));
      },
      skip: databaseUrl == null ? 'RIVET_TEST_DATABASE_URL is not configured.' : false,
    );

    test(
      'should update and return targets selected through relations',
      () async {
        final returned = await RelationalPosts.db
            .update(
              RelationalPostsCompanion.update(
                title: const RivetValue.present('selected'),
              ),
              where: (post) => post.author.matches(
                (user) => user.name.equals('Ada'),
              ),
            )
            .returning()
            .get(database);

        expect(returned.map((post) => post.id), containsAll([11, 12, 13]));
        expect(returned.every((post) => post.title == 'selected'), isTrue);
        expect(returned.every((post) => !post.author.isLoaded), isTrue);
        expect(statements, hasLength(1));
      },
      skip: databaseUrl == null ? 'RIVET_TEST_DATABASE_URL is not configured.' : false,
    );

    test(
      'should delete targets selected by nested relations in one statement',
      () async {
        final deleted = await RelationalPosts.db
            .delete(
              where: (post) => post.comments.any(
                (comment) => comment.body.equals('old'),
              ),
            )
            .returning()
            .get(database);

        expect(deleted.map((post) => post.id), [11]);
        expect(deleted.single.comments.isLoaded, isFalse);
        expect(statements, hasLength(1));
      },
      skip: databaseUrl == null ? 'RIVET_TEST_DATABASE_URL is not configured.' : false,
    );

    test(
      'should preserve zero-match counts and transaction rollback',
      () async {
        final deleted = await RelationalPosts.db
            .delete(
              where: (post) => post.author.matches(
                (user) => user.name.equals('Missing'),
              ),
            )
            .execute(database);
        expect(deleted, 0);

        await expectLater(
          database.transaction((tx) async {
            final affected = await RelationalPosts.db
                .update(
                  RelationalPostsCompanion.update(
                    title: const RivetValue.present('rolled back'),
                  ),
                  where: (post) => post.comments.any(
                    (comment) => comment.body.equals('old'),
                  ),
                )
                .execute(tx);
            expect(affected, 1);
            throw StateError('rollback');
          }),
          throwsStateError,
        );
        final titles = await fixture.execute(
          'SELECT title FROM fbr146."relationalPosts" WHERE id = 11',
        );
        expect(titles.single.single, 'Ada first');
        expect(statements, hasLength(2));
      },
      skip: databaseUrl == null ? 'RIVET_TEST_DATABASE_URL is not configured.' : false,
    );

    test(
      'should filter and order roots by collection aggregates',
      () async {
        final prolific = await RelationalUsers.db
            .find(
              where: (user) => user.authoredPosts.count().greaterThan(1),
            )
            .getSingle(database);
        expect(prolific.name, 'Ada');

        final ordered = await RelationalUsers.db
            .find(
              orderBy: (user) => [
                user.authoredPosts.count().desc(),
                user.id.asc(),
              ],
            )
            .get(database);
        expect(ordered.map((user) => user.name), ['Ada', 'Grace', 'Linus']);

        final maximum = await RelationalUsers.db
            .find(
              where: (user) => user.authoredPosts.max((post) => post.rank).greaterThan(2),
              orderBy: (user) => [
                user.authoredPosts.min((post) => post.rank).asc(),
              ],
            )
            .get(database);
        expect(maximum.map((user) => user.name), ['Ada', 'Grace']);

        final filteredCount = await RelationalUsers.db
            .find(
              where: (user) => user.authoredPosts
                  .count(where: (post) => post.title.equals('Ada second'))
                  .equals(1),
            )
            .getSingle(database);
        expect(filteredCount.name, 'Ada');

        final fewerPostsThanId = await RelationalUsers.db
            .find(
              where: (user) => user.authoredPosts.count().lessThanExpression(user.id),
              orderBy: (user) => [user.id.asc()],
            )
            .get(database);
        expect(fewerPostsThanId.map((user) => user.name), ['Grace', 'Linus']);
        expect(ordered.every((user) => !user.authoredPosts.isLoaded), isTrue);
        expect(statements, hasLength(5));
      },
      skip: databaseUrl == null ? 'RIVET_TEST_DATABASE_URL is not configured.' : false,
    );

    test(
      'should return nullable scores with typed rows and includes',
      () async {
        final scored = await RelationalPosts.db
            .find(
              orderBy: (post) => [post.id.asc()],
              include: (include) => [include.author()],
            )
            .withScore((post) => post.quality)
            .get(database);
        expect(scored.map((result) => result.score), [1.5, null, 2.5, 4.5]);
        expect(scored.map((result) => result.row.id), [11, 12, 13, 14]);
        expect(scored.every((result) => result.row.author.isLoaded), isTrue);

        final single = await RelationalPosts.db
            .find(where: (post) => post.id.equals(11))
            .withScore((post) => post.weight)
            .getSingle(database);
        expect(single.row.id, 11);
        expect(single.score, 1.0);
        expect(single.row.author.isLoaded, isFalse);

        final bound = await RelationalPosts.db
            .find(where: (post) => post.id.equals(11))
            .withScore((post) => post.weight.value(1.5))
            .getSingle(database);
        expect(bound.score, 1.5);

        final missing = await RelationalPosts.db
            .find(where: (post) => post.id.equals(99))
            .withScore((post) => post.quality)
            .getSingleOrNull(database);
        expect(missing, isNull);

        final first = await RelationalPosts.db
            .find(orderBy: (post) => [post.id.asc()])
            .withScore((post) => post.weight)
            .getFirstOrNull(database);
        expect(first?.row.id, 11);

        await expectLater(
          RelationalPosts.db.find().withScore((post) => post.weight).getSingle(database),
          throwsA(isA<RivetCardinalityException>()),
        );

        await database.transaction((tx) async {
          final nullable = await RelationalPosts.db
              .find(where: (post) => post.id.equals(12))
              .withScore((post) => post.quality)
              .getSingle(tx);
          expect(nullable.score, isNull);
        });
        expect(statements, hasLength(7));
      },
      skip: databaseUrl == null ? 'RIVET_TEST_DATABASE_URL is not configured.' : false,
    );
  });
}
