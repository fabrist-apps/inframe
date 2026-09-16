import 'dart:convert';

import 'package:artificer_core/src/errors.dart';
import 'package:artificer_core/src/protocols/sse.dart';
import 'package:test/test.dart';

void main() {
  group('SseParser', () {
    test('should preserve split UTF-8, BOM, CRLF, multiline data and identifiers', () async {
      final bytes = utf8.encode(
        '\ufeff: comment\r\nid: first\revent: strange\r\ndata: café\ndata: two\nretry: 25\n\ndata: next\r\n\r\n',
      );
      final events = await SseParser()
          .decode(Stream.fromIterable(bytes.map((byte) => [byte])))
          .toList();
      expect(events.map((event) => event.data), ['café\ntwo', 'next']);
      expect(events.first.event, 'strange');
      expect(events.first.id, 'first');
      expect(events.last.id, 'first');
      expect(events.first.retry, 25);
      expect(SseEvent.fromJson(events.first.toJson()).data, 'café\ntwo');
    });

    test('should reject event byte limits without dropping any fragments', () async {
      final source = Stream.value(utf8.encode('data: abcdef\n\n'));
      expect(SseParser(maxEventBytes: 8).decode(source), emitsError(isA<ResponseLimitError>()));
    });

    test('should reject malformed UTF-8 and incomplete final frames', () async {
      expect(
        SseParser().decode(Stream.value([100, 97, 116, 97, 58, 255, 10, 10])),
        emitsError(isA<ProtocolError>()),
      );
      expect(
        SseParser().decode(Stream.value(utf8.encode('data: unfinished'))),
        emitsError(isA<ProtocolError>()),
      );
    });
  });
}
