import 'dart:io';

import 'package:clickhouse/clickhouse.dart';
import 'package:test/test.dart';

void main() {
  final endpoint = Platform.environment['CLICKHOUSE_URL'];
  final password = Platform.environment['CLICKHOUSE_PASSWORD'];

  group(
    'ClickHouseClient integration',
    () {
      late ClickHouseClient client;

      setUp(() {
        client = ClickHouseClient(
          endpoint: endpoint!,
          database: 'default',
          username: 'default',
          password: password!,
        );
      });

      tearDown(() => client.close());

      test('should bind textual parameters without changing SQL structure', () async {
        final result = await client.query(
          '''
          SELECT
            {text:String} AS text,
            {number:UInt32} AS number,
            {values:Array(String)} AS values
          ''',
          parameters: {
            'text': "quote ' tab\t line\n slash\\ தமிழ்",
            'number': '42',
            'values': "['first', 'second']",
          },
        );

        expect(result.rows.single, {
          'text': "quote ' tab\t line\n slash\\ தமிழ்",
          'number': 42,
          'values': ['first', 'second'],
        });
      });

      test('should make the JSON header override an SQL format clause', () async {
        final result = await client.query("SELECT 'value' AS value FORMAT TabSeparated");

        expect(result.columns.single.type, 'String');
        expect(result.rows.single['value'], 'value');
      });

      test('should preserve exact values selected as strings', () async {
        final result = await client.query('''
          SELECT
            toString(toUInt128('340282366920938463463374607431768211455')) AS integer,
            CAST('1.230000000000000000' AS String) AS decimal
        ''');

        expect(result.rows.single, {
          'integer': '340282366920938463463374607431768211455',
          'decimal': '1.230000000000000000',
        });
      });
    },
    skip: endpoint == null || password == null
        ? 'Set CLICKHOUSE_URL and CLICKHOUSE_PASSWORD.'
        : false,
  );
}
