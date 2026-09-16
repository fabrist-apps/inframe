import 'package:chronicler/chronicler.dart';
import 'package:conflux/result.dart';
import 'package:test/test.dart';

import 'support/records.dart';

void main() {
  setUpAll(Chronicler.initialize);
  group('Chronicler model schemas', () {
    test('should enforce the attribute snapshot byte budget', () {
      final record = testLogRecord('hello').copyWith(
        payload: LogPayload(
          severity: LogSeverity.info,
          message: 'hello',
          attributes: {'key': 'value'},
        ),
      );
      final schema = LogPayload.schema(
        maxRecordBytes: 4,
      );

      expect(schema.safeParse(record.payload.toMap()).isFailure, isTrue);
      expect(
        LogPayload.schema().safeParse(record.payload.toMap()).getOrNull(),
        equals(record.payload.toMap()),
      );
    });

    test('should reject duplicate property removal keys', () {
      final schema = UserPropertiesUnsetPayload.schema();

      expect(
        schema
            .safeParse(UserPropertiesUnsetPayload(userId: 'user', keys: ['name', 'name']).toMap())
            .isFailure,
        isTrue,
      );
      expect(
        schema
            .safeParse(UserPropertiesUnsetPayload(userId: 'user', keys: ['name']).toMap())
            .isSuccess,
        isTrue,
      );
    });

    test('should validate metric instrument rules independently of the codec', () {
      final payload = testMetricRecord().payload;
      final schema = MetricPayload.schema();

      expect(schema.safeParse(payload.copyWith(sum: -1).toMap()).isFailure, isTrue);
      expect(
        schema
            .safeParse(
              payload.copyWith(instrument: MetricInstrument.upDownCounter, sum: -1).toMap(),
            )
            .isSuccess,
        isTrue,
      );
    });

    test('should reject correlation on metric records through the composed schema', () {
      final record = testMetricRecord();
      final schema = ChroniclerRecord.schema();

      expect(schema.safeParse(record.toMap()).isSuccess, isTrue);
      expect(
        schema
            .safeParse(record.copyWith(envelope: record.envelope.copyWith(userId: 'user')).toMap())
            .isFailure,
        isTrue,
      );
    });
  });
}
