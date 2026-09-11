import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:inlet/inlet.dart';
import 'package:test/test.dart';

void main() {
  group('Inlet SSE delivery', () {
    test('should flush headers before waiting for the first event', () async {
      final events = StreamController<SseEvent>();
      final application = Inlet()..get('/events', (_, _) => Response.sse(events.stream));
      final server = await application.serve(port: 0);
      final wire = await _WireClient.connect(server);
      addTearDown(() async {
        await wire.close();
        await server.close(force: true);
        await events.close();
      });

      wire.send(
        'GET /events HTTP/1.1\r\n'
        'Host: ${server.address.address}:${server.port}\r\n'
        'Connection: close\r\n'
        '\r\n',
      );
      await wire.waitFor((text) => text.contains('\r\n\r\n'));

      expect(wire.text, contains('HTTP/1.1 200'));
      expect(
        wire.text.toLowerCase(),
        contains('content-type: text/event-stream; charset=utf-8'),
      );
      expect(wire.text.toLowerCase(), contains('cache-control: no-cache'));

      events.add(SseEvent(data: 'first'));
      await wire.waitFor((text) => text.contains('data: first\n\n'));
      expect(events.isClosed, isFalse);

      events.add(SseEvent(data: 'second'));
      await wire.waitFor((text) => text.contains('data: second\n\n'));
      await events.close();
      await wire.waitUntilDone();
    });

    test('should suppress HEAD without subscribing over HTTP', () async {
      var subscriptions = 0;
      final application = Inlet()
        ..get(
          '/events',
          (_, _) => Response.sse(
            Stream<SseEvent>.multi((controller) {
              subscriptions++;
              unawaited(controller.close());
            }),
          ),
        );
      final server = await application.serve(port: 0);
      final client = HttpClient();
      addTearDown(() async {
        client.close(force: true);
        await server.close(force: true);
      });

      final request = await client.head(server.address.address, server.port, '/events');
      final response = await request.close();
      await response.drain<void>();

      expect(response.statusCode, HttpStatus.ok);
      expect(response.headers.value(HttpHeaders.contentLengthHeader), isNull);
      expect(response.headers.value(HttpHeaders.transferEncodingHeader), isNull);
      expect(subscriptions, 0);
    });

    test('should deliver JSON events and comments over HTTP', () async {
      final application = Inlet()
        ..get(
          '/events',
          (_, _) => Response.sse(
            Stream.fromIterable([
              SseEvent.json(
                {'title': 'Ready'},
                event: 'document',
                id: 'event-1',
              ),
              SseEvent.comment('keep-alive'),
            ]),
          ),
        );
      final server = await application.serve(port: 0);
      final client = HttpClient();
      addTearDown(() async {
        client.close(force: true);
        await server.close(force: true);
      });

      final request = await client.get(
        server.address.address,
        server.port,
        '/events',
      );
      final response = await request.close();

      expect(
        await utf8.decodeStream(response),
        'event: document\n'
        'id: event-1\n'
        'data: {"title":"Ready"}\n'
        '\n'
        ': keep-alive\n'
        '\n',
      );
    });

    test('should pause the source until each event flush completes', () async {
      final transitions = <String>[];
      late StreamController<SseEvent> events;
      var delivered = 0;
      events = StreamController<SseEvent>(
        sync: true,
        onListen: () {
          delivered = 1;
          events.add(SseEvent(data: 'first'));
        },
        onPause: () => transitions.add('pause'),
        onResume: () {
          transitions.add('resume');
          if (delivered == 1) {
            delivered = 2;
            scheduleMicrotask(() => events.add(SseEvent(data: 'second')));
          } else {
            scheduleMicrotask(events.close);
          }
        },
      );
      final application = Inlet()..get('/events', (_, _) => Response.sse(events.stream));
      final server = await application.serve(port: 0);
      final wire = await _WireClient.connect(server);
      addTearDown(() async {
        await wire.close();
        await server.close(force: true);
        await events.close();
      });

      wire.send(
        'GET /events HTTP/1.1\r\n'
        'Host: ${server.address.address}:${server.port}\r\n'
        'Connection: close\r\n'
        '\r\n',
      );
      await wire.waitUntilDone();

      expect(wire.text, contains('data: first\n\n'));
      expect(wire.text, contains('data: second\n\n'));
      expect(transitions, ['pause', 'resume', 'pause', 'resume']);
    });

    test('should cancel a paused producer after client disconnect', () async {
      final paused = Completer<void>();
      final cancelled = Completer<void>();
      late Socket socket;
      late StreamController<SseEvent> events;
      events = StreamController<SseEvent>(
        sync: true,
        onListen: () => events.add(SseEvent(data: 'x' * (8 * 1024 * 1024))),
        onPause: () {
          paused.complete();
          socket.destroy();
        },
        onCancel: cancelled.complete,
      );
      final application = Inlet(
        onReportError: (_, _) {},
      )..get('/events', (_, _) => Response.sse(events.stream));
      final server = await application.serve(port: 0);
      addTearDown(() async {
        socket.destroy();
        await server.close(force: true);
        await events.close();
      });
      socket = await Socket.connect(server.address, server.port);

      await (socket..write(
            'GET /events HTTP/1.1\r\n'
            'Host: ${server.address.address}:${server.port}\r\n'
            '\r\n',
          ))
          .flush();

      await paused.future.timeout(const Duration(seconds: 2));
      await cancelled.future.timeout(const Duration(seconds: 2));
    });

    test('should report source failures after the header commit without recovery', () async {
      for (final emitEvent in [false, true]) {
        final failure = StateError(emitEvent ? 'after event' : 'before event');
        final reports = <Object>[];
        var hookCalls = 0;
        final cancelled = Completer<void>();
        late StreamController<SseEvent> events;
        events = StreamController<SseEvent>(
          onListen: () {
            if (emitEvent) {
              events.add(SseEvent(data: 'started'));
            }
            events.addError(failure);
          },
          onCancel: cancelled.complete,
        );
        final application = Inlet(
          onError: (_, _, _, _) {
            hookCalls++;
            return Response.text('replacement');
          },
          onReportError: (error, _) => reports.add(error),
        )..get('/events', (_, _) => Response.sse(events.stream));
        final server = await application.serve(port: 0);
        final wire = await _WireClient.connect(server);

        wire.send(
          'GET /events HTTP/1.1\r\n'
          'Host: ${server.address.address}:${server.port}\r\n'
          'Connection: close\r\n'
          '\r\n',
        );
        await wire.waitUntilDone();
        await cancelled.future.timeout(const Duration(seconds: 2));

        expect(reports, [same(failure)]);
        expect(hookCalls, 0);
        expect(wire.text, isNot(contains('replacement')));

        await wire.close();
        await server.close(force: true);
        await events.close();
      }
    });

    test('should recover a delivery failure before committing headers', () async {
      final reports = <Object>[];
      var hookCalls = 0;
      final application =
          Inlet(
            onError: (_, _, error, _) {
              hookCalls++;
              expect(error, isA<StateError>());
              return Response.text('replacement');
            },
            onReportError: (error, _) => reports.add(error),
          )..get('/events', (_, _) async {
            final response = Response.sse(Stream.value(SseEvent(data: 'consumed')));
            await response.body.drain<void>();
            return response;
          });
      final server = await application.serve(port: 0);
      final client = HttpClient();
      addTearDown(() async {
        client.close(force: true);
        await server.close(force: true);
      });

      final request = await client.get(
        server.address.address,
        server.port,
        '/events',
      );
      final response = await request.close();

      expect(await utf8.decodeStream(response), 'replacement');
      expect(hookCalls, 1);
      expect(reports, hasLength(1));
      expect(reports.single, isA<StateError>());
    });

    test('should cancel active delivery when listener close escalates to force', () async {
      final cancelled = Completer<void>();
      late StreamController<SseEvent> events;
      events = StreamController<SseEvent>(
        onListen: () => events.add(SseEvent(data: 'started')),
        onCancel: cancelled.complete,
      );
      final application = Inlet(
        onReportError: (_, _) {},
      )..get('/events', (_, _) => Response.sse(events.stream));
      final server = await application.serve(port: 0);
      final client = HttpClient();
      addTearDown(() async {
        client.close(force: true);
        await server.close(force: true);
        await events.close();
      });
      final request = await client.get(
        server.address.address,
        server.port,
        '/events',
      );
      final response = await request.close();
      final firstEvent = Completer<void>();
      response.listen(
        (_) => firstEvent.complete(),
        onError: (_, _) {},
      );
      await firstEvent.future;

      final normalClose = server.close();
      await normalClose.timeout(const Duration(seconds: 2));
      expect(cancelled.isCompleted, isFalse);
      expect(server.close(force: true), same(normalClose));

      await cancelled.future.timeout(const Duration(seconds: 2));
    });
  });
}

final class _WireClient {
  _WireClient._(this._socket) {
    _socket.listen(
      (chunk) {
        _bytes.addAll(chunk);
        if (!_changed.isCompleted) {
          _changed.complete();
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!_changed.isCompleted) {
          _changed.completeError(error, stackTrace);
        }
      },
      onDone: () {
        _done = true;
        if (!_changed.isCompleted) {
          _changed.complete();
        }
      },
    );
  }

  static Future<_WireClient> connect(InletServer server) async =>
      _WireClient._(await Socket.connect(server.address, server.port));

  final Socket _socket;
  final List<int> _bytes = [];
  Completer<void> _changed = Completer<void>();
  bool _done = false;

  String get text => latin1.decode(_bytes);

  void send(String value) {
    _socket.add(latin1.encode(value));
    unawaited(_socket.flush());
  }

  Future<void> waitFor(bool Function(String value) predicate) async {
    while (!predicate(text)) {
      if (_done) {
        fail('Connection closed before the expected response arrived:\n$text');
      }
      final changed = _changed;
      await changed.future.timeout(const Duration(seconds: 2));
      if (identical(changed, _changed)) {
        _changed = Completer<void>();
      }
    }
  }

  Future<void> waitUntilDone() async {
    while (!_done) {
      final changed = _changed;
      await changed.future.timeout(const Duration(seconds: 2));
      if (identical(changed, _changed)) {
        _changed = Completer<void>();
      }
    }
  }

  Future<void> close() => _socket.close();
}
