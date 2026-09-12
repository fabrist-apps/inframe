import 'package:rivet/rivet.dart';
import 'package:test/test.dart';

import 'generated_consumer.dart';

void main() {
  group('Rivet insertMany', () {
    late _RecordingExecutor executor;

    setUp(() {
      executor = _RecordingExecutor(affectedRows: 2);
      mutationDefaultCalls = 0;
      mutationUpdateCalls = 0;
      mutationNullableCalls = 0;
    });

    test('should short-circuit both empty terminals without callbacks or SQL', () async {
      final insert = MutationUsers.db.insertMany([]).prepare();

      expect(await insert.execute(executor), 0);
      expect(await insert.returning().get(executor), isEmpty);
      expect(mutationDefaultCalls, 0);
      expect(mutationUpdateCalls, 0);
      expect(mutationNullableCalls, 0);
      expect(executor.queries, isEmpty);
    });

    test('should resolve mixed row values and hooks independently', () async {
      final explicitCreated = DateTime.utc(2026, 1, 2);
      final explicitUpdated = DateTime.utc(2026, 2, 3);
      final companions = [
        MutationUsersCompanion.insert(
          id: const RivetValue.present(1),
          name: const RivetValue.present('Ada'),
        ),
        MutationUsersCompanion.insert(
          id: const RivetValue.present(2),
          name: const RivetValue.present('Grace'),
          nickname: const RivetValue.present('G'),
          createdAt: RivetValue.present(explicitCreated),
          updatedAt: RivetValue.present(explicitUpdated),
          nullableDefault: const RivetValue.present(null),
          serverValue: const RivetValue.present(7),
        ),
      ];
      final plan = MutationUsers.db.insertMany(companions);
      companions.clear();

      expect(await plan.execute(executor), 2);
      expect(mutationDefaultCalls, 1);
      expect(mutationUpdateCalls, 1);
      expect(mutationNullableCalls, 1);
      final query = executor.queries.single;
      expect(query.sql, contains('VALUES ('));
      expect(query.sql, contains('), ('));
      expect(query.sql, isNot(contains('RETURNING')));
      expect(query.parameters, containsAllInOrder([1, 'Ada']));
      expect(query.parameters, containsAllInOrder([2, 'Grace', 'G']));
      expect(query.parameters, containsAllInOrder([explicitCreated, explicitUpdated, null, 7]));
    });

    test('should decode complete rows from one INSERT RETURNING', () async {
      final timestamp = DateTime.utc(2026);
      executor.rows = [
        (
          [1, 'Ada', null, timestamp, timestamp, null, 42],
          [false, false, true, false, false, true, false],
        ),
        (
          [2, 'Grace', null, timestamp, timestamp, null, 42],
          [false, false, true, false, false, true, false],
        ),
      ];

      final rows = await MutationUsers.db
          .insertMany([
            MutationUsersCompanion.insert(
              id: const RivetValue.present(1),
              name: const RivetValue.present('Ada'),
            ),
            MutationUsersCompanion.insert(
              id: const RivetValue.present(2),
              name: const RivetValue.present('Grace'),
            ),
          ])
          .returning()
          .get(executor);

      expect(rows.map((row) => row.name), ['Ada', 'Grace']);
      expect(executor.queries.single.sql, contains(' RETURNING '));
      expect(mutationDefaultCalls, 2);
      expect(mutationUpdateCalls, 2);
      expect(mutationNullableCalls, 2);
    });

    test('should reject PostgreSQL parameter overflow before execution', () {
      final companions = List.generate(
        65536,
        (index) => ParameterNamesCompanion.insert(
          value: RivetValue.present('$index'),
        ),
        growable: false,
      );

      expect(
        () => ParameterNames.db.insertMany(companions).execute(executor),
        throwsA(isA<RivetUnsupportedQueryException>()),
      );
      expect(executor.queries, isEmpty);
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
