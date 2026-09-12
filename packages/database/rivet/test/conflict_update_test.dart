import 'package:rivet/rivet.dart';
import 'package:test/test.dart';

import 'generated_consumer.dart';

void main() {
  group('Rivet conflict updates', () {
    late _RecordingExecutor executor;

    setUp(() {
      executor = _RecordingExecutor();
      _resetHooks();
    });

    test('should compile distinct target and action predicates with row scopes', () async {
      await MutationUpsertUsers.db
          .insert(
            _user(1, name: 'shared', age: 31),
            onConflict: (conflict) => conflict.update(
              target: (user) => [user.name],
              targetWhere: (user) => ~user.name.equals(''),
              set: (old, excluded) => MutationUpsertUsersCompanion.update(
                age: RivetValue.expression((_) => excluded.age),
                active: RivetValue.expression((_) => old.active),
                // Explicit absence follows the same update-hook path as omission.
                // ignore: avoid_redundant_argument_values
                updatedAt: const RivetValue.absent(),
                note: const RivetValue.present(null),
                code: RivetValue.expression((_) => excluded.code.storage),
              ),
              where: (old, excluded) => old.age.lessThanExpression(excluded.age),
            ),
          )
          .returning()
          .get(executor);

      final query = executor.queries.single;
      expect(
        query.sql,
        contains(
          'ON CONFLICT ("name") WHERE NOT ("name" = \'\'::text) '
          'DO UPDATE SET "age" = "excluded"."age", '
          '"active" = "mutationUpsertUsers"."active"',
        ),
      );
      expect(query.sql, contains(r'"note" = $'));
      expect(query.sql, contains('"code" = "excluded"."code"'));
      expect(
        query.sql,
        contains(
          'WHERE "mutationUpsertUsers"."age" < "excluded"."age" RETURNING',
        ),
      );
      expect(upsertTimestampUpdateCalls, 1);
      expect(upsertNoteUpdateCalls, 0);
      expect(upsertCodeUpdateCalls, 0);
    });

    test('should defer and reevaluate set callbacks and hooks per execution', () async {
      var conflictCalls = 0;
      var setCalls = 0;
      final plan = MutationUpsertUsers.db
          .insert(
            _user(1),
            onConflict: (conflict) {
              conflictCalls++;
              return conflict.update(
                target: (user) => [user.email],
                set: (old, excluded) {
                  setCalls++;
                  return MutationUpsertUsersCompanion.update(
                    age: RivetValue.expression((_) => excluded.age + setCalls),
                  );
                },
              );
            },
          )
          .prepare();

      expect(conflictCalls, 0);
      expect(setCalls, 0);
      expect(upsertTimestampDefaultCalls, 0);
      expect(upsertTimestampUpdateCalls, 0);

      await plan.execute(executor);
      await plan.execute(executor);

      expect(conflictCalls, 2);
      expect(setCalls, 2);
      expect(upsertTimestampDefaultCalls, 2);
      expect(upsertNoteDefaultCalls, 2);
      expect(upsertCodeDefaultCalls, 2);
      expect(upsertTimestampUpdateCalls, 2);
      expect(upsertNoteUpdateCalls, 2);
      expect(upsertCodeUpdateCalls, 2);
      expect(executor.queries[0].parameters, isNot(executor.queries[1].parameters));
    });

    test('should not run callbacks for an empty batch', () async {
      var conflictCalls = 0;
      var setCalls = 0;
      final plan = MutationUpsertUsers.db.insertMany(
        [],
        onConflict: (conflict) {
          conflictCalls++;
          return conflict.update(
            target: (user) => [user.email],
            set: (_, _) {
              setCalls++;
              return MutationUpsertUsersCompanion.update();
            },
          );
        },
      );

      expect(await plan.execute(executor), 0);
      expect(await plan.returning().get(executor), isEmpty);
      expect(conflictCalls, 0);
      expect(setCalls, 0);
      expect(upsertTimestampDefaultCalls, 0);
      expect(upsertTimestampUpdateCalls, 0);
      expect(executor.queries, isEmpty);
    });

    test('should reject an update with no set assignments or hooks', () {
      final plan = MutationConflictGroups.db.insert(
        MutationConflictGroupsCompanion.insert(id: const RivetValue.present(1)),
        onConflict: (conflict) => conflict.update(
          target: (group) => [group.id],
          set: (_, _) => MutationConflictGroupsCompanion.update(),
        ),
      );

      expect(
        () => plan.execute(executor),
        throwsA(isA<RivetEmptyUpdateException>()),
      );
      expect(executor.queries, isEmpty);
    });

    test('should reject columns outside the target table', () {
      final other = MutationConflictGroups.db.buildSchema().definition;
      final plans = [
        MutationUpsertUsers.db.insert(
          _user(1),
          onConflict: (conflict) => conflict.update(
            target: (_) => [other.id],
            set: (_, _) => MutationUpsertUsersCompanion.update(),
          ),
        ),
        MutationUpsertUsers.db.insert(
          _user(2),
          onConflict: (conflict) => conflict.update(
            target: (user) => [user.id],
            set: (_, _) => MutationUpsertUsersCompanion.update(),
            where: (_, _) => other.id.equals(1),
          ),
        ),
      ];

      for (final plan in plans) {
        expect(
          () => plan.execute(executor),
          throwsA(isA<RivetUnsupportedQueryException>()),
        );
      }
      expect(executor.queries, isEmpty);
    });
  });
}

MutationUpsertUsersCompanion _user(
  int id, {
  String? email,
  String name = 'user',
  int age = 30,
  bool active = true,
  RivetValue<MutationUpsertUsers, int?, int?> conditionValue = const RivetValue.absent(),
}) => MutationUpsertUsersCompanion.insert(
  id: RivetValue.present(id),
  email: RivetValue.present(email ?? 'user$id@example.com'),
  name: RivetValue.present(name),
  age: RivetValue.present(age),
  active: RivetValue.present(active),
  conditionValue: conditionValue,
);

void _resetHooks() {
  upsertTimestampDefaultCalls = 0;
  upsertTimestampUpdateCalls = 0;
  upsertNoteDefaultCalls = 0;
  upsertNoteUpdateCalls = 0;
  upsertCodeDefaultCalls = 0;
  upsertCodeUpdateCalls = 0;
}

final class _RecordingExecutor implements RivetExecutor {
  final queries = <RivetCompiledQuery>[];

  @override
  Future<List<Row>> execute<Row>(
    RivetCompiledQuery query,
    RivetRowDecoder<Row> decode,
  ) async {
    queries.add(query);
    return [];
  }

  @override
  Future<int> executeAffected(RivetCompiledQuery query) async {
    queries.add(query);
    return 1;
  }
}
