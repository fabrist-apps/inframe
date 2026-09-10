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

      test('should create, insert, query, and deduplicate a batch', () async {
        final table = 'fbr1.events`archive\\${DateTime.now().microsecondsSinceEpoch}';
        final quotedTable = quoteIdentifier(table);
        await client.command('''
          CREATE TABLE $quotedTable (
            id UInt64,
            name String
          )
          ENGINE = MergeTree
          ORDER BY id
          SETTINGS non_replicated_deduplication_window = 100
        ''');

        try {
          final rows = [
            <String, Object?>{'id': 1, 'name': 'first'},
            <String, Object?>{'id': 2, 'name': 'second'},
          ];
          await client.insert(table: table, rows: rows, deduplicationToken: 'stable-batch');
          await client.insert(table: table, rows: rows, deduplicationToken: 'stable-batch');

          final result = await client.query('SELECT id, name FROM $quotedTable ORDER BY id');
          expect(result.rows, rows);
        } finally {
          await client.command('DROP TABLE $quotedTable');
        }
      });

      test('should expose command rejection from ClickHouse', () async {
        await expectLater(
          client.command('THIS IS NOT SQL'),
          throwsA(
            isA<ClickHouseServerException>()
                .having((error) => error.statusCode, 'statusCode', HttpStatus.badRequest)
                .having((error) => error.clickHouseCode, 'clickHouseCode', isNotNull),
          ),
        );
      });
    },
    skip: endpoint == null || password == null
        ? 'Set CLICKHOUSE_URL and CLICKHOUSE_PASSWORD.'
        : false,
    tags: 'integration',
  );
}

String quoteIdentifier(String identifier) {
  final escaped = identifier.replaceAll(r'\', r'\\').replaceAll('`', r'\`');
  return '`$escaped`';
}
