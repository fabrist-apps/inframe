import 'dart:convert';

import 'package:chronicler/chronicler.dart';
import 'package:test/test.dart';

void main() {
  group('ChroniclerCodec', () {
    test('should encode canonical batch framing and UTC microseconds', () {
      final record = LogRecord(
        envelope: RecordEnvelope(
          eventId: 'evt_000000000000000000000000',
          appId: 'app',
          release: 'release',
          source: ChroniclerSource.server,
          timestamp: DateTime.utc(2026, 9, 12, 10, 20, 30, 123, 456),
        ),
        payload: LogPayload(
          severity: LogSeverity.info,
          message: '',
          attributes: const {
            'z': 1,
            'a': {'b': true, 'a': false},
          },
        ),
      );
      const codec = ChroniclerCodec();

      final recordText = utf8.decode(codec.encodeRecord(record));
      final batchText = utf8.decode(codec.encodeBatch(ChroniclerBatch([record])));

      expect(recordText, contains('2026-09-12T10:20:30.123456Z'));
      expect(recordText.indexOf('"a"'), lessThan(recordText.indexOf('"z"')));
      expect(batchText.length - recordText.length, 32);
      expect(batchText, '{"records":[$recordText],"schemaVersion":1}');

      final decoded = codec.decodeRecord(codec.encodeRecord(record));
      expect(decoded, isA<Decoded<ChroniclerRecord>>());
      expect((decoded as Decoded<ChroniclerRecord>).value, record);
    });

    test('should keep every exported batch within configured bounds', () async {
      final records = List.generate(
        3,
        (index) => LogRecord(
          envelope: RecordEnvelope(
            eventId: 'evt_00000000000000000000000$index',
            appId: 'app',
            release: 'release',
            source: ChroniclerSource.server,
            timestamp: DateTime.utc(2026),
          ),
          payload: LogPayload(
            severity: LogSeverity.info,
            message: '$index',
          ),
        ),
      );
      const codec = ChroniclerCodec();
      final batch = ChroniclerBatch(records.take(2));

      expect(batch.records, hasLength(2));
      expect(codec.encodeBatch(batch).length, lessThan(512 * 1024));
      expect(codec.encodeRecord(records.first).length, lessThan(64 * 1024));
    });
  });
}
