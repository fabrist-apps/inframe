import 'package:rivet/rivet.dart';
import 'package:test/test.dart';

import 'generated_consumer.dart';

void main() {
  group('RivetFind', () {
    late _RecordingExecutor executor;

    setUp(() => executor = _RecordingExecutor());

    test('should compile bound filters and nulls-last ordering', () async {
      executor.rows = [
        (['Ada'], [false]),
      ];
      final row = await UserProfiles.db
          .find(
            where: (users) => users.displayName.equals('Ada'),
            orderBy: (users) => [users.displayName.desc()],
          )
          .getFirstOrNull(executor);

      expect(row?.displayName, 'Ada');
      expect(executor.queries.single.sql, contains('ORDER BY "displayName" DESC NULLS LAST'));
      expect(executor.queries.single.sql, endsWith('LIMIT 1'));
      expect(executor.queries.single.parameters, ['Ada']);
      expect(executor.queries.single.sql, contains(r'"displayName" = $1::text'));
    });

    test('should honor explicit null placement', () async {
      await UserProfiles.db
          .find(orderBy: (users) => [users.displayName.asc(nulls: NullsOrder.first)])
          .get(executor);

      expect(executor.queries.single.sql, contains('ASC NULLS FIRST'));
    });

    test('should compile nullable equality and reject columns from another root', () async {
      await ScalarValues.db.find(where: (values) => values.optionalCode.equals(null)).get(executor);
      expect(executor.queries.single.sql, contains('"optionalCode" IS NULL'));
      expect(executor.queries.single.parameters, isEmpty);

      final other = Posts.db.buildSchema().definition;
      expect(
        () => UserProfiles.db.find(where: (_) => other.authorName.equals('Ada')),
        throwsA(isA<RivetUnsupportedQueryException>()),
      );
      expect(
        () => UserProfiles.db.find(orderBy: (_) => [other.authorName.asc()]),
        throwsA(isA<RivetUnsupportedQueryException>()),
      );
    });

    test('should enforce exact and optional-single cardinality in one statement', () async {
      executor.rows = [
        (['Ada'], [false]),
        (['Grace'], [false]),
      ];
      final plan = UserProfiles.db.find();

      await expectLater(plan.getSingle(executor), throwsA(isA<RivetCardinalityException>()));
      await expectLater(plan.getSingleOrNull(executor), throwsA(isA<RivetCardinalityException>()));

      expect(executor.queries, hasLength(2));
      expect(executor.queries.every((query) => query.sql.endsWith('LIMIT 2')), isTrue);
    });

    test('should reject PostgreSQL parameter overflow before execution', () {
      RivetPredicate overflow(UserProfiles users) {
        var level = List<RivetPredicate>.generate(
          65536,
          (index) => users.displayName.equals('$index'),
          growable: false,
        );
        while (level.length > 1) {
          level = [
            for (var index = 0; index < level.length; index += 2)
              if (index + 1 == level.length) level[index] else level[index] | level[index + 1],
          ];
        }
        return level.single;
      }

      expect(
        () => UserProfiles.db.find(where: overflow).get(executor),
        throwsA(isA<RivetUnsupportedQueryException>()),
      );
      expect(executor.queries, isEmpty);
    });

    test('should not rewrite placeholder text inside quoted identifiers', () async {
      await ParameterNames.db
          .find(
            where: (values) => values.value.equals('Ada') | ~values.value.equals('Grace'),
          )
          .get(executor);

      expect(
        executor.queries.single.sql,
        contains(r'("a@value" = $1::text) OR (NOT ("a@value" = $2::text))'),
      );
      expect(executor.queries.single.parameters, ['Ada', 'Grace']);
    });

    test('should decode transport values for generated tables without relations', () {
      final row = MalformedArrays.db.buildSchema().decodeRow(
        [
          {
            'dimensions': 1,
            'lower': 1,
            'upper': 2,
            'elements': [
              [false, 1],
              [false, 2],
            ],
          },
        ],
        [false],
        transport: true,
      );

      expect(row.ints, [1, 2]);
    });

    test('should offset root predicate parameters after a bound score', () async {
      await RelationalPosts.db
          .find(where: (post) => post.id.equals(11))
          .withScore((post) => post.weight.value(1.5))
          .get(executor);

      expect(executor.queries.single.parameters, [1.5, 11]);
      expect(executor.queries.single.sql, contains(r'$1::float8 AS "__rivet_score"'));
      expect(executor.queries.single.sql, contains(r'"id" = $2::int4'));
    });

    test('should compare a relation aggregate with a root column', () async {
      await RelationalUsers.db
          .find(
            where: (user) => user.authoredPosts.count().lessThanExpression(user.id),
          )
          .get(executor);

      expect(executor.queries.single.parameters, isEmpty);
      expect(executor.queries.single.sql, contains('SELECT count(*)'));
      expect(executor.queries.single.sql, contains('< "__rivet_t0"."id"'));
    });

    test('should load one relation and preserve missing and duplicate cardinality', () async {
      executor.rows = [
        (
          [
            'Ada',
            {
              'count': 1,
              'rows': [
                [
                  [false, 'Ada'],
                ],
              ],
            },
          ],
          [false, false],
        ),
      ];

      final row = await Posts.db.find(include: (include) => [include.author()]).getSingle(executor);

      expect((row.author as LoadedRelation<UserProfilesRow?>).value?.displayName, 'Ada');
      expect(executor.queries.single.sql, contains('jsonb_build_object'));
      expect(executor.queries.single.sql, contains('LIMIT 2'));

      executor.rows = [
        (
          [
            'Missing',
            {'count': 0, 'rows': <Object?>[]},
          ],
          [false, false],
        ),
      ];
      final missing = await Posts.db
          .find(include: (include) => [include.author()])
          .getSingle(executor);
      expect((missing.author as LoadedRelation<UserProfilesRow?>).value, isNull);

      executor.rows = [
        (
          [
            'Ada',
            {
              'count': 2,
              'rows': [
                [
                  [false, 'Ada'],
                ],
                [
                  [false, 'Ada'],
                ],
              ],
            },
          ],
          [false, false],
        ),
      ];
      await expectLater(
        Posts.db.find(include: (include) => [include.author()]).get(executor),
        throwsA(
          isA<RivetCardinalityException>().having(
            (error) => error.relationPath,
            'relationPath',
            'author',
          ),
        ),
      );
    });

    test('should reject duplicate one includes before execution', () {
      expect(
        () => Posts.db.find(
          include: (include) => [include.author(), include.author()],
        ),
        throwsA(
          isA<RivetUnsupportedQueryException>().having(
            (error) => error.message,
            'message',
            contains('author'),
          ),
        ),
      );
      expect(executor.queries, isEmpty);
    });
  });
}

final class _RecordingExecutor implements RivetExecutor {
  List<(List<Object?>, List<bool>)> rows = [];
  final queries = <RivetCompiledQuery>[];

  @override
  Future<List<Row>> execute<Row>(
    RivetCompiledQuery query,
    RivetRowDecoder<Row> decode,
  ) async {
    queries.add(query);
    return [for (final row in rows) decode(row.$1, row.$2)];
  }

  @override
  Future<int> executeAffected(RivetCompiledQuery query) async {
    queries.add(query);
    return rows.length;
  }
}
