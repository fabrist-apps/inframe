import 'package:chronicler/chronicler.dart';
import 'package:chronicler/src/runtime.dart'
    show ChroniclerCaptureFixture, ChroniclerDeliveryFixture;
import 'package:context/context.dart';
import 'package:test/test.dart';

import 'support/async.dart';
import 'support/exporter.dart';
import 'support/records.dart';
import 'support/runtime.dart';

void main() {
  group('Chronicler collection controls', () {
    test('disabled logs never enter delivery and toggles are independent', () async {
      final exporter = TestExporter();
      final chronicler = _chronicler(exporter);

      expect(chronicler.isCollectionEnabled(ChroniclerSignal.logs), isTrue);
      expect(ChroniclerDeliveryFixture.propagationEnabled(chronicler), isTrue);
      chronicler
        ..setCollectionEnabled(ChroniclerSignal.logs, false)
        ..setCollectionEnabled(ChroniclerSignal.logs, false)
        ..setPropagationEnabled(false);
      Context().withChronicler(chronicler.recorder).logs.info('disabled');

      expect(chronicler.isCollectionEnabled(ChroniclerSignal.logs), isFalse);
      expect(chronicler.isCollectionEnabled(ChroniclerSignal.events), isTrue);
      expect(ChroniclerDeliveryFixture.propagationEnabled(chronicler), isFalse);
      expect(exporter.batches, isEmpty);
      expect(chronicler.diagnosticCounts[DiagnosticReason.collectionDisabled], BigInt.one);
    });

    test('disabling a signal discards its queue and leaves other signals', () async {
      final exporter = TestExporter();
      final chronicler = _chronicler(
        exporter,
        maxBatchRecords: 2,
        batchInterval: const Duration(seconds: 1),
      );
      Context().withChronicler(chronicler.recorder).logs.info('discard');
      ChroniclerCaptureFixture.capture(chronicler, _event('kept-one'));

      chronicler.setCollectionEnabled(ChroniclerSignal.logs, false);
      ChroniclerCaptureFixture.capture(chronicler, _event('kept-two'));
      await waitForCondition(() => exporter.attempts.length == 1);

      expect(exporter.batches.single.records.map((record) => record.kind), [
        'event',
        'event',
      ]);
      expect(chronicler.diagnosticCounts[DiagnosticReason.collectionDisabled], BigInt.one);
    });

    test('identity and property operations use the events switch', () {
      final exporter = TestExporter();
      final chronicler = _chronicler(exporter)
        ..setCollectionEnabled(ChroniclerSignal.events, false);

      for (final record in [_identity(), _propertiesSet(), _propertiesUnset()]) {
        ChroniclerCaptureFixture.capture(chronicler, record);
      }

      expect(exporter.batches, isEmpty);
      expect(chronicler.diagnosticCounts[DiagnosticReason.collectionDisabled], BigInt.from(3));
      expect(chronicler.isCollectionEnabled(ChroniclerSignal.logs), isTrue);
      expect(ChroniclerDeliveryFixture.propagationEnabled(chronicler), isTrue);
    });

    test('each signal switch uses the record signal classification', () {
      for (final entry in <ChroniclerSignal, ChroniclerRecord>{
        ChroniclerSignal.logs: _log(),
        ChroniclerSignal.events: _event('event'),
        ChroniclerSignal.traces: _span(),
        ChroniclerSignal.errors: _error(),
        ChroniclerSignal.metrics: testMetricRecord(),
      }.entries) {
        final exporter = TestExporter();
        final chronicler = _chronicler(exporter)..setCollectionEnabled(entry.key, false);

        ChroniclerCaptureFixture.capture(chronicler, entry.value);

        expect(exporter.batches, isEmpty, reason: entry.key.name);
        expect(
          chronicler.diagnosticCounts[DiagnosticReason.collectionDisabled],
          BigInt.one,
          reason: entry.key.name,
        );
        expect(chronicler.diagnosticCounts[DiagnosticReason.invalidRecord], isNull);
        expect(chronicler.isCollectionEnabled(entry.key), isFalse);
        expect(
          ChroniclerSignal.values
              .where((signal) => signal != entry.key)
              .every(chronicler.isCollectionEnabled),
          isTrue,
        );
      }
    });

    test('disabled in-flight records stay ineligible while unaffected records retry', () async {
      final exporter = TestExporter();
      final chronicler = _chronicler(exporter, maxBatchRecords: 2);
      ChroniclerDeliveryFixture.selectRetryDelay(chronicler, (_, _) => Duration.zero);
      Context().withChronicler(chronicler.recorder).logs.info('log');
      ChroniclerCaptureFixture.capture(chronicler, _event('event'));
      await waitForCondition(() => exporter.attempts.length == 1);
      final records = exporter.batches.single.records;

      chronicler
        ..setCollectionEnabled(ChroniclerSignal.logs, false)
        ..setCollectionEnabled(ChroniclerSignal.logs, true);
      exporter.attempts.single.completer.complete(
        ExportResult.perRecord([
          for (final record in records)
            RecordExportOutcome(
              eventId: record.envelope.eventId,
              disposition: ExportDisposition.retryable,
            ),
        ]),
      );
      await waitForCondition(() => exporter.attempts.length == 2);

      expect(exporter.batches.last.records.map((record) => record.kind), ['event']);
      expect(chronicler.diagnosticCounts[DiagnosticReason.collectionDisabled], BigInt.one);
    });

    for (final outcome in <String, void Function(TestExportAttempt)>{
      'accepted': (attempt) => attempt.completer.complete(const ExportResult.accepted()),
      'retryable': (attempt) => attempt.completer.complete(const ExportResult.retryable()),
      'malformed': (attempt) => attempt.completer.complete(ExportResult.perRecord(const [])),
      'failed': (attempt) => attempt.completer.completeError(Exception('failed')),
    }.entries) {
      test('disable then re-enable suppresses an in-flight ${outcome.key} retry', () async {
        final exporter = TestExporter();
        final chronicler = _chronicler(exporter);
        Context().withChronicler(chronicler.recorder).logs.info('old');
        await waitForCondition(() => exporter.attempts.length == 1);

        chronicler
          ..setCollectionEnabled(ChroniclerSignal.logs, false)
          ..setCollectionEnabled(ChroniclerSignal.logs, true);
        outcome.value(exporter.attempts.single);
        await settleAsync();
        expect(exporter.batches, hasLength(1));

        Context().withChronicler(chronicler.recorder).logs.info('new');
        await waitForCondition(() => exporter.attempts.length == 2);
        expect(
          (exporter.batches.last.records.single as LogRecord).payload.message,
          'new',
        );
      });
    }

    test('timed-out disabled record never overlaps and only new capture exports', () async {
      final exporter = TestExporter();
      final chronicler = _chronicler(
        exporter,
        attemptTimeout: const Duration(milliseconds: 2),
      );
      Context().withChronicler(chronicler.recorder).logs.info('old');
      await waitForCondition(() => exporter.attempts.length == 1);
      chronicler
        ..setCollectionEnabled(ChroniclerSignal.logs, false)
        ..setCollectionEnabled(ChroniclerSignal.logs, true);
      await waitForCondition(() => exporter.attempts.single.cancelCount == 1);
      await settleAsync();
      expect(exporter.batches, hasLength(1));

      exporter.attempts.single.completer.complete(const ExportResult.retryable());
      await settleAsync();
      expect(exporter.batches, hasLength(1));
      Context().withChronicler(chronicler.recorder).logs.info('new');
      await waitForCondition(() => exporter.attempts.length == 2);
    });
  });
}

Chronicler _chronicler(
  TestExporter exporter, {
  int maxBatchRecords = 1,
  Duration batchInterval = const Duration(seconds: 5),
  Duration attemptTimeout = const Duration(seconds: 1),
}) => closeAfterTest(
  Chronicler(
    appId: 'app',
    release: 'release',
    source: ChroniclerSource.server,
    exporter: exporter,
    options: ChroniclerOptions(
      delivery: DeliveryOptions(
        maxBatchRecords: maxBatchRecords,
        batchInterval: batchInterval,
        attemptTimeout: attemptTimeout,
        initialRetryDelay: const Duration(microseconds: 1),
      ),
    ),
  ),
  exporter,
);

ProductEventRecord _event(String name) => ProductEventRecord(
  envelope: testEnvelope(),
  payload: ProductEventPayload(name: name),
);

LogRecord _log() => LogRecord(
  envelope: testEnvelope(),
  payload: LogPayload(severity: LogSeverity.info, message: 'log'),
);

SpanRecord _span() => SpanRecord(
  envelope: testEnvelope().copyWith(
    traceId: '0123456789abcdef0123456789abcdef',
    spanId: '0123456789abcdef',
  ),
  payload: SpanPayload(
    name: 'span',
    spanKind: SpanKind.internal,
    status: SpanStatus.success,
    durationMicros: 1,
  ),
);

ErrorRecord _error() => ErrorRecord(
  envelope: testEnvelope(),
  payload: ErrorPayload(
    error: const ErrorDetails(type: 'Exception', message: 'failed'),
    handled: true,
  ),
);

IdentityLinkRecord _identity() => IdentityLinkRecord(
  envelope: testEnvelope(),
  payload: const IdentityLinkPayload(anonymousId: 'anonymous', userId: 'user'),
);

UserPropertiesSetRecord _propertiesSet() => UserPropertiesSetRecord(
  envelope: testEnvelope(),
  payload: UserPropertiesSetPayload(
    userId: 'user',
    properties: const {'name': 'A'},
  ),
);

UserPropertiesUnsetRecord _propertiesUnset() => UserPropertiesUnsetRecord(
  envelope: testEnvelope(),
  payload: UserPropertiesUnsetPayload(userId: 'user', keys: const ['name']),
);
