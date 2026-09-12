import 'package:rivet/rivet.dart';
import 'package:test/test.dart';

import 'generated_consumer.dart';

void main() {
  group('Rivet update', () {
    late _RecordingExecutor executor;

    setUp(() {
      executor = _RecordingExecutor(affectedRows: 2);
      updateTimestampCalls = 0;
      updateNullableCalls = 0;
      updateCodeCalls = 0;
      updateDefaultOnlyCalls = 0;
      mutationCodeEncodeCalls = 0;
    });

    test('should apply update hooks once when each execution begins', () async {
      final update = MutationUpdateUsers.db.update(
        MutationUpdateUsersCompanion.update(),
        where: (users) => users.id.equals(99),
      );
      final prepared = update.prepare();

      expect(updateTimestampCalls, 0);
      expect(updateNullableCalls, 0);
      expect(updateCodeCalls, 0);
      expect(await prepared.execute(executor), 2);
      expect(await prepared.execute(executor), 2);

      expect(updateTimestampCalls, 2);
      expect(updateNullableCalls, 2);
      expect(updateCodeCalls, 2);
      expect(updateDefaultOnlyCalls, 0);
      expect(mutationCodeEncodeCalls, 2);
      expect(executor.queries, hasLength(2));
      expect(
        executor.queries.first.sql,
        contains(
          r'SET "updatedAt" = $1::timestamptz, '
          r'"nullableNote" = $2::text, "code" = $3::text WHERE "id" = $4::int4',
        ),
      );
      expect(executor.queries.first.parameters[1], isNull);
      expect(executor.queries.first.parameters[2], 'code:hook-1');
      expect(executor.queries.first.parameters[3], 99);
      expect(executor.queries.last.parameters[2], 'code:hook-2');
    });

    test('should suppress hooks with values, nulls, and row expressions', () async {
      final explicitTime = DateTime.utc(2026, 1, 2);
      await MutationUpdateUsers.db
          .update(
            MutationUpdateUsersCompanion.update(
              age: RivetValue.expression((users) => users.age + 1),
              updatedAt: RivetValue.present(explicitTime),
              nullableNote: const RivetValue.present(null),
              code: RivetValue.expression(
                (users) => users.code.storage.value('code:expression'),
              ),
            ),
          )
          .execute(executor);

      expect(updateTimestampCalls, 0);
      expect(updateNullableCalls, 0);
      expect(updateCodeCalls, 0);
      expect(updateDefaultOnlyCalls, 0);
      expect(mutationCodeEncodeCalls, 0);
      expect(executor.queries.single.sql, contains(r'"age" = ("age" + $1::int4)'));
      expect(executor.queries.single.sql, isNot(contains('"defaultOnly" =')));
      expect(executor.queries.single.sql, isNot(contains('"serverOnly" =')));
      expect(executor.queries.single.parameters, [1, explicitTime, null, 'code:expression']);
    });

    test('should reject an empty update before SQL execution', () async {
      final update = MutationUpdateChildren.db.update(
        MutationUpdateChildrenCompanion.update(),
      );

      expect(
        () => update.execute(executor),
        throwsA(isA<RivetEmptyUpdateException>()),
      );
      expect(executor.queries, isEmpty);
    });

    test('should reject predicates and expressions from another table', () async {
      final other = MutationUsers.db.buildSchema().definition;

      expect(
        () => MutationUpdateUsers.db.update(
          MutationUpdateUsersCompanion.update(name: const RivetValue.present('Ada')),
          where: (_) => other.id.equals(1),
        ),
        throwsA(isA<RivetUnsupportedQueryException>()),
      );
      expect(
        () => MutationUpdateUsers.db
            .update(
              MutationUpdateUsersCompanion.update(
                age: RivetValue.expression((_) => other.id + 1),
              ),
            )
            .execute(executor),
        throwsA(isA<RivetUnsupportedQueryException>()),
      );
      expect(executor.queries, isEmpty);
    });
  });
}

final class _RecordingExecutor implements RivetExecutor {
  _RecordingExecutor({required this.affectedRows});

  final int affectedRows;
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
    return affectedRows;
  }
}
