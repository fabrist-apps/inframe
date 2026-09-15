import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:clickhouse/clickhouse.dart';
import 'package:test/test.dart';

import 'support/http_server.dart';

void main() {
  group('ClickHouseClient failures', () {
    test('should report connection refusal before transmission', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final client = createClient(serverUrl(server));
      await server.close(force: true);
      addTearDown(client.close);
      await expectLater(
        client.command('SELECT 1'),
        throwsA(
          isA<ClickHouseTransportException>().having(
            (error) => error.requestState,
            'requestState',
            ClickHouseRequestState.notSent,
          ),
        ),
      );
    });

    test(
      'should allow request bodies at the limit and reject larger bodies before sending',
      () async {
        await expectRequestBoundary(
          body: 'SELECT 1',
          invoke: (client) => client.query('SELECT 1'),
          responseBody: validResult,
        );
        await expectRequestBoundary(
          body: 'DROP TABLE events',
          invoke: (client) => client.command('DROP TABLE events'),
        );
        await expectRequestBoundary(
          body: 'INSERT INTO `events` FORMAT JSONEachRow\n{"id":1}\n',
          invoke: (client) => client.insert(
            table: 'events',
            rows: [
              <String, Object?>{'id': 1},
            ],
          ),
        );
      },
    );

    test(
      'should allow a response at the limit and stop a larger response during consumption',
      () async {
        final responseBytes = utf8.encode(validResult);
        final acceptedServer = await responseServer(responseBytes);
        addTearDown(() => acceptedServer.close(force: true));
        final acceptedClient = createClient(
          serverUrl(acceptedServer),
          maxResponseBytes: responseBytes.length,
        );
        addTearDown(acceptedClient.close);

        expect((await acceptedClient.query('SELECT 1')).rows.single['value'], 1);

        final rejectedServer = await responseServer(responseBytes);
        addTearDown(() => rejectedServer.close(force: true));
        final rejectedClient = createClient(
          serverUrl(rejectedServer),
          maxResponseBytes: responseBytes.length - 1,
        );
        addTearDown(rejectedClient.close);

        await expectLater(
          rejectedClient.query('SELECT 1'),
          throwsA(
            isA<ClickHouseSizeLimitException>()
                .having(
                  (error) => error.direction,
                  'direction',
                  ClickHouseSizeLimitDirection.response,
                )
                .having((error) => error.limit, 'limit', responseBytes.length - 1)
                .having(
                  (error) => error.requestState,
                  'requestState',
                  ClickHouseRequestState.mayHaveReachedServer,
                ),
          ),
        );
      },
    );

    test('should count decompressed response bytes including error bodies', () async {
      final largeResult = jsonEncode({
        'meta': [
          {'name': 'value', 'type': 'String'},
        ],
        'data': [
          {'value': 'x' * 1024},
        ],
        'rows': 1,
      });
      final compressedServer = await responseServer(
        gzip.encode(utf8.encode(largeResult)),
        contentEncoding: 'gzip',
      );
      addTearDown(() => compressedServer.close(force: true));
      final compressedClient = createClient(serverUrl(compressedServer), maxResponseBytes: 100);
      addTearDown(compressedClient.close);

      await expectLater(
        compressedClient.query('SELECT 1'),
        throwsA(isA<ClickHouseSizeLimitException>()),
      );

      final errorServer = await responseServer(
        utf8.encode('Code: 62. DB::Exception: ${'x' * 1024}'),
        statusCode: HttpStatus.badRequest,
      );
      addTearDown(() => errorServer.close(force: true));
      final errorClient = createClient(serverUrl(errorServer), maxResponseBytes: 100);
      addTearDown(errorClient.close);

      await expectLater(
        errorClient.command('INVALID SQL'),
        throwsA(isA<ClickHouseSizeLimitException>()),
      );
    });

    test('should preserve server status, code, query ID, and transmission state', () async {
      final server = await responseServer(
        utf8.encode('Code: 62. DB::Exception: Syntax error'),
        statusCode: HttpStatus.badRequest,
        queryId: 'query-id',
      );
      addTearDown(() => server.close(force: true));
      final client = createClient(serverUrl(server));
      addTearDown(client.close);

      await expectLater(
        client.command('INVALID SQL'),
        throwsA(
          isA<ClickHouseServerException>()
              .having((error) => error.statusCode, 'statusCode', HttpStatus.badRequest)
              .having((error) => error.clickHouseCode, 'clickHouseCode', 62)
              .having((error) => error.queryId, 'queryId', 'query-id')
              .having(
                (error) => error.requestState,
                'requestState',
                ClickHouseRequestState.mayHaveReachedServer,
              ),
        ),
      );
    });

    test('should preserve a ClickHouse error code supplied only by a response header', () async {
      final server = await responseServer(
        utf8.encode('Rejected'),
        statusCode: HttpStatus.badRequest,
        exceptionCode: 516,
      );
      addTearDown(() => server.close(force: true));
      final client = createClient(serverUrl(server));
      addTearDown(client.close);

      await expectLater(
        client.command('SELECT 1'),
        throwsA(
          isA<ClickHouseServerException>().having(
            (error) => error.clickHouseCode,
            'clickHouseCode',
            516,
          ),
        ),
      );
    });

    test('should recognize a late server error after HTTP 200', () async {
      final server = await responseServer(
        utf8.encode('$validResult\nCode: 241. DB::Exception: Memory limit exceeded'),
      );
      addTearDown(() => server.close(force: true));
      final client = createClient(serverUrl(server));
      addTearDown(client.close);

      await expectLater(
        client.query('SELECT 1'),
        throwsA(
          isA<ClickHouseServerException>()
              .having((error) => error.statusCode, 'statusCode', HttpStatus.ok)
              .having((error) => error.clickHouseCode, 'clickHouseCode', 241),
        ),
      );
    });

    test('should reject unexpected command output', () async {
      final server = await responseServer(utf8.encode('unexpected'));
      addTearDown(() => server.close(force: true));
      final client = createClient(serverUrl(server));
      addTearDown(client.close);

      await expectLater(
        client.command('CREATE TABLE events (id UInt8)'),
        throwsA(isA<ClickHouseProtocolException>()),
      );
    });

    test('should report malformed results without preventing a later operation', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      var requestCount = 0;
      server.listen((request) async {
        await request.drain<void>();
        requestCount += 1;
        request.response.write(requestCount == 1 ? '{"meta":[' : validResult);
        await request.response.close();
      });
      final client = createClient(serverUrl(server));
      addTearDown(client.close);

      await expectLater(client.query('SELECT broken'), throwsA(isA<ClickHouseProtocolException>()));
      expect((await client.query('SELECT 1')).rows.single['value'], 1);
    });

    test('should preserve a truncated response transport cause', () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      server.listen((socket) {
        var responded = false;
        socket.listen((_) {
          if (responded) {
            return;
          }
          responded = true;
          unawaited(
            (socket..add(utf8.encode('HTTP/1.1 200 OK\r\nContent-Length: 100\r\n\r\nshort')))
                .close(),
          );
        });
      });
      final client = ClickHouseClient(
        endpoint: 'http://${server.address.host}:${server.port}',
        database: 'analytics',
        username: 'tester',
        password: 'secret',
        allowInsecureHttp: true,
      );
      addTearDown(client.close);

      await expectLater(
        client.query('SELECT 1'),
        throwsA(
          isA<ClickHouseTransportException>()
              .having((error) => error.cause, 'cause', isA<HttpException>())
              .having(
                (error) => error.requestState,
                'requestState',
                ClickHouseRequestState.mayHaveReachedServer,
              ),
        ),
      );
    });

    test('should report interrupted writes as unknown without retrying', () async {
      for (final operation in <Future<void> Function(ClickHouseClient)>[
        (client) => client.command('CREATE TABLE interrupted (id UInt8)'),
        (client) => client.insert(
          table: 'events',
          rows: [
            <String, Object?>{'id': 1},
          ],
        ),
      ]) {
        final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(server.close);
        var connections = 0;
        server.listen((socket) {
          connections += 1;
          socket.listen((_) => socket.destroy());
        });
        final client = ClickHouseClient(
          endpoint: 'http://${server.address.host}:${server.port}',
          database: 'analytics',
          username: 'tester',
          password: 'secret',
          allowInsecureHttp: true,
        );
        addTearDown(client.close);

        await expectLater(
          operation(client),
          throwsA(
            isA<ClickHouseTransportException>().having(
              (error) => error.requestState,
              'requestState',
              ClickHouseRequestState.mayHaveReachedServer,
            ),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(connections, 1);
      }
    });
  });
}

Future<void> expectRequestBoundary({
  required String body,
  required Future<Object?> Function(ClickHouseClient client) invoke,
  String responseBody = '',
}) async {
  final bodyBytes = utf8.encode(body);
  final acceptedServer = await responseServer(utf8.encode(responseBody));
  final acceptedClient = createClient(serverUrl(acceptedServer), maxRequestBytes: bodyBytes.length);
  addTearDown(acceptedClient.close);
  addTearDown(() => acceptedServer.close(force: true));

  await invoke(acceptedClient);

  final rejectedServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  var requests = 0;
  rejectedServer.listen((request) async {
    requests += 1;
    await request.drain<void>();
    request.response.write(responseBody);
    await request.response.close();
  });
  final rejectedClient = createClient(
    serverUrl(rejectedServer),
    maxRequestBytes: bodyBytes.length - 1,
  );
  addTearDown(rejectedClient.close);
  addTearDown(() => rejectedServer.close(force: true));

  await expectLater(
    invoke(rejectedClient),
    throwsA(
      isA<ClickHouseSizeLimitException>()
          .having((error) => error.direction, 'direction', ClickHouseSizeLimitDirection.request)
          .having((error) => error.limit, 'limit', bodyBytes.length - 1)
          .having(
            (error) => error.requestState,
            'requestState',
            ClickHouseRequestState.notSent,
          ),
    ),
  );
  await Future<void>.delayed(const Duration(milliseconds: 20));
  expect(requests, 0);
}
