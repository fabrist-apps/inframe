import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:inlet/inlet.dart';
import 'package:test/test.dart';

import 'tls_fixture.dart';

void main() {
  group('Inlet HTTP server', () {
    test('should serve the same JSON result in process and over HTTP', () async {
      final application = Inlet()
        ..post('/echo', (_, request) async {
          return Response.json(await request.json(maxBytes: 64 * 1024));
        })
        ..get(
          '/untyped',
          (_, _) => Response.bytes([1, 2, 3], contentType: null),
        );
      final localRequest = Request(
        method: 'POST',
        uri: Uri.parse('/echo'),
        headers: const Headers.empty().set('x-source', 'local'),
        body: Stream.value(utf8.encode('{"message":"hello"}')),
      );
      final localResponse = await application.handle(localRequest);
      final server = await application.serve(port: 0);
      addTearDown(() => server.close(force: true));

      final network = await _request(
        server,
        method: 'POST',
        path: '/echo',
        headers: {HttpHeaders.acceptEncodingHeader: 'gzip'},
        body: utf8.encode('{"message":"hello"}'),
      );
      final untyped = await _request(server, path: '/untyped');

      expect(network.statusCode, localResponse.statusCode);
      expect(network.headers[HttpHeaders.contentTypeHeader], localResponse.headers['content-type']);
      expect(jsonDecode(utf8.decode(network.body)), await localResponse.json());
      expect(network.headers[HttpHeaders.contentEncodingHeader], isNull);
      expect(untyped.headers[HttpHeaders.contentTypeHeader], isNull);
      await localResponse.close();
      await localRequest.close();
    });

    test('should bind TLS with the supplied security context', () async {
      final application = Inlet()..get('/secure', (_, _) => Response.text('secure'));
      final server = await application.serveSecure(_securityContext(), port: 0);
      addTearDown(() => server.close(force: true));

      final response = await _request(server, path: '/secure');

      expect(server.address, InternetAddress.loopbackIPv4);
      expect(server.port, greaterThan(0));
      expect(server.isSecure, isTrue);
      expect(utf8.decode(response.body), 'secure');
    });

    test('should use documented HTTP and TLS defaults', () async {
      final httpApplication = Inlet();
      final http = await httpApplication.serve();
      addTearDown(() => http.close(force: true));

      final tlsApplication = Inlet();
      final tls = await tlsApplication.serveSecure(_securityContext());
      addTearDown(() => tls.close(force: true));

      expect(http.address, InternetAddress.loopbackIPv4);
      expect(http.port, 8080);
      expect(http.isSecure, isFalse);
      expect(tls.address, InternetAddress.loopbackIPv4);
      expect(tls.port, 8443);
      expect(tls.isSecure, isTrue);
    });

    test('should validate listener options before freezing or binding', () async {
      final application = Inlet();

      await expectLater(application.serve(port: -1), throwsArgumentError);
      await expectLater(application.serve(port: 65536), throwsArgumentError);
      await expectLater(application.serve(backlog: -1), throwsArgumentError);
      await expectLater(
        application.serve(idleTimeout: const Duration(microseconds: -1)),
        throwsArgumentError,
      );
      expect(
        () => application.get('/still-editable', (_, _) => Response.empty()),
        returnsNormally,
      );

      final server = await application.serve(
        address: InternetAddress.loopbackIPv4,
        port: 0,
        backlog: 1,
        shared: true,
        idleTimeout: null,
      );
      expect(server.address, InternetAddress.loopbackIPv4);
      await server.close(force: true);
    });

    test('should expose transport-derived connection facts', () async {
      final application = Inlet()
        ..get('/connection', (_, request) {
          final connection = request.connection!;
          return Response.json({
            'remoteAddress': connection.remoteAddress.address,
            'remotePort': connection.remotePort,
            'localPort': connection.localPort,
            'secure': connection.isSecure,
          });
        });
      final server = await application.serve(port: 0);
      addTearDown(() => server.close(force: true));

      final response = await _request(
        server,
        path: '/connection',
        headers: {
          'forwarded': 'for=203.0.113.1;proto=https',
          'x-forwarded-for': '203.0.113.1',
        },
      );
      final facts = jsonDecode(utf8.decode(response.body))! as Map<String, Object?>;

      expect(facts['remoteAddress'], InternetAddress.loopbackIPv4.address);
      expect(facts['remotePort'], isA<int>().having((port) => port, 'port', greaterThan(0)));
      expect(facts['localPort'], server.port);
      expect(facts['secure'], isFalse);

      final simulated = ConnectionInfo(
        remoteAddress: InternetAddress('192.0.2.1'),
        remotePort: 1234,
        localPort: 5678,
        isSecure: true,
      );
      final inProcessRequest = Request(
        method: 'GET',
        uri: Uri.parse('/'),
        connection: simulated,
      );
      expect(inProcessRequest.connection, same(simulated));
      await inProcessRequest.close();
    });

    test('should reject invalid network metadata before dispatch', () async {
      var handlerCalls = 0;
      final application = Inlet()
        ..get('/', (_, _) {
          handlerCalls++;
          return Response.empty();
        });
      final server = await application.serve(port: 0);
      addTearDown(() => server.close(force: true));
      final socket = await Socket.connect(server.address, server.port);

      socket.add(
        latin1.encode(
          'POST / HTTP/1.1\r\n'
          'Host: ${server.address.address}:${server.port}\r\n'
          'Content-Length: 1000000\r\n'
          'X-Invalid: \x7f\r\n'
          '\r\n',
        ),
      );
      await socket.flush();
      final wireResponse = await latin1.decodeStream(socket);

      expect(wireResponse, startsWith('HTTP/1.1 400'));
      expect(wireResponse.toLowerCase(), contains('connection: close'));
      expect(handlerCalls, 0);
      await socket.close();
    });

    test('should replace a pre-commit delivery failure without leaking headers', () async {
      final reports = <Object>[];
      var hookCalls = 0;
      final application =
          Inlet(
            onError: (_, _, _, _) {
              hookCalls++;
              return Response.text(
                'replacement',
                status: HttpStatus.badGateway,
                headers: const Headers.empty().set('x-replacement', 'yes'),
              );
            },
            onReportError: (error, _) => reports.add(error),
          )..get('/', (_, _) async {
            final response = Response.text(
              'original',
              headers: Headers.from({
                'set-cookie': ['session=original'],
                'x-original': ['yes'],
              }),
            );
            await response.bytes();
            return response;
          });
      final server = await application.serve(port: 0);
      addTearDown(() => server.close(force: true));

      final response = await _request(server);

      expect(response.statusCode, HttpStatus.badGateway);
      expect(utf8.decode(response.body), 'replacement');
      expect(response.headers['x-replacement'], 'yes');
      expect(response.headers['x-original'], isNull);
      expect(response.headers['set-cookie'], isNull);
      expect(hookCalls, 1);
      expect(reports, hasLength(1));
    });

    test('should abort when a pre-commit replacement also cannot be delivered', () async {
      final reports = <Object>[];
      var hookCalls = 0;
      Future<Response> consumed(String value) async {
        final response = Response.text(value);
        await response.bytes();
        return response;
      }

      final application = Inlet(
        onError: (_, _, _, _) async {
          hookCalls++;
          return consumed('replacement');
        },
        onReportError: (error, _) => reports.add(error),
      )..get('/', (_, _) => consumed('original'));
      final server = await application.serve(port: 0);
      addTearDown(() => server.close(force: true));
      final socket = await Socket.connect(server.address, server.port);
      addTearDown(socket.destroy);

      socket.write(
        'GET / HTTP/1.1\r\n'
        'Host: ${server.address.address}:${server.port}\r\n'
        '\r\n',
      );
      await socket.flush();
      final bytes = await socket
          .fold<List<int>>(<int>[], (received, chunk) => received..addAll(chunk))
          .timeout(const Duration(seconds: 2));

      expect(bytes, isEmpty);
      expect(hookCalls, 1);
      expect(reports, hasLength(2));
    });

    test('should clean up network request and response wrappers after delivery', () async {
      late Request capturedRequest;
      late Response capturedResponse;
      final application = Inlet()
        ..post('/echo', (_, request) async {
          capturedRequest = request;
          return capturedResponse = Response.json(await request.json());
        });
      final server = await application.serve(port: 0);
      addTearDown(() => server.close(force: true));

      final response = await _request(
        server,
        method: 'POST',
        path: '/echo',
        body: utf8.encode('{"ok":true}'),
      );

      expect(response.statusCode, HttpStatus.ok);
      await expectLater(capturedResponse.bytes(), throwsStateError);
      await expectLater(capturedRequest.bytes(), throwsStateError);
    });

    test('should restore editability after a failed first bind', () async {
      final occupied = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(occupied.close);
      final application = Inlet();

      final failed = application.serve(port: occupied.port);
      expect(
        () => application.get('/pending', (_, _) => Response.empty()),
        throwsStateError,
      );
      await expectLater(failed, throwsA(isA<SocketException>()));

      expect(
        () => application.get('/after-failure', (_, _) => Response.text('available')),
        returnsNormally,
      );
      final server = await application.serve(port: 0);
      final response = await _request(server, path: '/after-failure');
      expect(utf8.decode(response.body), 'available');
      await server.close(force: true);
    });

    test('should let waiting dispatch and listener starts retry admission', () async {
      final occupied = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(occupied.close);
      final application = Inlet()..get('/ready', (_, _) => Response.text('ready'));
      final request = Request(method: 'GET', uri: Uri.parse('/ready'));

      final failed = application.serve(port: occupied.port);
      final dispatch = application.handle(request);
      final listener = application.serve(port: 0);
      await expectLater(failed, throwsA(isA<SocketException>()));
      final response = await dispatch;
      final server = await listener;

      expect(await response.text(), 'ready');
      expect(
        () => application.get('/frozen', (_, _) => Response.empty()),
        throwsStateError,
      );
      await response.close();
      await request.close();
      await server.close(force: true);
    });

    test('should share frozen routes across independent listeners', () async {
      final application = Inlet()..get('/shared', (_, _) => Response.text('shared'));
      final first = await application.serve(port: 0);
      final second = await application.serve(port: 0);
      addTearDown(() => first.close(force: true));
      addTearDown(() => second.close(force: true));

      expect(utf8.decode((await _request(first, path: '/shared')).body), 'shared');
      expect(utf8.decode((await _request(second, path: '/shared')).body), 'shared');
      await expectLater(
        application.serve(port: first.port),
        throwsA(isA<SocketException>()),
      );
      expect(
        () => application.get('/still-frozen', (_, _) => Response.empty()),
        throwsStateError,
      );
    });
  });
}

SecurityContext _securityContext() => SecurityContext()
  ..useCertificateChainBytes(utf8.encode(testCertificate))
  ..usePrivateKeyBytes(utf8.encode(testPrivateKey));

Future<_NetworkResponse> _request(
  InletServer server, {
  String method = 'GET',
  String path = '/',
  Map<String, String> headers = const {},
  List<int>? body,
}) async {
  final client = HttpClient()..badCertificateCallback = (_, _, _) => true;
  try {
    final request = await client.openUrl(
      method,
      Uri(
        scheme: server.isSecure ? 'https' : 'http',
        host: server.address.address,
        port: server.port,
        path: path,
      ),
    );
    headers.forEach(request.headers.set);
    if (body != null) {
      request.add(body);
    }
    final response = await request.close();
    final responseHeaders = <String, String>{};
    response.headers.forEach((name, values) {
      responseHeaders[name] = values.first;
    });
    return _NetworkResponse(
      response.statusCode,
      Map.unmodifiable(responseHeaders),
      await response.fold<List<int>>(<int>[], (bytes, chunk) => bytes..addAll(chunk)),
    );
  } finally {
    client.close(force: true);
  }
}

final class _NetworkResponse {
  const _NetworkResponse(this.statusCode, this.headers, this.body);

  final int statusCode;
  final Map<String, String> headers;
  final List<int> body;
}
