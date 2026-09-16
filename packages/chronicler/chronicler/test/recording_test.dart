import 'package:chronicler/chronicler.dart';
import 'package:context/context.dart';
import 'package:test/test.dart';

import 'support/exporter.dart';

void main() {
  setUpAll(Chronicler.initialize);
  group('Chronicler recording', () {
    test('should expose all log severities with immutable captured values', () async {
      final exporter = TestExporter();
      final chronicler = Chronicler(
        appId: 'app-external',
        release: '1.2.3',
        buildId: 'build-4',
        source: ChroniclerSource.server,
        exporter: exporter,
        options: const ChroniclerOptions(
          delivery: DeliveryOptions(maxBatchRecords: 4),
        ),
      );
      final context = Context().withChronicler(chronicler.recorder);
      final nested = <String, Object?>{
        'items': <Object?>[
          1,
          {'secret': 'later'},
        ],
      };

      context.logs.debug('debug', attributes: nested);
      context.logs.info('info');
      context.logs.warning('warning', stackTrace: StackTrace.fromString('standalone'));
      context.logs.error(
        'error',
        error: StateError('failed'),
        stackTrace: StackTrace.fromString('error-stack'),
      );
      (nested['items']! as List<Object?>).add(2);

      await Future<void>.delayed(Duration.zero);
      final records = exporter.batches.single.records.cast<LogRecord>().toList();
      expect(records.map((record) => record.payload.severity), LogSeverity.values);
      expect(records.first.envelope.appId, 'app-external');
      expect(records.first.envelope.buildId, 'build-4');
      expect(records.first.envelope.eventId, startsWith('evt_'));
      expect(records.first.payload.attributes['items'], hasLength(2));
      expect(records[2].payload.stackTrace, 'standalone');
      expect(records[3].payload.error?.message, 'Bad state: failed');
      expect(records[3].payload.error?.stackTrace, 'error-stack');
      expect(records[3].payload.stackTrace, isNull);
      expect(() => exporter.batches.single.records.add(records.first), throwsUnsupportedError);
      expect(
        () => (records.first.payload.attributes['items']! as List<Object?>).add(2),
        throwsUnsupportedError,
      );
    });

    test('should throw MissingContextValue when setup is absent', () {
      expect(() => Context().logs, throwsA(isA<MissingContextValue>()));
    });

    test('should reject invalid setup without exposing supplied values', () {
      expect(
        () => Chronicler(
          appId: 'secret-invalid-value',
          release: 'release',
          source: ChroniclerSource.server,
          exporter: TestExporter(),
          options: const ChroniclerOptions(
            delivery: DeliveryOptions(maxPendingRecords: 0),
          ),
        ),
        throwsA(
          isA<ChroniclerConfigurationException>()
              .having((error) => error.setting, 'setting', 'maxPendingRecords')
              .having(
                (error) => error.toString(),
                'message',
                isNot(contains('secret-invalid-value')),
              ),
        ),
      );
    });
  });
}
