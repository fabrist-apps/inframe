import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:clickhouse/clickhouse.dart';
import 'package:test/test.dart';

void main() {
  group('ClickHouseClient lifecycle', () {
    test('should time out response headers and keep the request outcome unknown', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final requestReceived = Completer<HttpRequest>();
      server.listen(requestReceived.complete);
      final client = createClient(server);
      addTearDown(client.close);

      final query = client.query('SELECT 1', timeout: const Duration(seconds: 1));
      final expectation = expectLater(
        query,
        throwsA(
          isA<ClickHouseTimeoutException>().having(
            (error) => error.requestState,
            'requestState',
            ClickHouseRequestState.mayHaveReachedServer,
          ),
        ),
      );
      final request = await requestReceived.future;

      await expectation;
      await request.response.close();
    });

    test('should detect a deadline exhausted by encoding before transmission', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      var requests = 0;
      server.listen((request) async {
        requests += 1;
        await request.drain<void>();
        await request.response.close();
      });
      final client = createClient(server);
      addTearDown(client.close);
      final rows = List<Map<String, Object?>>.generate(
        10000,
        (index) => {'index': index, 'value': 'x' * 100},
      );

      await expectLater(
        client.insert(table: 'events', rows: rows, timeout: const Duration(microseconds: 1)),
        throwsA(
          isA<ClickHouseTimeoutException>().having(
            (error) => error.requestState,
            'requestState',
            ClickHouseRequestState.notSent,
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(requests, 0);
    });

    test('should apply timeout overrides to commands and inserts', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        await request.drain<void>();
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await request.response.close();
      });
      final client = createClient(server);
      addTearDown(client.close);

      await expectLater(
        client.command('DROP TABLE events', timeout: const Duration(milliseconds: 20)),
        throwsA(isA<ClickHouseTimeoutException>()),
      );
      await expectLater(
        client.insert(
          table: 'events',
          rows: [
            <String, Object?>{'id': 1},
          ],
          timeout: const Duration(milliseconds: 20),
        ),
        throwsA(isA<ClickHouseTimeoutException>()),
      );
    });

    test('should isolate concurrent operation settings and failures', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final received = <String, Map<String, String>>{};
      server.listen((request) async {
        final body = await utf8.decoder.bind(request).join();
        received[body] = request.uri.queryParameters;
        if (body == 'SELECT slow') {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        if (body.startsWith('SELECT')) {
          request.response.write(validResult);
        }
        await request.response.close();
      });
      final client = createClient(server);
      addTearDown(client.close);

      final slow = client.query(
        'SELECT slow',
        parameters: {'request': 'slow'},
        timeout: const Duration(milliseconds: 20),
      );
      final fast = client.query(
        'SELECT fast',
        parameters: {'request': 'fast'},
        timeout: const Duration(seconds: 1),
      );
      final insert = client.insert(
        table: 'events',
        rows: [
          <String, Object?>{'id': 1},
        ],
        deduplicationToken: 'batch-id',
      );

      await expectLater(slow, throwsA(isA<ClickHouseTimeoutException>()));
      expect((await fast).rows.single['value'], 1);
      await insert;
      expect(received['SELECT slow']?['param_request'], 'slow');
      expect(received['SELECT fast']?['param_request'], 'fast');
      expect(
        received['INSERT INTO `events` FORMAT JSONEachRow\n{"id":1}\n']?['insert_deduplication_token'],
        'batch-id',
      );
    });

    test('should wait for active work and make repeated close calls share shutdown', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final requestReceived = Completer<HttpRequest>();
      server.listen(requestReceived.complete);
      final client = createClient(server);
      final operation = client.query('SELECT 1');
      final request = await requestReceived.future;

      final firstClose = client.close();
      final secondClose = client.close();
      var closeCompleted = false;
      unawaited(firstClose.then((_) => closeCompleted = true));
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(identical(firstClose, secondClose), isTrue);
      expect(closeCompleted, isFalse);
      await expectLater(client.query('SELECT 2'), throwsStateError);
      await expectLater(client.command('DROP TABLE events'), throwsStateError);
      await expectLater(client.insert(table: 'events', rows: []), throwsStateError);

      request.response.write(validResult);
      await request.response.close();
      await operation;
      await firstClose;
      expect(closeCompleted, isTrue);
    });

    test('should let an active operation reach its deadline while closing', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        await request.drain<void>();
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await request.response.close();
      });
      final client = createClient(server);
      final operation = client.query('SELECT slow', timeout: const Duration(milliseconds: 20));
      final operationExpectation = expectLater(
        operation,
        throwsA(isA<ClickHouseTimeoutException>()),
      );

      final shutdown = client.close();
      await operationExpectation;
      await shutdown;
    });

    test('should reject non-positive timeout overrides for every operation', () async {
      final client = ClickHouseClient(
        endpoint: 'http://127.0.0.1:1',
        database: 'analytics',
        username: 'tester',
        password: 'secret',
      );
      addTearDown(client.close);

      await expectLater(client.query('SELECT 1', timeout: Duration.zero), throwsArgumentError);
      await expectLater(client.command('SELECT 1', timeout: Duration.zero), throwsArgumentError);
      await expectLater(
        client.insert(table: 'events', rows: [], timeout: Duration.zero),
        throwsArgumentError,
      );
    });
  });
}

const validResult = '{"meta":[{"name":"value","type":"UInt8"}],"data":[{"value":1}],"rows":1}';

ClickHouseClient createClient(HttpServer server) => ClickHouseClient(
  endpoint: 'http://${server.address.host}:${server.port}',
  database: 'analytics',
  username: 'tester',
  password: 'secret',
);
