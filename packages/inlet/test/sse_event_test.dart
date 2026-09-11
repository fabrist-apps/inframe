import 'dart:convert';
import 'dart:io';

import 'package:inlet/inlet.dart';
import 'package:test/test.dart';

void main() {
  group('SseEvent', () {
    test('should encode event metadata and multiline data exactly', () async {
      final response = Response.sse(
        Stream.value(
          SseEvent(
            data: 'first 😀\r\n\rsecond\n',
            event: '',
            id: '',
            retry: const Duration(milliseconds: 1500),
          ),
        ),
      );
      addTearDown(response.close);

      expect(
        await response.text(),
        'event:\n'
        'id:\n'
        'retry: 1500\n'
        'data: first 😀\n'
        'data:\n'
        'data: second\n'
        'data:\n'
        '\n',
      );
    });

    test('should snapshot JSON before caller mutation', () async {
      final document = <String, Object?>{
        'items': <Object?>[
          <String, Object?>{'title': 'Ready'},
        ],
      };
      final event = SseEvent.json(
        document,
        event: 'document',
        id: 'event-1',
      );
      (document['items']! as List<Object?>).clear();
      final response = Response.sse(Stream.value(event));
      addTearDown(response.close);

      expect(
        await response.text(),
        'event: document\n'
        'id: event-1\n'
        'data: {"items":[{"title":"Ready"}]}\n'
        '\n',
      );
    });

    test('should reject invalid event names and IDs', () {
      for (final invalid in ['line\rbreak', 'line\nbreak', 'nul\u0000value']) {
        expect(() => SseEvent(data: 'value', event: invalid), throwsArgumentError);
        expect(() => SseEvent(data: 'value', id: invalid), throwsArgumentError);
      }

      expect(() => SseEvent(data: 'value', event: '', id: ''), returnsNormally);
    });

    test('should accept only nonnegative whole-millisecond retries', () {
      expect(
        () => SseEvent(data: 'value', retry: Duration.zero),
        returnsNormally,
      );
      expect(
        () => SseEvent(
          data: 'value',
          retry: const Duration(milliseconds: 1),
        ),
        returnsNormally,
      );
      expect(
        () => SseEvent(
          data: 'value',
          retry: const Duration(microseconds: -1),
        ),
        throwsArgumentError,
      );
      expect(
        () => SseEvent(
          data: 'value',
          retry: const Duration(microseconds: 1),
        ),
        throwsArgumentError,
      );
    });

    test('should encode single-line comments exactly', () async {
      final response = Response.sse(
        Stream.fromIterable([
          SseEvent.comment('keep-alive'),
          SseEvent.comment(''),
        ]),
      );
      addTearDown(response.close);

      expect(
        await response.body.map(utf8.decode).toList(),
        [': keep-alive\n\n', ':\n\n'],
      );
      expect(() => SseEvent.comment('two\nlines'), throwsArgumentError);
      expect(() => SseEvent.comment('two\rlines'), throwsArgumentError);
    });

    test('should route JSON construction failures through the handler boundary', () async {
      final cyclic = <Object?>[];
      cyclic.add(cyclic);
      final application = Inlet(
        onReportError: (_, _) {},
      )..get('/events', (_, _) => Response.sse(Stream.value(SseEvent.json(cyclic))));
      final request = Request(method: 'GET', uri: Uri.parse('/events'));
      final response = await application.handle(request);
      addTearDown(() async {
        await response.close();
        await request.close();
      });

      expect(response.statusCode, HttpStatus.internalServerError);
      expect(await response.bytes(), isEmpty);
    });
  });
}
