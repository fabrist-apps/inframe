import 'dart:convert';

import 'package:chronicler/chronicler.dart';
import 'package:conflux/moment.dart';
import 'package:conflux/result.dart';
import 'package:test/test.dart';

import 'support/moments.dart';

void main() {
  group('ChroniclerCodec', () {
    test('should encode canonical batch framing and UTC microseconds', () {
      final record = LogRecord(
        envelope: RecordEnvelope(
          eventId: 'evt_000000000000000000000000',
          appId: 'app',
          release: 'release',
          source: ChroniclerSource.server,
          timestamp: utcMoment(2026, 9, 12, 10, 20, 30, 123, 456),
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

    test('should serialize offset Moments as UTC and decode Moment timestamps', () {
      final timestamp = Moment.parse('2026-09-12T15:50:30.123456+05:30')
          .getOrThrowWith((error) => StateError('$error'));
      final record = LogRecord(
        envelope: RecordEnvelope(
          eventId: 'evt_000000000000000000000000',
          appId: 'app',
          release: 'release',
          source: ChroniclerSource.server,
          timestamp: timestamp,
        ),
        payload: LogPayload(severity: LogSeverity.info, message: 'offset'),
      );
      const codec = ChroniclerCodec();

      final encoded = codec.encodeRecord(record);
      final map = jsonDecode(utf8.decode(encoded)) as Map<String, Object?>;
      expect(map['timestamp'], '2026-09-12T10:20:30.123456Z');
      final decoded = codec.decodeRecord(encoded);
      expect(decoded, isA<Decoded<ChroniclerRecord>>());
      expect(
        (decoded as Decoded<ChroniclerRecord>).value.envelope.timestamp,
        timestamp.toUtc(),
      );
    });

    test('should enforce exact encoded record and batch byte bounds', () {
      final records = List.generate(
        3,
        (index) => LogRecord(
          envelope: RecordEnvelope(
            eventId: 'evt_00000000000000000000000$index',
            appId: 'app',
            release: 'release',
            source: ChroniclerSource.server,
            timestamp: utcMoment(2026),
          ),
          payload: LogPayload(
            severity: LogSeverity.info,
            message: '$index',
          ),
        ),
      );
      const codec = ChroniclerCodec();
      final batch = ChroniclerBatch(records.take(2));

      final recordBytes = codec.encodeRecord(records.first).length;
      final batchBytes = codec.encodeBatch(batch).length;
      expect(
        ChroniclerCodec(maxRecordBytes: recordBytes).encodeRecord(records.first),
        hasLength(recordBytes),
      );
      expect(
        () => ChroniclerCodec(maxRecordBytes: recordBytes - 1).encodeRecord(records.first),
        throwsA(isA<ChroniclerEncodingException>()),
      );
      expect(ChroniclerCodec(maxBatchBytes: batchBytes).encodeBatch(batch), hasLength(batchBytes));
      expect(
        () => ChroniclerCodec(maxBatchBytes: batchBytes - 1).encodeBatch(batch),
        throwsA(isA<ChroniclerEncodingException>()),
      );
    });
  });
}
