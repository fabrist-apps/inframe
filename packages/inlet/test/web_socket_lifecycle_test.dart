import 'dart:async';
import 'dart:io';

import 'package:inlet/inlet.dart';
import 'package:test/test.dart';

void main() {
  group('Inlet WebSocket lifecycle', () {
    test('should close synchronous sessions and preserve application close reasons', () async {
      final failure = StateError('failed after close');
      final reports = <Object>[];
      var hookCalls = 0;
      final application =
          Inlet(
              onError: (_, _, _, _) {
                hookCalls++;
                return Response.empty();
              },
              onReportError: (error, _) => reports.add(error),
            )
            ..get('/sync', (_, _) => Response.webSocket(onConnect: (_) {}))
            ..get('/chosen', (_, _) {
              return Response.webSocket(
                onConnect: (socket) async {
                  await socket.close(4321, 'application choice');
                  throw failure;
                },
              );
            });
      final server = await application.serve(port: 0);
      addTearDown(() => server.close(force: true));

      final synchronous = await _connect(server, '/sync');
      await synchronous.drain<void>().timeout(_testTimeout);
      expect(synchronous.closeCode, WebSocketStatus.normalClosure);

      final chosen = await _connect(server, '/chosen');
      await chosen.drain<void>().timeout(_testTimeout);
      expect(chosen.closeCode, 4321);
      expect(chosen.closeReason, 'application choice');
      expect(reports, [same(failure)]);
      expect(hookCalls, 0);
    });

    test('should unwind middleware before the session and clean registries', () async {
      final transitions = <String>[];
      final registry = <String, WebSocket>{};
      final releases = {
        'normal': Completer<void>(),
        'failure': Completer<void>(),
      };
      final cleaned = {
        for (final outcome in ['peer', 'normal', 'failure']) outcome: Completer<void>(),
      };
      final sessionFailure = StateError('session failed');
      final reports = <Object>[];
      final application =
          Inlet(
              onReportError: (error, _) => reports.add(error),
            )
            ..use((context, request, next) async {
              transitions.add('middleware enter');
              final response = await next(context, request);
              transitions.add('middleware exit');
              return response;
            })
            ..get('/sessions/:outcome', (_, request) {
              final outcome = request.pathParameters['outcome']!;
              transitions.add('handler $outcome');
              return Response.webSocket(
                onConnect: (socket) async {
                  transitions.add('connect $outcome');
                  registry[outcome] = socket;
                  try {
                    switch (outcome) {
                      case 'peer':
                        await socket.drain<void>();
                      case 'normal':
                        await releases['normal']!.future;
                      case 'failure':
                        await releases['failure']!.future;
                        throw sessionFailure;
                    }
                  } finally {
                    registry.remove(outcome);
                    cleaned[outcome]!.complete();
                  }
                },
              );
            });
      final server = await application.serve(port: 0);
      addTearDown(() => server.close(force: true));

      final peer = await _connect(server, '/sessions/peer');
      await _waitUntil(() => registry.containsKey('peer'));
      expect(transitions.take(4), [
        'middleware enter',
        'handler peer',
        'middleware exit',
        'connect peer',
      ]);
      await peer.close(WebSocketStatus.normalClosure);
      await cleaned['peer']!.future.timeout(_testTimeout);
      expect(registry, isEmpty);

      final normal = await _connect(server, '/sessions/normal');
      await _waitUntil(() => registry.containsKey('normal'));
      releases['normal']!.complete();
      await normal.drain<void>().timeout(_testTimeout);
      await cleaned['normal']!.future.timeout(_testTimeout);
      expect(normal.closeCode, WebSocketStatus.normalClosure);
      expect(registry, isEmpty);

      final failed = await _connect(server, '/sessions/failure');
      await _waitUntil(() => registry.containsKey('failure'));
      releases['failure']!.complete();
      await failed.drain<void>().timeout(_testTimeout);
      await cleaned['failure']!.future.timeout(_testTimeout);
      expect(failed.closeCode, WebSocketStatus.internalServerError);
      expect(registry, isEmpty);
      expect(reports, [same(sessionFailure)]);
    });

    test('should keep pending sessions and ordinary requests independent', () async {
      final sessions = <String, WebSocket>{};
      final releases = <String, Completer<void>>{};
      final application = Inlet()
        ..get('/health', (_, _) => Response.text('ok'))
        ..get('/sessions/:id', (_, request) {
          final id = request.pathParameters['id']!;
          final release = releases[id] = Completer<void>();
          return Response.webSocket(
            onConnect: (socket) async {
              sessions[id] = socket;
              final messages = socket.listen(socket.add);
              try {
                await release.future;
              } finally {
                await messages.cancel();
                sessions.remove(id);
              }
            },
          );
        });
      final server = await application.serve(port: 0);
      addTearDown(() => server.close(force: true));

      final first = await _connect(server, '/sessions/first');
      final firstMessages = StreamIterator<Object?>(first);
      await _waitUntil(() => sessions.containsKey('first'));

      final health = await _request(server, '/health');
      expect(await health.transform(const SystemEncoding().decoder).join(), 'ok');

      final second = await _connect(server, '/sessions/second');
      final secondMessages = StreamIterator<Object?>(second);
      await _waitUntil(() => sessions.length == 2);

      first.add('first');
      second.add('second');
      expect(await firstMessages.moveNext().timeout(_testTimeout), isTrue);
      expect(firstMessages.current, 'first');
      expect(await secondMessages.moveNext().timeout(_testTimeout), isTrue);
      expect(secondMessages.current, 'second');

      releases['first']!.complete();
      expect(await firstMessages.moveNext().timeout(_testTimeout), isFalse);
      expect(first.closeCode, WebSocketStatus.normalClosure);
      expect(second.readyState, WebSocket.open);
      second.add('still open');
      expect(await secondMessages.moveNext().timeout(_testTimeout), isTrue);
      expect(secondMessages.current, 'still open');

      releases['second']!.complete();
      expect(await secondMessages.moveNext().timeout(_testTimeout), isFalse);
      expect(second.closeCode, WebSocketStatus.normalClosure);
      expect(sessions, isEmpty);
    });

    test('should leave upgraded sessions to the application during listener close', () async {
      for (final force in [false, true]) {
        final registry = <WebSocket>{};
        final cleaned = Completer<void>();
        final application = Inlet()
          ..get('/chat', (_, _) {
            return Response.webSocket(
              onConnect: (socket) async {
                registry.add(socket);
                try {
                  await socket.forEach(socket.add);
                } finally {
                  registry.remove(socket);
                  cleaned.complete();
                }
              },
            );
          });
        final server = await application.serve(port: 0);
        final client = await _connect(server, '/chat');
        final messages = StreamIterator<Object?>(client);
        await _waitUntil(() => registry.length == 1);

        await server.close(force: force).timeout(_testTimeout);
        expect(registry, hasLength(1));
        expect(client.readyState, WebSocket.open);
        client.add('after close');
        expect(await messages.moveNext().timeout(_testTimeout), isTrue);
        expect(messages.current, 'after close');

        final applicationClose = Future.wait(
          registry.map((socket) => socket.close(WebSocketStatus.goingAway, 'shutdown')),
        );
        expect(await messages.moveNext().timeout(_testTimeout), isFalse);
        await applicationClose.timeout(_testTimeout);
        await cleaned.future.timeout(_testTimeout);
        expect(client.closeCode, WebSocketStatus.goingAway);
        expect(client.closeReason, 'shutdown');
        expect(registry, isEmpty);
      }
    });
  });
}

const _testTimeout = Duration(seconds: 2);

Future<WebSocket> _connect(InletServer server, String path) => WebSocket.connect(
  'ws://${server.address.address}:${server.port}$path',
  compression: CompressionOptions.compressionOff,
);

Future<HttpClientResponse> _request(InletServer server, String path) async {
  final client = HttpClient();
  final request = await client.get(server.address.address, server.port, path);
  final response = await request.close();
  client.close();
  return response;
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
