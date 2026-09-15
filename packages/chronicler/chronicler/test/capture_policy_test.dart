import 'package:chronicler/chronicler.dart';
import 'package:chrono_id/chrono_id.dart';
import 'package:context/context.dart';
import 'package:test/test.dart';

import 'support/exporter.dart';
import 'support/runtime.dart';

void main() {
  group('Chronicler capture policy', () {
    test('should drop logs before buffering when sampling is zero', () async {
      final exporter = TestExporter();
      final chronicler = Chronicler(
        appId: 'app',
        release: 'release',
        source: ChroniclerSource.server,
        exporter: exporter,
        options: const ChroniclerOptions(
          delivery: DeliveryOptions(maxBatchRecords: 1),
          sampling: SamplingOptions(logs: 0),
        ),
      );
      final context = Context().withChronicler(chronicler.recorder);

      context.logs.info('excluded', attributes: {'unsupported': Object()});
      await Future<void>.delayed(Duration.zero);

      expect(exporter.batches, isEmpty);
      expect(chronicler.diagnosticCounts[DiagnosticReason.sampledOut], BigInt.one);
      expect(chronicler.diagnosticCounts[DiagnosticReason.invalidRecord], isNull);
    });

    test('should apply default field redaction recursively before buffering', () async {
      final exporter = TestExporter();
      final chronicler = _chronicler(exporter: exporter);
      final context = Context().withChronicler(chronicler.recorder);

      context.logs.info(
        'created',
        attributes: {
          'AuthorizationHeader': {'nested': 'removed together'},
          'items': [
            {'access_token': 'secret'},
            {'safe': true},
          ],
        },
      );
      await Future<void>.delayed(Duration.zero);

      final attributes = (exporter.batches.single.records.single as LogRecord).payload.attributes;
      expect(attributes['AuthorizationHeader'], '[REDACTED]');
      expect(attributes['items'], [
        {'access_token': '[REDACTED]'},
        {'safe': true},
      ]);
    });

    test('should redact nested maps with erased generic types', () async {
      final exporter = TestExporter();
      final chronicler = _chronicler(exporter: exporter);
      chronicler.recorder.recordEvent(
        'event',
        properties: {
          'nested': <dynamic, dynamic>{'access_token': 'secret'},
        },
      );
      await Future<void>.delayed(Duration.zero);

      final event = exporter.batches.single.records.single as ProductEventRecord;
      expect(event.payload.properties['nested'], {'access_token': '[REDACTED]'});
    });

    test('should snapshot replaced, extended, and empty field rules', () async {
      final mutableTerms = <String>['custom'];
      final exporter = TestExporter();
      final chronicler = _chronicler(
        exporter: exporter,
        redaction: RedactionOptions(fieldTerms: mutableTerms),
        maxBatchRecords: 2,
      );
      mutableTerms.add('later');
      final context = Context().withChronicler(chronicler.recorder);

      context.logs.info('one', attributes: {'password': 'kept', 'customField': 'hidden'});
      context.logs.info('two', attributes: {'later': 'kept'});
      await Future<void>.delayed(Duration.zero);

      final records = exporter.batches.single.records.cast<LogRecord>().toList();
      expect(records.first.payload.attributes, {
        'password': 'kept',
        'customField': '[REDACTED]',
      });
      expect(records.last.payload.attributes['later'], 'kept');

      final noRulesExporter = TestExporter();
      final noRules = _chronicler(
        exporter: noRulesExporter,
        redaction: const RedactionOptions(fieldTerms: []),
      );
      Context()
          .withChronicler(noRules.recorder)
          .logs
          .info('none', attributes: {'password': 'kept'});
      await Future<void>.delayed(Duration.zero);
      expect(
        (noRulesExporter.batches.single.records.single as LogRecord).payload.attributes['password'],
        'kept',
      );
    });

    test('should run a modifying hook once and redact its introduced fields', () async {
      final exporter = TestExporter();
      var calls = 0;
      final chronicler = _chronicler(
        exporter: exporter,
        redaction: RedactionOptions(
          beforeRecord: (record) {
            calls++;
            final log = record as LogRecord;
            return log.copyWith(
              payload: log.payload.copyWith(
                message: '[REDACTED MESSAGE]',
                error: log.payload.error?.copyWith(message: '[REDACTED ERROR]'),
                attributes: {'newToken': 'secret'},
              ),
            );
          },
        ),
      );

      Context()
          .withChronicler(chronicler.recorder)
          .logs
          .error('original', error: StateError('original'));
      await Future<void>.delayed(Duration.zero);

      final record = exporter.batches.single.records.single as LogRecord;
      expect(calls, 1);
      expect(record.payload.message, '[REDACTED MESSAGE]');
      expect(record.payload.error?.message, '[REDACTED ERROR]');
      expect(record.payload.attributes['newToken'], '[REDACTED]');
    });

    test('should enforce complete-record size after hooks and field redaction', () async {
      final hookExporter = TestExporter();
      final hooked = _chronicler(
        exporter: hookExporter,
        maxRecordBytes: 512,
        redaction: RedactionOptions(
          beforeRecord: (record) {
            final log = record as LogRecord;
            return log.copyWith(payload: log.payload.copyWith(message: 'redacted'));
          },
        ),
      );
      Context().withChronicler(hooked.recorder).logs.info('x' * 1000);

      final fieldExporter = TestExporter();
      final fieldRedacted = _chronicler(
        exporter: fieldExporter,
        maxRecordBytes: 512,
      );
      Context()
          .withChronicler(fieldRedacted.recorder)
          .logs
          .info('redact field', attributes: {'token': 'x' * 400});
      await Future<void>.delayed(Duration.zero);

      expect(
        (hookExporter.batches.single.records.single as LogRecord).payload.message,
        'redacted',
      );
      expect(
        (fieldExporter.batches.single.records.single as LogRecord).payload.attributes,
        {'token': '[REDACTED]'},
      );
    });

    test('should contain null, throwing, invalid, and protected-field hook results', () async {
      Future<(TestExporter, Chronicler)> capture(
        ChroniclerRecord? Function(ChroniclerRecord) hook,
      ) async {
        final exporter = TestExporter();
        final chronicler = _chronicler(
          exporter: exporter,
          redaction: RedactionOptions(beforeRecord: hook),
        );
        Context().withChronicler(chronicler.recorder).logs.info('record');
        await Future<void>.delayed(Duration.zero);
        return (exporter, chronicler);
      }

      final dropped = await capture((_) => null);
      final failed = await capture((_) => throw StateError('sensitive'));
      final invalid = await capture((record) {
        final log = record as LogRecord;
        return log.copyWith(payload: log.payload.copyWith(attributes: {'value': Object()}));
      });
      final protected = await capture((record) {
        final log = record as LogRecord;
        return log.copyWith(
          envelope: log.envelope.copyWith(eventId: ChronoID.generate(prefix: 'evt')),
        );
      });

      expect(dropped.$1.batches, isEmpty);
      expect(dropped.$2.diagnosticCounts[DiagnosticReason.hookDropped], BigInt.one);
      expect(failed.$2.diagnosticCounts[DiagnosticReason.hookFailed], BigInt.one);
      expect(invalid.$2.diagnosticCounts[DiagnosticReason.invalidRecord], BigInt.one);
      expect(protected.$2.diagnosticCounts[DiagnosticReason.invalidRecord], BigInt.one);
    });

    test('should suppress same-runtime recording from inside a hook', () async {
      final exporter = TestExporter();
      late Context context;
      final chronicler = _chronicler(
        exporter: exporter,
        redaction: RedactionOptions(
          beforeRecord: (record) {
            context.logs.info('recursive');
            return record;
          },
        ),
      );
      context = Context().withChronicler(chronicler.recorder);

      context.logs.info('outer');
      await Future<void>.delayed(Duration.zero);

      expect(exporter.batches.single.records, hasLength(1));
      expect(chronicler.diagnosticCounts[DiagnosticReason.reentrantRecording], BigInt.one);
    });

    test('should sample ordinary events but not identity, errors, or metrics', () async {
      final exporter = TestExporter(acceptImmediately: true);
      final chronicler = _chronicler(
        exporter: exporter,
        sampling: const SamplingOptions(events: 0),
        maxBatchRecords: 3,
      );
      chronicler.recorder
        ..recordEvent('sampled-event')
        ..identify(anonymousId: 'anonymous', userId: 'user')
        ..recordError(StateError('failed'));
      chronicler.recorder.metrics.counter('count').add(1);
      await chronicler.flush();

      expect(exporter.batches.single.records, hasLength(3));
      expect(exporter.batches.single.records.whereType<IdentityLinkRecord>(), hasLength(1));
      expect(exporter.batches.single.records.whereType<ErrorRecord>(), hasLength(1));
      expect(exporter.batches.single.records.whereType<MetricRecord>(), hasLength(1));
      expect(chronicler.diagnosticCounts[DiagnosticReason.sampledOut], BigInt.one);
    });

    test('should allow identity removal and reject protected field changes', () async {
      final removingExporter = TestExporter();
      final removing = _chronicler(
        exporter: removingExporter,
        redaction: RedactionOptions(
          beforeRecord: (record) {
            final event = record as ProductEventRecord;
            return event.copyWith(envelope: event.envelope.copyWith(userId: null));
          },
        ),
      );
      removing.recorder.withIdentity(userId: 'external-user').recordEvent('event');
      await Future<void>.delayed(Duration.zero);
      expect(removingExporter.batches.single.records.single.envelope.userId, isNull);

      final adding = _chronicler(
        exporter: TestExporter(),
        redaction: RedactionOptions(
          beforeRecord: (record) {
            final event = record as ProductEventRecord;
            return event.copyWith(envelope: event.envelope.copyWith(userId: 'added'));
          },
        ),
      );
      adding.recorder.recordEvent('event');
      expect(adding.diagnosticCounts[DiagnosticReason.invalidRecord], BigInt.one);

      final metric = _chronicler(
        exporter: TestExporter(),
        redaction: RedactionOptions(
          beforeRecord: (record) {
            final value = record as MetricRecord;
            return value.copyWith(payload: value.payload.copyWith(name: 'changed'));
          },
        ),
      );
      metric.recorder.metrics.counter('original').add(1);
      await metric.flush();
      expect(metric.diagnosticCounts[DiagnosticReason.invalidRecord], BigInt.one);
    });

    test('should validate sensitive caller fields before redacting them', () {
      final exporter = TestExporter();
      final chronicler = _chronicler(exporter: exporter);

      Context()
          .withChronicler(chronicler.recorder)
          .logs
          .info('invalid', attributes: {'password': Object()});

      expect(exporter.batches, isEmpty);
      expect(chronicler.diagnosticCounts[DiagnosticReason.invalidRecord], BigInt.one);
    });
  });
}

Chronicler _chronicler({
  required TestExporter exporter,
  RedactionOptions redaction = const RedactionOptions(),
  SamplingOptions sampling = const SamplingOptions(),
  int maxBatchRecords = 1,
  int maxRecordBytes = 64 * 1024,
}) => closeAfterTest(
  Chronicler(
    appId: 'app',
    release: 'release',
    source: ChroniclerSource.server,
    exporter: exporter,
    options: ChroniclerOptions(
      delivery: DeliveryOptions(
        maxBatchRecords: maxBatchRecords,
        maxRecordBytes: maxRecordBytes,
      ),
      redaction: redaction,
      sampling: sampling,
    ),
  ),
  exporter,
);
