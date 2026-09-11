import 'dart:async';
import 'dart:io';

import 'package:inlet/inlet.dart';
import 'package:test/test.dart';

import 'tls_fixture.dart';

void main() {
  group('Inlet WebSocket delivery', () {
    test('should exchange text and binary messages over HTTP and TLS', () async {
      for (final secure in [false, true]) {
        final sessions = <WebSocket>{};
        final application = Inlet()
          ..get('/chat', (_, _) {
            return Response.webSocket(
              headers: const Headers.empty().set('x-application', 'chat'),
              onConnect: (socket) async {
                sessions.add(socket);
                try {
                  await socket.forEach(socket.add);
                } finally {
                  sessions.remove(socket);
                }
              },
            );
          });
        final server = secure
            ? await application.serveSecure(_securityContext(), port: 0)
            : await application.serve(port: 0);
        final client = HttpClient()..badCertificateCallback = (_, _, _) => true;
        addTearDown(() async {
          client.close(force: true);
          await server.close(force: true);
        });

        final socket = await WebSocket.connect(
          '${secure ? 'wss' : 'ws'}://${server.address.address}:${server.port}/chat',
          customClient: client,
          compression: CompressionOptions.compressionOff,
        );
        final messages = StreamIterator<Object?>(socket);
        socket.add('hello');
        expect(await messages.moveNext().timeout(_testTimeout), isTrue);
        expect(messages.current, 'hello');
        socket.add(<int>[1, 2, 3]);
        expect(await messages.moveNext().timeout(_testTimeout), isTrue);
        expect(messages.current, <int>[1, 2, 3]);
        expect(socket.protocol, isNull);
        expect(sessions, hasLength(1));

        await socket.close(WebSocketStatus.normalClosure);
        await messages.cancel();
        await _waitUntil(() => sessions.isEmpty);
      }
    });

    test('should preserve application headers and configure compression', () async {
      final application = Inlet()
        ..get('/default', (_, _) {
          return Response.webSocket(
            headers: const Headers.empty().set('x-application', 'chat'),
            onConnect: (_) {},
          );
        })
        ..get('/compressed', (_, _) {
          return Response.webSocket(
            compression: CompressionOptions.compressionDefault,
            onConnect: (_) {},
          );
        });
      final server = await application.serve(port: 0);
      addTearDown(() => server.close(force: true));

      final ordinary = await _handshake(server, '/default', offerCompression: true);
      final compressed = await _handshake(server, '/compressed', offerCompression: true);

      expect(ordinary.statusCode, HttpStatus.switchingProtocols);
      expect(ordinary.headers['x-application'], 'chat');
      expect(ordinary.headers[HttpHeaders.contentTypeHeader], isNull);
      expect(ordinary.headers['sec-websocket-extensions'], isNull);
      expect(compressed.headers['sec-websocket-extensions'], contains('permessage-deflate'));
    });

    test('should reject invalid handshakes before connecting', () async {
      var callbackCalls = 0;
      final reports = <Object>[];
      final application =
          Inlet(
              onReportError: (error, _) => reports.add(error),
            )
            ..get('/chat', (_, _) {
              return Response.webSocket(onConnect: (_) => callbackCalls++);
            })
            ..post('/chat', (_, _) {
              return Response.webSocket(onConnect: (_) => callbackCalls++);
            });
      final server = await application.serve(port: 0);
      addTearDown(() => server.close(force: true));

      final missingHeaders = await _request(server, 'GET', '/chat');
      final wrongMethod = await _request(server, 'POST', '/chat');

      expect(missingHeaders.statusCode, HttpStatus.badRequest);
      expect(await missingHeaders.drain<List<int>>(<int>[]), isEmpty);
      expect(wrongMethod.statusCode, HttpStatus.badRequest);
      expect(await wrongMethod.drain<List<int>>(<int>[]), isEmpty);
      expect(callbackCalls, 0);
      expect(reports, isEmpty);
    });

    test('should let origin policy reject before upgrading', () async {
      var callbackCalls = 0;
      final application = Inlet()
        ..get('/chat', (_, request) {
          if (request.headers['origin'] != 'https://app.example.com') {
            return Response.empty(status: HttpStatus.forbidden);
          }
          return Response.webSocket(onConnect: (_) => callbackCalls++);
        });
      final server = await application.serve(port: 0);
      addTearDown(() => server.close(force: true));

      await expectLater(
        WebSocket.connect(
          'ws://${server.address.address}:${server.port}/chat',
          headers: {'origin': 'https://attacker.example.com'},
        ),
        throwsA(
          isA<WebSocketException>().having(
            (error) => error.httpStatusCode,
            'status',
            HttpStatus.forbidden,
          ),
        ),
      );
      expect(callbackCalls, 0);
    });

    test('should close normally when the session callback completes', () async {
      final application = Inlet()
        ..get('/once', (_, _) {
          return Response.webSocket(
            onConnect: (socket) async {
              final message = await socket.first;
              socket.add(message);
            },
          );
        });
      final server = await application.serve(port: 0);
      addTearDown(() => server.close(force: true));
      final socket = await WebSocket.connect(
        'ws://${server.address.address}:${server.port}/once',
      );
      final messages = StreamIterator<Object?>(socket);

      socket.add('one');
      expect(await messages.moveNext().timeout(_testTimeout), isTrue);
      expect(messages.current, 'one');
      expect(await messages.moveNext().timeout(_testTimeout), isFalse);

      expect(socket.closeCode, WebSocketStatus.normalClosure);
    });

    test('should report callback failure and close with 1011', () async {
      final failure = StateError('session failed');
      final reports = <Object>[];
      var hookCalls = 0;
      final application =
          Inlet(
            onError: (_, _, _, _) {
              hookCalls++;
              return Response.text('replacement');
            },
            onReportError: (error, _) => reports.add(error),
          )..get('/fail', (_, _) {
            return Response.webSocket(onConnect: (_) => throw failure);
          });
      final server = await application.serve(port: 0);
      addTearDown(() => server.close(force: true));
      final socket = await WebSocket.connect(
        'ws://${server.address.address}:${server.port}/fail',
      );

      await socket.drain<void>().timeout(_testTimeout);

      expect(socket.closeCode, WebSocketStatus.internalServerError);
      expect(reports, [same(failure)]);
      expect(hookCalls, 0);
    });

    test('should reject oversized incoming frames', () async {
      final acceptedFrame = Completer<Object?>();
      final application =
          Inlet(
            onReportError: (_, _) {},
          )..get('/limited', (_, _) {
            return Response.webSocket(
              maxFrameBytes: 4,
              onConnect: (socket) async {
                await for (final message in socket) {
                  if (!acceptedFrame.isCompleted) {
                    acceptedFrame.complete(message);
                  }
                }
              },
            );
          });
      final server = await application.serve(port: 0);
      addTearDown(() => server.close(force: true));
      final socket = await WebSocket.connect(
        'ws://${server.address.address}:${server.port}/limited',
      );

      socket.add('1234');
      expect(await acceptedFrame.future.timeout(_testTimeout), '1234');
      socket.add('12345');
      await socket.drain<void>().timeout(_testTimeout);

      expect(socket.closeCode, WebSocketStatus.protocolError);
    });

    test('should recover preflight failures once and reject recursive upgrades', () async {
      var hookCalls = 0;
      final reports = <Object>[];
      final recovered = Inlet(
        onError: (_, _, _, _) {
          hookCalls++;
          return Response.empty(status: 418);
        },
        onReportError: (error, _) => reports.add(error),
      )..get('/chat', (_, _) => Response.webSocket(onConnect: (_) {}));
      final recoveredServer = await recovered.serve(port: 0);
      addTearDown(() => recoveredServer.close(force: true));

      final replacement = await _request(recoveredServer, 'GET', '/chat');
      expect(replacement.statusCode, 418);
      expect(hookCalls, 1);
      expect(reports, isEmpty);

      final recursive = Inlet(
        onError: (_, _, _, _) {
          return Response.webSocket(onConnect: (_) {});
        },
        onReportError: (error, _) => reports.add(error),
      )..post('/chat', (_, _) => Response.webSocket(onConnect: (_) {}));
      final recursiveServer = await recursive.serve(port: 0);
      addTearDown(() => recursiveServer.close(force: true));

      final rejected = await _request(recursiveServer, 'POST', '/chat');
      expect(rejected.statusCode, HttpStatus.internalServerError);
      expect(await rejected.drain<List<int>>(<int>[]), isEmpty);
    });

    test('should recover SDK failures before the handshake commits', () async {
      Object? recoveredError;
      final reports = <Object>[];
      final application =
          Inlet(
            onError: (_, _, error, _) {
              recoveredError = error;
              return Response.empty(status: HttpStatus.badGateway);
            },
            onReportError: (error, _) => reports.add(error),
          )..get('/chat', (_, _) {
            return Response.webSocket(onConnect: (_) {});
          });
      final server = await application.serve(port: 0);
      addTearDown(() => server.close(force: true));

      final response = await _handshake(
        server,
        '/chat',
        extensionHeader: 'permessage-deflate; x="',
      );

      expect(response.statusCode, HttpStatus.badGateway);
      expect(recoveredError, isA<HttpException>());
      expect(reports, [same(recoveredError)]);
    });

    test('should call an asynchronous selector once with immutable empty offers', () async {
      var selectorCalls = 0;
      var sessionCalls = 0;
      final application = Inlet()
        ..get('/chat', (_, _) {
          return Response.webSocket(
            selectProtocol: (offered) async {
              selectorCalls++;
              expect(offered, isEmpty);
              expect(() => offered.add('chat.v1'), throwsUnsupportedError);
              await Future<void>.delayed(Duration.zero);
              return null;
            },
            onConnect: (_) => sessionCalls++,
          );
        });
      final server = await application.serve(port: 0);
      addTearDown(() => server.close(force: true));

      final socket = await WebSocket.connect(
        'ws://${server.address.address}:${server.port}/chat',
      );
      await socket.drain<void>().timeout(_testTimeout);

      expect(socket.protocol, isNull);
      expect(selectorCalls, 1);
      expect(sessionCalls, 1);
    });

    test('should negotiate one offered subprotocol from the ordered list', () async {
      List<String>? receivedOffers;
      final application = Inlet()
        ..get('/chat', (_, _) {
          return Response.webSocket(
            selectProtocol: (offered) {
              receivedOffers = offered;
              return 'chat.v1';
            },
            onConnect: (_) {},
          );
        });
      final server = await application.serve(port: 0);
      addTearDown(() => server.close(force: true));

      final socket = await WebSocket.connect(
        'ws://${server.address.address}:${server.port}/chat',
        protocols: ['chat.v2', 'chat.v1', 'other'],
      );
      await socket.drain<void>().timeout(_testTimeout);

      expect(receivedOffers, ['chat.v2', 'chat.v1', 'other']);
      expect(socket.protocol, 'chat.v1');
    });

    test('should upgrade with no subprotocol after a null selection', () async {
      final application = Inlet()
        ..get('/chat', (_, _) {
          return Response.webSocket(
            selectProtocol: (_) => null,
            onConnect: (_) {},
          );
        })
        ..get('/without-selector', (_, _) {
          return Response.webSocket(onConnect: (_) {});
        });
      final server = await application.serve(port: 0);
      addTearDown(() => server.close(force: true));

      final socket = await WebSocket.connect(
        'ws://${server.address.address}:${server.port}/chat',
        protocols: ['chat.v1'],
      );
      await socket.drain<void>().timeout(_testTimeout);

      expect(socket.protocol, isNull);

      final withoutSelector = await WebSocket.connect(
        'ws://${server.address.address}:${server.port}/without-selector',
        protocols: ['chat.v1'],
      );
      await withoutSelector.drain<void>().timeout(_testTimeout);
      expect(withoutSelector.protocol, isNull);
    });

    test('should reject empty and invalid offered protocol tokens', () async {
      var selectorCalls = 0;
      var sessionCalls = 0;
      final application = Inlet()
        ..get('/chat', (_, _) {
          return Response.webSocket(
            selectProtocol: (_) {
              selectorCalls++;
              return null;
            },
            onConnect: (_) => sessionCalls++,
          );
        });
      final server = await application.serve(port: 0);
      addTearDown(() => server.close(force: true));

      for (final offered in [
        ['chat.v1,,chat.v2'],
        ['chat.v1, bad protocol'],
        ['chat.v1', ''],
      ]) {
        final response = await _handshake(
          server,
          '/chat',
          protocolHeaders: offered,
        );
        expect(response.statusCode, HttpStatus.badRequest);
      }
      expect(selectorCalls, 0);
      expect(sessionCalls, 0);
    });

    test('should reject explicit and unoffered selector results', () async {
      for (final explicitRejection in [true, false]) {
        final reports = <Object>[];
        var sessionCalls = 0;
        final application =
            Inlet(
              onReportError: (error, _) => reports.add(error),
            )..get('/chat', (_, _) {
              return Response.webSocket(
                selectProtocol: (_) {
                  if (explicitRejection) {
                    throw const WebSocketException('chat.v1 is required');
                  }
                  return 'unoffered';
                },
                onConnect: (_) => sessionCalls++,
              );
            });
        final server = await application.serve(port: 0);
        addTearDown(() => server.close(force: true));

        final response = await _handshake(
          server,
          '/chat',
          protocolHeaders: ['chat.v1'],
        );

        expect(
          response.statusCode,
          explicitRejection ? HttpStatus.badRequest : HttpStatus.internalServerError,
        );
        expect(sessionCalls, 0);
        expect(reports, explicitRejection ? isEmpty : [isA<StateError>()]);
      }
    });

    test('should recover unexpected selector failure with captured request context', () async {
      final failure = StateError('selector failed');
      final reports = <Object>[];
      var sessionCalls = 0;
      final application =
          Inlet(
            onError: (_, request, error, _) {
              expect(request.uri.path, '/chat');
              expect(error, same(failure));
              return Response.empty(status: HttpStatus.badGateway);
            },
            onReportError: (error, _) => reports.add(error),
          )..get('/chat', (_, _) {
            return Response.webSocket(
              selectProtocol: (_) => throw failure,
              onConnect: (_) => sessionCalls++,
            );
          });
      final server = await application.serve(port: 0);
      addTearDown(() => server.close(force: true));

      final response = await _handshake(
        server,
        '/chat',
        protocolHeaders: ['chat.v1'],
      );

      expect(response.statusCode, HttpStatus.badGateway);
      expect(reports, [same(failure)]);
      expect(sessionCalls, 0);
    });

    test('should let the error hook customize an explicit selector rejection', () async {
      final reports = <Object>[];
      var sessionCalls = 0;
      final application =
          Inlet(
            onError: (_, _, error, _) {
              expect(error, isA<WebSocketException>());
              return Response.empty(status: HttpStatus.forbidden);
            },
            onReportError: (error, _) => reports.add(error),
          )..get('/chat', (_, _) {
            return Response.webSocket(
              selectProtocol: (_) {
                throw const WebSocketException('chat.v1 is required');
              },
              onConnect: (_) => sessionCalls++,
            );
          });
      final server = await application.serve(port: 0);
      addTearDown(() => server.close(force: true));

      final response = await _handshake(
        server,
        '/chat',
        protocolHeaders: ['chat.v2'],
      );

      expect(response.statusCode, HttpStatus.forbidden);
      expect(reports, isEmpty);
      expect(sessionCalls, 0);
    });

    test('should fall back to 500 when selector recovery fails', () async {
      final selectorFailure = StateError('selector failed');
      final hookFailure = StateError('hook failed');
      final reports = <Object>[];
      var sessionCalls = 0;
      final application =
          Inlet(
            onError: (_, _, _, _) => throw hookFailure,
            onReportError: (error, _) => reports.add(error),
          )..get('/chat', (_, _) {
            return Response.webSocket(
              selectProtocol: (_) => throw selectorFailure,
              onConnect: (_) => sessionCalls++,
            );
          });
      final server = await application.serve(port: 0);
      addTearDown(() => server.close(force: true));

      final response = await _handshake(
        server,
        '/chat',
        protocolHeaders: ['chat.v1'],
      );

      expect(response.statusCode, HttpStatus.internalServerError);
      expect(reports, [same(selectorFailure), same(hookFailure)]);
      expect(sessionCalls, 0);
    });
  });
}

const _testTimeout = Duration(seconds: 2);

SecurityContext _securityContext() => SecurityContext()
  ..useCertificateChainBytes(testCertificate.codeUnits)
  ..usePrivateKeyBytes(testPrivateKey.codeUnits);

Future<HttpClientResponse> _request(
  InletServer server,
  String method,
  String path,
) async {
  final client = HttpClient();
  final request = await client.openUrl(
    method,
    Uri.parse('http://${server.address.address}:${server.port}$path'),
  );
  final response = await request.close();
  client.close();
  return response;
}

Future<_Handshake> _handshake(
  InletServer server,
  String path, {
  bool offerCompression = false,
  String? extensionHeader,
  List<String>? protocolHeaders,
}) async {
  final client = HttpClient();
  final request = await client.get(server.address.address, server.port, path);
  request.headers
    ..set(HttpHeaders.connectionHeader, 'Upgrade')
    ..set(HttpHeaders.upgradeHeader, 'websocket')
    ..set('sec-websocket-key', 'dGhlIHNhbXBsZSBub25jZQ==')
    ..set('sec-websocket-version', '13');
  if (offerCompression || extensionHeader != null) {
    request.headers.set(
      'sec-websocket-extensions',
      extensionHeader ?? 'permessage-deflate; client_max_window_bits',
    );
  }
  if (protocolHeaders != null) {
    for (final value in protocolHeaders) {
      request.headers.add('sec-websocket-protocol', value);
    }
  }
  final response = await request.close();
  final headers = <String, String?>{
    'x-application': response.headers.value('x-application'),
    HttpHeaders.contentTypeHeader: response.headers.value(HttpHeaders.contentTypeHeader),
    'sec-websocket-extensions': response.headers.value('sec-websocket-extensions'),
    'sec-websocket-protocol': response.headers.value('sec-websocket-protocol'),
  };
  if (response.statusCode == HttpStatus.switchingProtocols) {
    final socket = await response.detachSocket();
    socket.destroy();
  } else {
    await response.drain<void>();
  }
  client.close(force: true);
  return _Handshake(response.statusCode, headers);
}

Future<void> _waitUntil(bool Function() condition) async {
  final deadline = DateTime.now().add(_testTimeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('Condition was not reached.', _testTimeout);
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

final class _Handshake {
  const _Handshake(this.statusCode, this.headers);

  final int statusCode;
  final Map<String, String?> headers;
}
