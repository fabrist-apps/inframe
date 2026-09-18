import 'dart:io';

import 'package:inlet/inlet.dart';
import 'package:inlet_cors/inlet_cors.dart';
import 'package:test/test.dart';

void main() {
  group('Cors', () {
    test('should apply preflight and recovered error grants over HTTP', () async {
      final app =
          Inlet(
              onReportError: (_, _) {},
              onError: (_, _, _, _) => Response.text('recovered', status: 418),
            )
            ..use(Cors(allowedOrigins: ['https://client.example']).call)
            ..get('/', (_, _) => throw StateError('failed'));
      final server = await app.serve(address: InternetAddress.loopbackIPv4, port: 0);
      addTearDown(() => server.close(force: true));
      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      for (final method in ['OPTIONS', 'GET']) {
        final request = await client.openUrl(method, Uri.parse('http://127.0.0.1:${server.port}/'));
        request.headers.set('origin', 'https://client.example');
        if (method == 'OPTIONS') {
          request.headers.set('access-control-request-method', 'GET');
        }
        final response = await request.close();
        expect(response.statusCode, method == 'OPTIONS' ? 204 : 418);
        expect(response.headers.value('access-control-allow-origin'), 'https://client.example');
        await response.drain<void>();
      }
    });

    test('should vary wildcard responses on origin presence', () async {
      final app = Inlet()
        ..use(Cors(allowedOrigins: ['*']).call)
        ..get('/', (_, _) => Response.empty());
      for (final headers in [
        const Headers.empty(),
        Headers.from({
          'origin': ['https://client.example'],
        }),
      ]) {
        final request = Request(method: 'GET', uri: Uri.parse('/'), headers: headers);
        addTearDown(request.close);
        final response = await app.handle(request);
        addTearDown(response.close);
        expect(response.headers['vary'], 'Origin');
      }
    });

    Future<Response> dispatch(
      Cors cors, {
      String method = 'GET',
      Map<String, List<String>> headers = const {},
      Handler? handler,
      ErrorHandler? onError,
    }) async {
      final app = Inlet(onError: onError, onReportError: (_, _) {})
        ..use(cors.call)
        ..get('/', handler ?? (_, _) => Response.text('hello'));
      final request = Request(method: method, uri: Uri.parse('/'), headers: Headers.from(headers));
      addTearDown(request.close);
      final response = await app.handle(request);
      addTearDown(response.close);
      return response;
    }

    test('should grant a configured origin and vary the response', () async {
      final cors = Cors(allowedOrigins: ['https://client.example']);
      final app = Inlet()
        ..use(cors.call)
        ..get('/', (_, _) => Response.text('hello'));
      final request = Request(
        method: 'GET',
        uri: Uri.parse('/'),
        headers: Headers.from({
          'origin': ['https://client.example'],
        }),
      );
      addTearDown(request.close);
      final response = await app.handle(request);
      addTearDown(response.close);
      expect(response.headers['access-control-allow-origin'], 'https://client.example');
      expect(response.headers['vary'], 'Origin');
      expect(await response.text(), 'hello');
    });

    test(
      'should pass requests without an origin and disallowed ordinary origins without a grant',
      () async {
        final cors = Cors(allowedOrigins: ['https://client.example']);
        for (final headers in <Map<String, List<String>>>[
          {},
          {
            'origin': ['https://other.example'],
          },
        ]) {
          final response = await dispatch(
            cors,
            headers: headers,
            handler: (_, _) => Response.text(
              'hello',
              headers: Headers.from({
                'access-control-allow-origin': ['*'],
                'access-control-allow-credentials': ['true'],
              }),
            ),
          );
          expect(response.statusCode, 200);
          expect(response.headers['access-control-allow-origin'], isNull);
          expect(response.headers['access-control-allow-credentials'], isNull);
          expect(response.headers['vary'], 'Origin');
        }
      },
    );

    test(
      'should answer allowed preflights before routing and parse request header lists',
      () async {
        final response = await dispatch(
          Cors(
            allowedOrigins: ['https://client.example'],
            allowedMethods: ['PUT'],
            allowedHeaders: ['Authorization', 'Content-Type'],
            allowCredentials: true,
            maxAge: const Duration(minutes: 5),
          ),
          method: 'OPTIONS',
          headers: {
            'origin': ['https://client.example'],
            'access-control-request-method': ['PUT'],
            'access-control-request-headers': ['AUTHORIZATION, content-type', 'authorization'],
          },
        );
        expect(response.statusCode, 204);
        expect(response.headers['access-control-allow-origin'], 'https://client.example');
        expect(response.headers['access-control-allow-credentials'], 'true');
        expect(response.headers['access-control-allow-methods'], 'PUT');
        expect(response.headers['access-control-allow-headers'], 'authorization, content-type');
        expect(response.headers['access-control-max-age'], '300');
        expect(
          response.headers['vary'],
          'Origin, Access-Control-Request-Method, Access-Control-Request-Headers',
        );
      },
    );

    test('should reject disallowed and malformed preflights without a grant', () async {
      final cors = Cors(allowedOrigins: ['https://client.example']);
      for (final override in <Map<String, List<String>>>[
        {
          'origin': ['https://other.example'],
        },
        {
          'origin': ['https://client.example', 'https://other.example'],
        },
        {
          'origin': ['https://client.example/path'],
        },
        {
          'access-control-request-method': ['DELETE'],
        },
        {
          'access-control-request-method': ['GET', 'POST'],
        },
        {'access-control-request-method': []},
        {
          'access-control-request-method': ['get'],
        },
        {
          'access-control-request-headers': ['authorization'],
        },
        {
          'access-control-request-headers': ['x-good,'],
        },
      ]) {
        final response = await dispatch(
          cors,
          method: 'OPTIONS',
          headers: {
            'origin': ['https://client.example'],
            'access-control-request-method': ['GET'],
            ...override,
          },
        );
        expect(response.statusCode, 403, reason: '$override');
        expect(response.headers['access-control-allow-origin'], isNull);
      }
    });

    test('should reject duplicate and malformed ordinary origins', () async {
      for (final origins in [
        <String>[],
        ['https://client.example', 'https://client.example'],
        ['https://client.example, https://other.example'],
        ['https://client.example/'],
      ]) {
        final response = await dispatch(Cors(allowedOrigins: ['*']), headers: {'origin': origins});
        expect(response.statusCode, 403);
        expect(response.headers['access-control-allow-origin'], isNull);
      }
    });

    test('should leave ordinary OPTIONS requests to routing', () async {
      final response = await dispatch(
        Cors(allowedOrigins: ['*']),
        method: 'OPTIONS',
        headers: {
          'origin': ['https://client.example'],
        },
      );
      expect(response.statusCode, 405);
      expect(response.headers['access-control-allow-origin'], '*');
    });

    test('should expose configured headers and merge Vary case-insensitively', () async {
      final response = await dispatch(
        Cors(allowedOrigins: ['https://client.example'], exposedHeaders: ['X-Request-ID']),
        headers: {
          'origin': ['https://client.example'],
        },
        handler: (_, _) => Response.empty(
          headers: Headers.from({
            'vary': ['Accept-Encoding, origin', 'ACCEPT-ENCODING'],
            'access-control-allow-origin': ['*'],
          }),
        ),
      );
      expect(response.headers['vary'], 'Accept-Encoding, origin');
      expect(response.headers.all('access-control-allow-origin'), ['https://client.example']);
      expect(response.headers['access-control-expose-headers'], 'x-request-id');
    });

    test('should preserve wildcard Vary', () async {
      final response = await dispatch(
        Cors(allowedOrigins: []),
        handler: (_, _) => Response.empty(
          headers: Headers.from({
            'vary': ['*'],
          }),
        ),
      );
      expect(response.headers['vary'], '*');
    });

    test('should grant headers on recovered errors and HEAD responses', () async {
      for (final method in ['GET', 'HEAD']) {
        final response = await dispatch(
          Cors(allowedOrigins: ['https://client.example']),
          method: method,
          headers: {
            'origin': ['https://client.example'],
          },
          handler: (_, _) => throw StateError('failed'),
          onError: (_, _, _, _) => Response.text('recovered', status: 418),
        );
        expect(response.statusCode, 418);
        expect(response.headers['access-control-allow-origin'], 'https://client.example');
        expect(await response.text(), method == 'HEAD' ? '' : 'recovered');
      }
    });

    test('should preserve lazy streaming responses', () async {
      var listened = false;
      Stream<List<int>> body() async* {
        listened = true;
        yield [1, 2];
      }

      final response = await dispatch(
        Cors(allowedOrigins: ['*']),
        headers: {
          'origin': ['https://client.example'],
        },
        handler: (_, _) => Response.stream(body()),
      );
      expect(listened, isFalse);
      expect(response.headers['access-control-allow-origin'], '*');
      expect(await response.bytes(), [1, 2]);
    });

    test('should copy configuration and validate policy', () {
      final origins = ['https://client.example'];
      final methods = ['GET'];
      final cors = Cors(allowedOrigins: origins, allowedMethods: methods);
      origins.clear();
      methods.clear();
      expect(cors.allowedOrigins, {'https://client.example'});
      expect(cors.allowedMethods, {'GET'});
      expect(() => Cors(allowedOrigins: ['*'], allowCredentials: true), throwsArgumentError);
      for (final origin in [
        'https://client.example/',
        'https://user@client.example',
        'https://client.example?q=1',
        'not an origin',
      ]) {
        expect(() => Cors(allowedOrigins: [origin]), throwsArgumentError);
      }
      expect(() => Cors(allowedOrigins: [], allowedMethods: ['GET, POST']), throwsArgumentError);
      expect(() => Cors(allowedOrigins: [], allowedHeaders: ['*']), throwsArgumentError);
      expect(() => Cors(allowedOrigins: [], exposedHeaders: ['bad header']), throwsArgumentError);
      expect(() => Cors(allowedOrigins: [], allowedMethods: ['GET\n']), throwsArgumentError);
      expect(
        () => Cors(allowedOrigins: [], maxAge: const Duration(seconds: -1)),
        throwsArgumentError,
      );
    });
  });
}
