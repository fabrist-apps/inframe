import 'package:rivet/rivet.dart';
import 'package:test/test.dart';

import 'generated_consumer.dart';

void main() {
  group('Rivet doNothing conflicts', () {
    late _RecordingExecutor executor;
    var conflictCalls = 0;

    setUp(() {
      executor = _RecordingExecutor();
      conflictCalls = 0;
      conflictDefaultCalls = 0;
      conflictUpdateCalls = 0;
    });

    test('should compile targetless, targeted, and literal partial targets', () async {
      await MutationConflictParents.db
          .insert(
            _parent(1),
            onConflict: (conflict) => conflict.doNothing(),
          )
          .execute(executor);
      await MutationConflictParents.db
          .insert(
            _parent(2),
            onConflict: (conflict) => conflict.doNothing(
              target: (parents) => [parents.email],
            ),
          )
          .execute(executor);
      await MutationConflictParents.db
          .insert(
            _parent(3),
            onConflict: (conflict) => conflict.doNothing(
              target: (parents) => [parents.email],
              targetWhere: (parents) =>
                  parents.active.equals(true) & parents.name.equals("O'Reilly"),
            ),
          )
          .returning()
          .get(executor);

      expect(executor.queries[0].sql, contains(' ON CONFLICT DO NOTHING'));
      expect(executor.queries[1].sql, contains(' ON CONFLICT ("email") DO NOTHING'));
      expect(
        executor.queries[2].sql,
        contains(
          'ON CONFLICT ("email") WHERE '
          '("active" = TRUE::bool) AND ("name" = \'O\'\'Reilly\'::text) '
          'DO NOTHING RETURNING',
        ),
      );
      expect(executor.queries[2].parameters, isNot(contains("O'Reilly")));
    });

    test('should invoke conflicts and insert defaults only at nonempty execution', () async {
      final insert = MutationConflictParents.db
          .insert(
            _parent(1),
            onConflict: (conflict) {
              conflictCalls++;
              return conflict.doNothing();
            },
          )
          .prepare();
      final empty = MutationConflictParents.db
          .insertMany(
            [],
            onConflict: (conflict) {
              conflictCalls++;
              return conflict.doNothing();
            },
          )
          .prepare();

      expect(conflictCalls, 0);
      expect(conflictDefaultCalls, 0);
      expect(await empty.execute(executor), 0);
      expect(await empty.returning().get(executor), isEmpty);
      expect(conflictCalls, 0);
      expect(conflictDefaultCalls, 0);
      expect(await insert.execute(executor), 1);
      expect(await insert.execute(executor), 1);
      expect(conflictCalls, 2);
      expect(conflictDefaultCalls, 2);
      expect(conflictUpdateCalls, 0);
      expect(executor.queries, hasLength(2));
    });

    test('should reject invalid targets before executor access', () {
      final other = MutationUpdateUsers.db.buildSchema().definition;
      final invalidPlans = [
        MutationConflictParents.db.insert(
          _parent(1),
          onConflict: (conflict) => conflict.doNothing(
            targetWhere: (parents) => parents.active.equals(true),
          ),
        ),
        MutationConflictParents.db.insert(
          _parent(2),
          onConflict: (conflict) => conflict.doNothing(target: (_) => []),
        ),
        MutationConflictParents.db.insert(
          _parent(3),
          onConflict: (conflict) => conflict.doNothing(
            target: (_) => [other.id],
          ),
        ),
        MutationConflictParents.db.insert(
          _parent(4),
          onConflict: (conflict) => conflict.doNothing(
            target: (parents) => [parents.id],
            targetWhere: (_) => other.id.equals(1),
          ),
        ),
      ];

      for (final plan in invalidPlans) {
        expect(
          () => plan.execute(executor),
          throwsA(isA<RivetUnsupportedQueryException>()),
        );
      }
      expect(executor.queries, isEmpty);
    });

    test('should preserve JSON values in partial-index literals', () {
      final table = MutationCatalog.db.buildSchema().definition;

      expect(
        table.payload.equals(JsonValue.from('active')).renderLiterals(),
        '"payload" = \'"active"\'::jsonb',
      );
      expect(
        table.payload.equals(const JsonNull()).renderLiterals(),
        '"payload" = \'null\'::jsonb',
      );
      expect(
        table.jsonValues.equals(const [JsonNull(), null]).renderLiterals(),
        '"jsonValues" = ARRAY[\'null\'::jsonb, NULL]::jsonb[]',
      );
      expect(
        table.score.equals(double.infinity).renderLiterals(),
        '"score" = \'Infinity\'::float8',
      );
    });
  });
}

MutationConflictParentsCompanion _parent(int id) => MutationConflictParentsCompanion.insert(
  id: RivetValue.present(id),
  email: RivetValue.present('user$id@example.com'),
  username: RivetValue.present('user$id'),
  active: const RivetValue.present(true),
  name: RivetValue.present('User $id'),
  age: const RivetValue.present(30),
  requiredByDatabase: const RivetValue.present('required'),
);

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
