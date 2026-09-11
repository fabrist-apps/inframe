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
