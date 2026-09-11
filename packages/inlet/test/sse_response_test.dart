import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:inlet/inlet.dart';
import 'package:test/test.dart';

void main() {
  group('Response.sse', () {
    test('should lazily deliver complete text events in process', () async {
      var subscriptions = 0;
      final events = Stream<SseEvent>.multi((controller) {
        subscriptions++;
        controller
          ..add(SseEvent(data: 'first\r\nsecond'))
          ..add(SseEvent(data: ''));
        unawaited(controller.close());
      });
      final application = Inlet()..get('/events', (_, _) => Response.sse(events));
      final request = Request(method: 'GET', uri: Uri.parse('/events'));

      final response = await application.handle(request);
      addTearDown(() async {
        await response.close();
        await request.close();
      });

      expect(subscriptions, 0);
      expect(response.statusCode, HttpStatus.ok);
      expect(response.headers['content-type'], 'text/event-stream; charset=utf-8');
      expect(response.headers['cache-control'], 'no-cache');
      expect(
        await response.body.map(utf8.decode).toList(),
        ['data: first\ndata: second\n\n', 'data:\n\n'],
      );
      expect(subscriptions, 1);
    });

    test('should preserve SSE policy and its body owner through header views', () async {
      final response = Response.sse(
        Stream.value(SseEvent(data: 'value')),
        headers: const Headers.empty()
            .set(HttpHeaders.contentTypeHeader, 'application/example')
            .set(HttpHeaders.cacheControlHeader, 'private'),
      );
      final view = response.withHeaders(const Headers.empty().set('x-view', 'yes'));
      addTearDown(view.close);

      expect(response.statusCode, HttpStatus.ok);
      expect(response.headers['content-type'], 'text/event-stream; charset=utf-8');
      expect(response.headers['cache-control'], 'private');
      expect(view.headers['content-type'], 'text/event-stream; charset=utf-8');
      expect(view.headers['cache-control'], 'no-cache');
      expect(view.headers['x-view'], 'yes');
      expect(await view.text(), 'data: value\n\n');
      expect(() => response.body.listen(null), throwsStateError);
      expect(response.close(), same(view.close()));
    });

    test('should reject content encoding and transport-owned headers', () {
      for (final name in [
        HttpHeaders.contentEncodingHeader,
        HttpHeaders.contentLengthHeader,
        HttpHeaders.transferEncodingHeader,
        HttpHeaders.connectionHeader,
        'keep-alive',
        'proxy-connection',
        HttpHeaders.trailerHeader,
        HttpHeaders.upgradeHeader,
      ]) {
        final headers = const Headers.empty().set(name, 'value');
        expect(
          () => Response.sse(const Stream.empty(), headers: headers),
          throwsArgumentError,
        );
        final response = Response.sse(const Stream.empty());
        addTearDown(response.close);
        expect(() => response.withHeaders(headers), throwsArgumentError);
      }
    });

    test('should suppress HEAD without subscribing to the event source', () async {
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
      final request = Request(method: 'HEAD', uri: Uri.parse('/events'));
      final response = await application.handle(request);
      final view = response.withHeaders(const Headers.empty().set('x-view', 'yes'));

      expect(await view.body.toList(), isEmpty);
      expect(subscriptions, 0);
      expect(response.close(), same(view.close()));
      await response.close();
      await request.close();
      expect(subscriptions, 0);
    });

    test('should close an untouched response without acquiring resources', () async {
      var subscriptions = 0;
      final response = Response.sse(
        Stream<SseEvent>.multi((controller) {
          subscriptions++;
          unawaited(controller.close());
        }),
      );

      final firstClose = response.close();
      expect(response.close(), same(firstClose));
      await firstClose;

      expect(subscriptions, 0);
    });
  });
}
