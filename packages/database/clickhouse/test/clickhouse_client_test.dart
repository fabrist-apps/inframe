import 'dart:convert';
import 'dart:io';

import 'package:clickhouse/clickhouse.dart';
import 'package:test/test.dart';

void main() {
  group('ClickHouseClient', () {
    test('should reject invalid endpoints and limits before network activity', () {
      for (final endpoint in [
        'ftp://clickhouse.example',
        'http:///missing-host',
        'http://@clickhouse.example',
        'http://user:password@clickhouse.example',
        'http://clickhouse.example?setting=value',
        'http://clickhouse.example#fragment',
      ]) {
        expect(() => createClient(endpoint), throwsArgumentError);
      }

      expect(
        () => createClient('http://clickhouse.example', timeout: Duration.zero),
        throwsArgumentError,
      );
      expect(
        () => createClient('http://clickhouse.example', maxRequestBytes: 0),
        throwsArgumentError,
      );
      expect(
        () => createClient('http://clickhouse.example', maxResponseBytes: -1),
        throwsArgumentError,
      );
    });

    test('should preserve proxy paths, headers, SQL, and parameters', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final requestFuture = server.first;
      final client = createClient('${serverUrl(server)}/clickhouse/proxy', password: '');
      addTearDown(client.close);

      final queryFuture = client.query(
        'SELECT {value:String}',
        parameters: {'value': "quote ' tab\t line\n slash\\ café"},
      );
      final request = await requestFuture;
      final body = await utf8.decoder.bind(request).join();

      expect(request.uri.path, '/clickhouse/proxy');
      expect(request.uri.queryParameters['database'], 'analytics');
      expect(request.uri.queryParameters['param_value'], r"quote ' tab\t line\n slash\\ café");
      expect(request.headers.value('x-clickhouse-user'), 'tester');
      expect(request.headers.value('x-clickhouse-key'), '');
      expect(request.headers.value('x-clickhouse-format'), 'JSON');
      expect(body, 'SELECT {value:String}');

      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write('''
          {
            "meta": [{"name": "value", "type": "String"}],
            "data": [{"value": "ok"}],
            "rows": 1
          }
        ''');
      await request.response.close();

      final result = await queryFuture;
      expect(result.columns.single.name, 'value');
      expect(result.columns.single.type, 'String');
      expect(result.rows, [
        <String, Object?>{'value': 'ok'},
      ]);
    });

    test('should preserve row order, exact strings, and nested immutability', () async {
      final server = await jsonServer({
        'meta': [
          {'name': 'number', 'type': 'UInt128'},
          {'name': 'nested', 'type': 'Array(String)'},
        ],
        'data': [
          {
            'number': '340282366920938463463374607431768211455',
            'nested': ['first'],
          },
          {
            'number': '1.230000000000000000',
            'nested': ['second'],
          },
        ],
        'rows': 2,
      });
      addTearDown(() => server.close(force: true));
      final client = createClient(serverUrl(server));
      addTearDown(client.close);

      final result = await client.query('SELECT number, nested');

      expect(result.rows.map((row) => row['number']), [
        '340282366920938463463374607431768211455',
        '1.230000000000000000',
      ]);
      expect(
        () => result.columns.add(const ClickHouseColumn(name: 'x', type: 'String')),
        throwsUnsupportedError,
      );
      expect(() => result.rows.add(<String, Object?>{}), throwsUnsupportedError);
      expect(() => result.rows.first['number'] = 'changed', throwsUnsupportedError);
      expect(
        () => (result.rows.first['nested']! as List<Object?>).add('changed'),
        throwsUnsupportedError,
      );
    });

    test('should reject duplicate metadata names and malformed results', () async {
      final duplicateServer = await jsonServer({
        'meta': [
          {'name': 'value', 'type': 'String'},
          {'name': 'value', 'type': 'String'},
        ],
        'data': [
          {'value': 'lost'},
        ],
        'rows': 1,
      });
      addTearDown(() => duplicateServer.close(force: true));
      final duplicateClient = createClient(serverUrl(duplicateServer));
      addTearDown(duplicateClient.close);

      await expectLater(
        duplicateClient.query('SELECT 1'),
        throwsA(isA<ClickHouseProtocolException>()),
      );

      final malformedServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => malformedServer.close(force: true));
      malformedServer.listen((request) async {
        request.response
          ..statusCode = HttpStatus.ok
          ..write('{"meta": [], "data": [');
        await request.response.close();
      });
      final malformedClient = createClient(serverUrl(malformedServer));
      addTearDown(malformedClient.close);

      await expectLater(
        malformedClient.query('SELECT 1'),
        throwsA(isA<ClickHouseProtocolException>()),
      );
    });

    test('should reject a non-positive operation timeout', () async {
      final client = createClient('http://127.0.0.1:1');
      addTearDown(client.close);

      await expectLater(client.query('SELECT 1', timeout: Duration.zero), throwsArgumentError);
    });

    test('should execute commands with separately bound parameters', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final requestFuture = server.first;
      final client = createClient(serverUrl(server));
      addTearDown(client.close);

      final commandFuture = client.command(
        'CREATE TABLE {table:String}',
        parameters: {'table': 'events\narchive'},
      );
      final request = await requestFuture;

      expect(await utf8.decoder.bind(request).join(), 'CREATE TABLE {table:String}');
      expect(request.uri.queryParameters['param_table'], r'events\narchive');
      await request.response.close();
      await commandFuture;
    });

    test('should quote one table identifier and encode a validated JSONEachRow batch', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final requestFuture = server.first;
      final client = createClient(serverUrl(server));
      addTearDown(client.close);

      final insertFuture = client.insert(
        table: r'events.raw`archive\name',
        rows: [
          {
            'id': 1,
            'data': {
              'active': true,
              'labels': ['one', null],
            },
          },
        ],
        deduplicationToken: r'batch\token',
      );
      final request = await requestFuture;
      final body = await utf8.decoder.bind(request).join();

      expect(
        body,
        '${r'INSERT INTO `events.raw\`archive\\name` FORMAT JSONEachRow'}\n'
        '{"id":1,"data":{"active":true,"labels":["one",null]}}\n',
      );
      expect(request.uri.queryParameters['async_insert'], '0');
      expect(request.uri.queryParameters['insert_deduplication_token'], r'batch\token');
      await request.response.close();
      await insertFuture;
    });

    test('should validate empty and invalid batches before network activity', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      var requests = 0;
      server.listen((request) async {
        requests += 1;
        await request.response.close();
      });
      final client = createClient(serverUrl(server));
      addTearDown(client.close);

      await client.insert(table: 'events', rows: []);
      await expectLater(
        client.insert(
          table: 'events',
          rows: [
            <String, Object?>{'valid': true},
            <String, Object?>{
              'invalid': <Object?, Object?>{1: 'not a JSON object'},
            },
          ],
        ),
        throwsArgumentError,
      );
      await expectLater(client.insert(table: '', rows: []), throwsArgumentError);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(requests, 0);
    });
  });
}

ClickHouseClient createClient(
  String endpoint, {
  String password = 'secret',
  Duration timeout = const Duration(seconds: 30),
  int maxRequestBytes = 16 * 1024 * 1024,
  int maxResponseBytes = 16 * 1024 * 1024,
}) => ClickHouseClient(
  endpoint: endpoint,
  database: 'analytics',
  username: 'tester',
  password: password,
  timeout: timeout,
  maxRequestBytes: maxRequestBytes,
  maxResponseBytes: maxResponseBytes,
);

String serverUrl(HttpServer server) => 'http://${server.address.host}:${server.port}';

Future<HttpServer> jsonServer(Object? body) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    request.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(body));
    await request.response.close();
  });
  return server;
}
