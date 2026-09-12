import 'package:rivet/rivet.dart';
import 'package:test/test.dart';

import 'generated_consumer.dart';

void main() {
  group('Rivet insert', () {
    late _RecordingExecutor executor;

    setUp(() {
      executor = _RecordingExecutor(affectedRows: 1);
      mutationDefaultCalls = 0;
      mutationUpdateCalls = 0;
      mutationNullableCalls = 0;
    });

    test('should resolve defaults only when each execution begins', () async {
      final insert = MutationUsers.db.insert(
        MutationUsersCompanion.insert(
          id: const RivetValue.present(1),
          name: const RivetValue.present('Ada'),
        ),
      );
      final prepared = insert.prepare();

      expect(mutationDefaultCalls, 0);
      expect(mutationUpdateCalls, 0);
      expect(mutationNullableCalls, 0);

      expect(await prepared.execute(executor), 1);
      expect(await prepared.execute(executor), 1);

      expect(mutationDefaultCalls, 2);
      expect(mutationUpdateCalls, 2);
      expect(mutationNullableCalls, 2);
      expect(executor.queries, hasLength(2));
      expect(executor.queries.first.sql, contains('INSERT INTO "fbr138"."mutationUsers"'));
      expect(executor.queries.first.sql, contains('NULL'));
      expect(executor.queries.first.sql, contains('DEFAULT'));
      expect(executor.queries.first.sql, isNot(contains('RETURNING')));
      expect(executor.queries.first.parameters.take(2), [1, 'Ada']);
      expect(executor.queries.first.parameters[2], DateTime.utc(2026, 9, 12, 10, 11, 1));
      expect(executor.queries.first.parameters[3], DateTime.utc(2026, 9, 12, 11, 12, 1));
      expect(executor.queries.first.parameters[4], isNull);
    });

    test('should preserve explicit values and expressions over hooks', () async {
      final created = DateTime.utc(2026, 1, 2);
      final updated = DateTime.utc(2026, 2, 3);
      await MutationUsers.db
          .insert(
            MutationUsersCompanion.insert(
              id: RivetValue.expression((users) => users.id.value(0) + 1),
              name: const RivetValue.present('Ada'),
              nickname: const RivetValue.present(null),
              createdAt: RivetValue.present(created),
              updatedAt: RivetValue.present(updated),
              nullableDefault: const RivetValue.present(null),
            ),
          )
          .execute(executor);

      expect(mutationDefaultCalls, 0);
      expect(mutationUpdateCalls, 0);
      expect(mutationNullableCalls, 0);
      expect(executor.queries.single.sql, contains(r'($1::int4 + $2::int4)'));
      expect(executor.queries.single.parameters, [0, 1, 'Ada', null, created, updated, null]);
    });

    test('should reject an explicitly absent required field before execution', () async {
      final insert = MutationUsers.db.insert(
        MutationUsersCompanion.insert(
          id: const RivetValue.absent(),
          name: const RivetValue.present('Ada'),
        ),
      );

      expect(
        () => insert.execute(executor),
        throwsA(
          isA<RivetMissingValueException>()
              .having((error) => error.table, 'table', 'fbr138.mutationUsers')
              .having((error) => error.column, 'column', 'id'),
        ),
      );
      expect(executor.queries, isEmpty);
    });

    test('should reject expression columns from another target table', () async {
      final other = ScalarValues.db.buildSchema().definition;
      final insert = MutationUsers.db.insert(
        MutationUsersCompanion.insert(
          id: RivetValue.expression((_) => other.count + 1),
          name: const RivetValue.present('Ada'),
        ),
      );

      expect(
        () => insert.execute(executor),
        throwsA(isA<RivetUnsupportedQueryException>()),
      );
      expect(executor.queries, isEmpty);
    });

    test('should decode complete rows from INSERT RETURNING', () async {
      final created = DateTime.utc(2026, 9, 12, 10);
      final updated = DateTime.utc(2026, 9, 12, 11);
      executor.rows = [
        (
          [1, 'Ada', null, created, updated, null, 42],
          [false, false, true, false, false, true, false],
        ),
      ];

      final rows = await MutationUsers.db
          .insert(
            MutationUsersCompanion.insert(
              id: const RivetValue.present(1),
              name: const RivetValue.present('Ada'),
            ),
          )
          .returning()
          .get(executor);

      expect(rows.single.id, 1);
      expect(rows.single.name, 'Ada');
      expect(rows.single.nickname, isNull);
      expect(rows.single.createdAt, created);
      expect(rows.single.updatedAt, updated);
      expect(rows.single.nullableDefault, isNull);
      expect(rows.single.serverValue, 42);
      expect(executor.queries.single.sql, contains(' RETURNING '));
    });
  });
}

final class _RecordingExecutor implements RivetExecutor {
  _RecordingExecutor({required this.affectedRows});

  final int affectedRows;
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
    return affectedRows;
  }
}
