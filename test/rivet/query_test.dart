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
    });

    test('should honor explicit null placement', () async {
      await UserProfiles.db
          .find(orderBy: (users) => [users.displayName.asc(nulls: NullsOrder.first)])
          .get(executor);

      expect(executor.queries.single.sql, contains('ASC NULLS FIRST'));
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
}
