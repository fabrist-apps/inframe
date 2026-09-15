import 'package:chronicler/chronicler.dart';
import 'package:context/context.dart';
import 'package:test/test.dart';

import 'support/async.dart';
import 'support/exporter.dart';
import 'support/runtime.dart';

void main() {
  group('Chronicler collection controls', () {
    test('disabled logs never enter delivery and toggles are independent', () async {
      final exporter = TestExporter();
      final chronicler = _chronicler(exporter);
      final span = chronicler.recorder.startSpan('propagation');
      addTearDown(() => span.end(SpanStatus.success));

      expect(chronicler.isCollectionEnabled(ChroniclerSignal.logs), isTrue);
      expect(TracePropagation.extract(span.recorder.injectTrace({})), isNotNull);
      chronicler
        ..setCollectionEnabled(ChroniclerSignal.logs, false)
        ..setCollectionEnabled(ChroniclerSignal.logs, false)
        ..setPropagationEnabled(false);
      Context().withChronicler(chronicler.recorder).logs.info('disabled');

      expect(chronicler.isCollectionEnabled(ChroniclerSignal.logs), isFalse);
      expect(chronicler.isCollectionEnabled(ChroniclerSignal.events), isTrue);
      expect(span.recorder.injectTrace({}), isEmpty);
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
      chronicler.recorder.recordEvent('kept-one');

      chronicler.setCollectionEnabled(ChroniclerSignal.logs, false);
      chronicler.recorder.recordEvent('kept-two');
      await waitForCondition(() => exporter.attempts.length == 1);

      expect(exporter.batches.single.records, hasLength(2));
      expect(exporter.batches.single.records.whereType<ProductEventRecord>(), hasLength(2));
      expect(chronicler.diagnosticCounts[DiagnosticReason.collectionDisabled], BigInt.one);
    });

    test('identity and property operations use the events switch', () {
      final exporter = TestExporter();
      final chronicler = _chronicler(exporter)
        ..setCollectionEnabled(ChroniclerSignal.events, false);

      chronicler.recorder
        ..identify(anonymousId: 'anonymous', userId: 'user')
        ..setUserProperties(userId: 'user', properties: {'name': 'A'})
        ..unsetUserProperties(userId: 'user', keys: ['name']);

      expect(exporter.batches, isEmpty);
      expect(chronicler.diagnosticCounts[DiagnosticReason.collectionDisabled], BigInt.from(3));
      expect(chronicler.isCollectionEnabled(ChroniclerSignal.logs), isTrue);
    });

    test('each signal switch should suppress capture through its public API', () async {
      for (final entry in <ChroniclerSignal, void Function(ChroniclerRecorder)>{
        ChroniclerSignal.logs: (recorder) => recorder.recordLog(LogSeverity.info, 'log'),
        ChroniclerSignal.events: (recorder) => recorder.recordEvent('event'),
        ChroniclerSignal.traces: (recorder) => recorder.startSpan('span').end(SpanStatus.success),
        ChroniclerSignal.errors: (recorder) => recorder.recordError(StateError('failed')),
        ChroniclerSignal.metrics: (recorder) => recorder.metrics.counter('count').add(1),
      }.entries) {
        final exporter = TestExporter();
        final chronicler = _chronicler(exporter)..setCollectionEnabled(entry.key, false);

        entry.value(chronicler.recorder);
        await chronicler.flush();

        expect(exporter.batches, isEmpty, reason: entry.key.name);
        expect(
          chronicler.diagnosticCounts[DiagnosticReason.collectionDisabled],
          // Disabled spans still establish correlation without retaining a payload.
          entry.key == ChroniclerSignal.traces ? isNull : BigInt.one,
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
      Context().withChronicler(chronicler.recorder).logs.info('log');
      chronicler.recorder.recordEvent('event');
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

      expect(exporter.batches.last.records, hasLength(1));
      expect(exporter.batches.last.records.single, isA<ProductEventRecord>());
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
