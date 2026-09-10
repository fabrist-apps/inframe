import 'dart:async';
import 'dart:io';

import 'package:inlet/inlet.dart';
import 'package:test/test.dart';

void main() {
  group('Inlet routing', () {
    test('should prefer literals then parameters then wildcards', () async {
      final application = Inlet()
        ..get('/items/*rest', (_, request) => Response.json(request.pathParameters))
        ..get('/items/:id', (_, request) => Response.json(request.pathParameters))
        ..get('/items/new', (_, _) => Response.text('literal'));

      expect(await _responseText(application, 'GET', '/items/new'), 'literal');
      expect(await _responseJson(application, 'GET', '/items/42'), {'id': '42'});
      expect(await _responseJson(application, 'GET', '/items/a/b'), {'rest': 'a/b'});
    });

    test('should backtrack across complete method and path candidates', () async {
      final application = Inlet()
        ..get('/documents/new', (_, _) => Response.text('GET literal'))
        ..post('/documents/:id', (_, request) => Response.text(request.pathParameters['id']!));

      expect(await _responseText(application, 'POST', '/documents/new'), 'new');
    });

    test('should decode captures once after splitting path separators', () async {
      final application = Inlet()
        ..get('/files/:value', (_, request) => Response.text(request.pathParameters['value']!))
        ..get('/caf%C3%A9/%3Aid', (_, _) => Response.text('literal'))
        ..get('/literal/%2F', (_, _) => Response.text('separator'));

      expect(await _responseText(application, 'GET', '/files/a%2Fb'), 'a/b');
      expect(await _responseText(application, 'GET', '/files/a%252Fb'), 'a%2Fb');
      expect(await _responseText(application, 'GET', '/caf%C3%A9/%3Aid?ignored=true'), 'literal');
      expect(await _responseText(application, 'GET', '/literal/%2F'), 'separator');
    });

    test('should return routing errors and sorted method allowances', () async {
      final application = Inlet()
        ..get('/items/new', (_, _) => Response.empty())
        ..post('/items/:id', (_, _) => Response.empty())
        ..put('/items/*rest', (_, _) => Response.empty());

      final missing = await _dispatch(application, 'GET', '/missing');
      final unsupported = await _dispatch(application, 'DELETE', '/items/new');
      final malformed = await _dispatch(application, 'GET', '/items/%FF');
      addTearDown(() async {
        await missing.response.close();
        await missing.request.close();
        await unsupported.response.close();
        await unsupported.request.close();
        await malformed.response.close();
        await malformed.request.close();
      });

      expect(missing.response.statusCode, HttpStatus.notFound);
      expect(await missing.response.bytes(), isEmpty);
      expect(unsupported.response.statusCode, HttpStatus.methodNotAllowed);
      expect(unsupported.response.headers['allow'], 'GET, HEAD, POST, PUT');
      expect(await unsupported.response.bytes(), isEmpty);
      expect(malformed.response.statusCode, HttpStatus.badRequest);
    });

    test('should prefer explicit HEAD before GET fallback without reading a body', () async {
      var subscriptions = 0;
      var explicitHeadCalls = 0;
      final application = Inlet()
        ..get(
          '/items/new',
          (_, _) => Response.stream(
            Stream<List<int>>.multi((controller) {
              subscriptions++;
              final closeFuture = (controller..add([1])).close();
              unawaited(closeFuture);
            }),
          ),
        )
        ..get(
          '/fallback',
          (_, _) => Response.stream(
            Stream<List<int>>.multi((controller) {
              subscriptions++;
              final closeFuture = (controller..add([1])).close();
              unawaited(closeFuture);
            }),
          ),
        )
        ..head('/items/:id', (_, request) {
          explicitHeadCalls++;
          return Response.text('head:${request.pathParameters['id']}');
        });

      final explicit = await _dispatch(application, 'HEAD', '/items/new');
      final fallback = await _dispatch(application, 'HEAD', '/fallback');
      addTearDown(() async {
        await explicit.response.close();
        await explicit.request.close();
        await fallback.response.close();
        await fallback.request.close();
      });

      expect(await explicit.response.bytes(), isEmpty);
      expect(await fallback.response.bytes(), isEmpty);
      expect(explicitHeadCalls, 1);
      expect(subscriptions, 0);
    });

    test('should distinguish strict trailing slashes and wildcard suffixes', () async {
      final application = Inlet()
        ..get('/items', (_, _) => Response.text('exact'))
        ..get('/files/*path', (_, request) => Response.text(request.pathParameters['path']!))
        ..get('/', (_, _) => Response.text('root'));

      expect(await _responseStatus(application, 'GET', '/items/'), 404);
      expect(await _responseStatus(application, 'GET', '/files'), 404);
      expect(await _responseText(application, 'GET', '/files/'), '');
      expect(await _responseText(application, 'GET', '/'), 'root');

      final rootWildcard = Inlet()
        ..get('/*path', (_, request) => Response.text(request.pathParameters['path']!));
      expect(await _responseText(rootWildcard, 'GET', '/'), '');
    });

    test('should remove one trailing slash in relaxed mode', () async {
      final application = Inlet(strict: false)
        ..get('/items/', (_, _) => Response.text('item'))
        ..get('/files/*path', (_, request) => Response.text(request.pathParameters['path']!))
        ..get('/double//', (_, _) => Response.text('double'));

      expect(await _responseText(application, 'GET', '/items'), 'item');
      expect(await _responseText(application, 'GET', '/items/'), 'item');
      expect(await _responseText(application, 'GET', '/files'), '');
      expect(await _responseStatus(application, 'GET', '/double'), 404);
      expect(await _responseText(application, 'GET', '/double//'), 'double');
    });

    test('should snapshot child routers under parameterized prefixes', () async {
      final child = Router()
        ..get('/:documentId', (_, request) => Response.json(request.pathParameters));
      final application = Inlet()
        ..route('/api/:tenant/documents', child)
        ..route('/archive/:year/documents', child);
      child.get('/later/route', (_, _) => Response.text('late'));

      expect(await _responseJson(application, 'GET', '/api/acme/documents/42'), {
        'tenant': 'acme',
        'documentId': '42',
      });
      expect(await _responseJson(application, 'GET', '/archive/2024/documents/7'), {
        'year': '2024',
        'documentId': '7',
      });
      expect(await _responseStatus(application, 'GET', '/api/acme/documents/later/route'), 404);
    });

    test('should reject an entire conflicting child mount atomically', () {
      final parent = Inlet()..get('/api/a', (_, _) => Response.empty());
      final child = Router()
        ..get('/a', (_, _) => Response.empty())
        ..get('/b', (_, _) => Response.empty());

      expect(() => parent.route('/api', child), throwsStateError);
      expect(() => parent.get('/api/b', (_, _) => Response.empty()), returnsNormally);
    });

    test('should validate patterns and structural conflicts', () {
      final application = Inlet(strict: false)..get('/items/:id', (_, _) => Response.empty());

      expect(() => application.get('/items/:name', (_, _) => Response.empty()), throwsStateError);
      expect(() => application.get('/items/:id/', (_, _) => Response.empty()), throwsStateError);
      expect(() => application.post('/items/:name', (_, _) => Response.empty()), returnsNormally);
      expect(() => application.get('relative', (_, _) => Response.empty()), throwsArgumentError);
      expect(() => application.get('/bad/:', (_, _) => Response.empty()), throwsArgumentError);
      expect(
        () => application.get('/bad/*rest/more', (_, _) => Response.empty()),
        throwsArgumentError,
      );
      expect(
        () => application.get('/bad/*rest/', (_, _) => Response.empty()),
        throwsArgumentError,
      );
      expect(
        () => application.get('/bad/:id/:id', (_, _) => Response.empty()),
        throwsArgumentError,
      );
      expect(() => application.get('/bad?query', (_, _) => Response.empty()), throwsArgumentError);
    });

    test('should freeze registration synchronously on first admission', () async {
      final release = Completer<void>();
      final application = Inlet()
        ..get('/wait', (_, _) async {
          await release.future;
          return Response.empty();
        });
      final firstRequest = Request(method: 'GET', uri: Uri.parse('/wait'));
      final secondRequest = Request(method: 'GET', uri: Uri.parse('/wait'));

      final first = application.handle(firstRequest);
      final second = application.handle(secondRequest);
      expect(() => application.get('/late', (_, _) => Response.empty()), throwsStateError);
      release.complete();
      final responses = await Future.wait([first, second]);
      addTearDown(() async {
        for (final response in responses) {
          await response.close();
        }
        await firstRequest.close();
        await secondRequest.close();
      });

      expect(responses, hasLength(2));
    });
  });
}

Future<String> _responseText(Inlet application, String method, String path) async {
  final exchange = await _dispatch(application, method, path);
  try {
    return await exchange.response.text();
  } finally {
    await exchange.response.close();
    await exchange.request.close();
  }
}

Future<Object?> _responseJson(Inlet application, String method, String path) async {
  final exchange = await _dispatch(application, method, path);
  try {
    return await exchange.response.json();
  } finally {
    await exchange.response.close();
    await exchange.request.close();
  }
}

Future<int> _responseStatus(Inlet application, String method, String path) async {
  final exchange = await _dispatch(application, method, path);
  try {
    return exchange.response.statusCode;
  } finally {
    await exchange.response.close();
    await exchange.request.close();
  }
}

Future<({Request request, Response response})> _dispatch(
  Inlet application,
  String method,
  String path,
) async {
  final request = Request(method: method, uri: Uri.parse(path));
  final response = await application.handle(request);
  return (request: request, response: response);
}
