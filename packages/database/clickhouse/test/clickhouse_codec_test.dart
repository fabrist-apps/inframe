import 'dart:convert';

import 'package:clickhouse/src/insert.dart';
import 'package:clickhouse/src/query_result.dart';
import 'package:clickhouse/src/response.dart';
import 'package:test/test.dart';

void main() {
  group('ClickHouseResponse', () {
    test('should preserve error-like text inside a valid query result', () {
      final response = ClickHouseResponse(
        statusCode: 200,
        body: utf8.encode(
          '{"meta":[{"name":"message","type":"String"}],'
          '"data":[{"message":"Code: 241. ordinary row data"}],"rows":1}',
        ),
      );

      expect(response.decodeQuery().rows.single['message'], 'Code: 241. ordinary row data');
    });
  });

  group('JSONEachRow encoding', () {
    test('should reject custom toJson objects without invoking them', () {
      final customValue = _CustomJson();

      expect(
        () => encodeRows([
          {'valid': true},
          {'custom': customValue},
        ]),
        throwsArgumentError,
      );
      expect(customValue.calls, 0);
    });

    test('should reject non-finite numbers and non-list iterables', () {
      for (final value in <Object?>[
        double.nan,
        double.infinity,
        <int>{1, 2},
      ]) {
        expect(
          () => encodeRows([
            {'value': value},
          ]),
          throwsArgumentError,
        );
      }
    });
  });

  group('ClickHouseQueryResult', () {
    test('should snapshot nested iterables as immutable lists', () {
      final values = <int>{1, 2};
      final result = ClickHouseQueryResult(
        columns: const [ClickHouseColumn(name: 'values', type: 'Array(Int32)')],
        rows: [
          {'values': values},
        ],
      );
      values.add(3);

      final snapshot = result.rows.single['values']! as List<Object?>;
      expect(snapshot, [1, 2]);
      expect(() => snapshot.add(4), throwsUnsupportedError);
    });
  });
}

final class _CustomJson {
  int calls = 0;

  Map<String, Object?> toJson() {
    calls += 1;
    return {'converted': true};
  }
}
