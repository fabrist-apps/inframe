import 'package:rivet/rivet.dart';
import 'package:test/test.dart';

import 'generated_consumer.dart';

void main() {
  group('Rivet delete', () {
    late _RecordingExecutor executor;

    setUp(() => executor = _RecordingExecutor(affectedRows: 1));

    test('should compile quoted targets and bound predicates', () async {
      final delete = MutationDeleteParents.db
          .delete(where: (parents) => parents.label.equals("O'Reilly"))
          .prepare();

      expect(await delete.execute(executor), 1);
      expect(
        executor.queries.single.sql,
        r'DELETE FROM "fbr141"."delete Parents" WHERE "display Name" = $1::text',
      );
      expect(executor.queries.single.parameters, ["O'Reilly"]);
    });

    test('should omit the predicate for an all-row delete', () async {
      await MutationDeleteParents.db.delete().execute(executor);

      expect(
        executor.queries.single.sql,
        'DELETE FROM "fbr141"."delete Parents"',
      );
      expect(executor.queries.single.parameters, isEmpty);
    });

    test('should decode complete rows from DELETE RETURNING', () async {
      executor.rows = [
        (
          [1, 'Ada'],
          [false, false],
        ),
      ];

      final rows = await MutationDeleteParents.db
          .delete(where: (parents) => parents.id.equals(1))
          .returning()
          .get(executor);

      expect(rows.single.id, 1);
      expect(rows.single.label, 'Ada');
      expect(rows.single.cascadeChildren.isLoaded, isFalse);
      expect(rows.single.restrictChildren.isLoaded, isFalse);
      expect(executor.queries.single.sql, contains(' RETURNING '));
    });

    test('should reject a predicate from another target table', () {
      final other = MutationUsers.db.buildSchema().definition;

      expect(
        () => MutationDeleteParents.db.delete(where: (_) => other.id.equals(1)),
        throwsA(isA<RivetUnsupportedQueryException>()),
      );
      expect(executor.queries, isEmpty);
    });

    test('should clear relation aliases after compilation', () async {
      late MutationDeleteParents definition;

      await MutationDeleteParents.db
          .delete(
            where: (parents) {
              definition = parents;
              return parents.cascadeChildren.any((child) => child.id.equals(1));
            },
          )
          .execute(executor);

      expect(definition.id.qualifier, isNull);
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
