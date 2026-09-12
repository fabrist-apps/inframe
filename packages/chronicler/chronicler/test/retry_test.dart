import 'package:chronicler/chronicler.dart';
import 'package:chronicler/src/runtime.dart' show ChroniclerDeliveryFixture;
import 'package:context/context.dart';
import 'package:test/test.dart';

import 'support/exporter.dart';

void main() {
  group('Chronicler retries', () {
    test('should retry a retryable record with stable identity', () async {
      final exporter = TestExporter();
      final chronicler = Chronicler(
        appId: 'app',
        release: 'release',
        source: ChroniclerSource.server,
        exporter: exporter,
        options: const ChroniclerOptions(
          delivery: DeliveryOptions(
            maxBatchRecords: 1,
            maxAttempts: 2,
            initialRetryDelay: Duration(milliseconds: 1),
            maxRetryDelay: Duration(milliseconds: 1),
          ),
        ),
      );
      Context().withChronicler(chronicler.recorder).logs.info('retry');
      await Future<void>.delayed(Duration.zero);
      final first = exporter.batches.single.records.single;

      exporter.attempts.single.completer.complete(const ExportResult.retryable());
      await Future<void>.delayed(const Duration(milliseconds: 5));

      expect(exporter.batches, hasLength(2));
      expect(exporter.batches.last.records.single.envelope.eventId, first.envelope.eventId);
      expect(exporter.batches.last.records.single.envelope.timestamp, first.envelope.timestamp);
    });

    test('applies mixed outcomes by event ID after validating the full result', () async {
      final exporter = TestExporter();
      final chronicler = _chronicler(
        exporter,
        maxBatchRecords: 3,
        maxAttempts: 2,
      );
      Context().withChronicler(chronicler.recorder).logs
        ..info('accepted')
        ..info('retryable')
        ..info('rejected');
      await _waitFor(() => exporter.attempts.length == 1);
      final records = exporter.batches.single.records;

      exporter.attempts.single.completer.complete(
        ExportResult.perRecord([
          RecordExportOutcome(
            eventId: records[2].envelope.eventId,
            disposition: ExportDisposition.rejected,
          ),
          RecordExportOutcome(
            eventId: records[0].envelope.eventId,
            disposition: ExportDisposition.accepted,
          ),
          RecordExportOutcome(
            eventId: records[1].envelope.eventId,
            disposition: ExportDisposition.retryable,
          ),
        ]),
      );
      await _waitFor(() => exporter.attempts.length == 2);

      expect(exporter.batches.last.records, [records[1]]);
      expect(chronicler.diagnosticCounts[DiagnosticReason.exportRejected], BigInt.one);
      exporter.attempts.last.completer.complete(const ExportResult.retryable());
      await _settle();
      expect(exporter.batches, hasLength(2));
      expect(chronicler.diagnosticCounts[DiagnosticReason.attemptsExhausted], BigInt.one);
    });

    for (final malformed in <String, ExportResult Function(List<ChroniclerRecord>)>{
      'missing ID': (records) => ExportResult.perRecord([
        RecordExportOutcome(
          eventId: records.first.envelope.eventId,
          disposition: ExportDisposition.accepted,
        ),
      ]),
      'duplicate ID': (records) => ExportResult.perRecord([
        for (var index = 0; index < 2; index++)
          RecordExportOutcome(
            eventId: records.first.envelope.eventId,
            disposition: ExportDisposition.accepted,
          ),
      ]),
      'unknown ID': (records) => ExportResult.perRecord([
        RecordExportOutcome(
          eventId: records.first.envelope.eventId,
          disposition: ExportDisposition.accepted,
        ),
        const RecordExportOutcome(
          eventId: 'evt_unknown',
          disposition: ExportDisposition.rejected,
        ),
      ]),
    }.entries) {
      test('${malformed.key} invalidates every partial outcome', () async {
        final exporter = TestExporter();
        final chronicler = _chronicler(
          exporter,
          maxBatchRecords: 2,
          maxAttempts: 2,
        );
        Context().withChronicler(chronicler.recorder).logs
          ..info('one')
          ..info('two');
        await _waitFor(() => exporter.attempts.length == 1);
        final records = exporter.batches.single.records;

        exporter.attempts.single.completer.complete(malformed.value(records));
        await _waitFor(() => exporter.attempts.length == 2);

        expect(exporter.batches.last.records, records);
        expect(chronicler.diagnosticCounts[DiagnosticReason.invalidExportResult], BigInt.one);
        exporter.attempts.last.completer.complete(const ExportResult.retryable());
        await _settle();
        expect(exporter.batches, hasLength(2));
        expect(
          chronicler.diagnosticCounts[DiagnosticReason.attemptsExhausted],
          BigInt.two,
        );
      });
    }

    test('whole-batch rejection is terminal and diagnosed for each record', () async {
      final exporter = TestExporter();
      final chronicler = _chronicler(exporter, maxBatchRecords: 2);
      Context().withChronicler(chronicler.recorder).logs
        ..info('one')
        ..info('two');
      await _waitFor(() => exporter.attempts.length == 1);

      exporter.attempts.single.completer.complete(const ExportResult.rejected());
      await _settle();

      expect(exporter.batches, hasLength(1));
      expect(chronicler.diagnosticCounts[DiagnosticReason.exportRejected], BigInt.two);
    });

    test('synchronous and asynchronous exporter failures consume attempts', () async {
      final exporter = TestExporter()..failNextExport(Exception('sync failure'));
      final chronicler = _chronicler(exporter, maxAttempts: 3);
      Context().withChronicler(chronicler.recorder).logs.info('failure');
      await _waitFor(() => exporter.attempts.length == 1);
      exporter.attempts.single.completer.completeError(StateError('async failure'));
      await _waitFor(() => exporter.attempts.length == 2);
      exporter.attempts.last.completer.complete(const ExportResult.retryable());
      await _settle();

      expect(exporter.batches, hasLength(3));
      expect(chronicler.diagnosticCounts[DiagnosticReason.exportFailed], BigInt.two);
      expect(chronicler.diagnosticCounts[DiagnosticReason.attemptsExhausted], BigInt.one);
    });

    test('uses five total attempts and capped exponential retry ceilings by default', () async {
      final exporter = TestExporter();
      final chronicler = Chronicler(
        appId: 'app',
        release: 'release',
        source: ChroniclerSource.server,
        exporter: exporter,
        options: const ChroniclerOptions(
          delivery: DeliveryOptions(maxBatchRecords: 1),
        ),
      );
      final ceilings = <Duration>[];
      ChroniclerDeliveryFixture.selectRetryDelay(chronicler, (attempt, ceiling) {
        ceilings.add(ceiling);
        return Duration.zero;
      });
      Context().withChronicler(chronicler.recorder).logs.info('exhaust');

      for (var attempt = 0; attempt < 5; attempt++) {
        await _waitFor(() => exporter.attempts.length == attempt + 1);
        exporter.attempts[attempt].completer.complete(const ExportResult.retryable());
      }
      await _settle();

      expect(exporter.batches, hasLength(5));
      expect(ceilings, const [
        Duration(seconds: 1),
        Duration(seconds: 2),
        Duration(seconds: 4),
        Duration(seconds: 8),
      ]);
      expect(chronicler.diagnosticCounts[DiagnosticReason.attemptsExhausted], BigInt.one);
    });

    test('caps additional retry ceilings and accepts every full-jitter boundary', () async {
      final exporter = TestExporter();
      final chronicler = _chronicler(
        exporter,
        initialRetryDelay: const Duration(microseconds: 2),
        maxRetryDelay: const Duration(microseconds: 3),
      );
      final ceilings = <Duration>[];
      ChroniclerDeliveryFixture.selectRetryDelay(chronicler, (attempt, ceiling) {
        ceilings.add(ceiling);
        return attempt.isOdd ? Duration.zero : ceiling;
      });
      Context().withChronicler(chronicler.recorder).logs.info('capped');

      for (var attempt = 0; attempt < 5; attempt++) {
        await _waitFor(() => exporter.attempts.length == attempt + 1);
        exporter.attempts[attempt].completer.complete(const ExportResult.retryable());
      }
      await _settle();

      expect(ceilings, const [
        Duration(microseconds: 2),
        Duration(microseconds: 3),
        Duration(microseconds: 3),
        Duration(microseconds: 3),
      ]);
    });

    test('supports retry ceilings larger than Random.nextInt permits', () async {
      final exporter = TestExporter();
      final chronicler = _chronicler(
        exporter,
        maxAttempts: 2,
        initialRetryDelay: const Duration(hours: 2),
        maxRetryDelay: const Duration(hours: 2),
      );
      Context().withChronicler(chronicler.recorder).logs.info('long delay');
      await _waitFor(() => exporter.attempts.length == 1);

      exporter.attempts.single.completer.complete(const ExportResult.retryable());
      await _settle();

      expect(exporter.attempts, hasLength(1));
      final closeFuture = chronicler.close();
      await _waitFor(() => exporter.attempts.length == 2);
      exporter.attempts.last.completer.complete(const ExportResult.accepted());
      expect((await closeFuture).accepted, 1);
    });

    test('ready records pass backoff while eligible records retain enqueue order', () async {
      final exporter = TestExporter();
      final chronicler = _chronicler(
        exporter,
        maxBatchRecords: 2,
        initialRetryDelay: const Duration(milliseconds: 20),
      );
      ChroniclerDeliveryFixture.selectRetryDelay(
        chronicler,
        (_, _) => const Duration(milliseconds: 20),
      );
      Context().withChronicler(chronicler.recorder).logs
        ..info('old-one')
        ..info('old-two');
      await _waitFor(() => exporter.attempts.length == 1);
      exporter.attempts.single.completer.complete(const ExportResult.retryable());
      await _settle();

      Context().withChronicler(chronicler.recorder).logs
        ..info('new-one')
        ..info('new-two');
      await _waitFor(() => exporter.attempts.length == 2);
      expect(
        exporter.batches[1].records.map((record) => (record as LogRecord).payload.message),
        ['new-one', 'new-two'],
      );

      exporter.attempts[1].completer.complete(const ExportResult.accepted());
      await _waitFor(() => exporter.attempts.length == 3);
      final retryMessages = exporter.batches[2].records
          .map((record) => (record as LogRecord).payload.message)
          .toList();
      if (retryMessages.length == 1) {
        exporter.attempts[2].completer.complete(const ExportResult.accepted());
        await _waitFor(() => exporter.attempts.length == 4);
        retryMessages.add(
          (exporter.batches[3].records.first as LogRecord).payload.message,
        );
      }
      expect(retryMessages, ['old-one', 'old-two']);
    });

    test('respects active-export concurrency across retries', () async {
      final exporter = TestExporter();
      final chronicler = _chronicler(
        exporter,
        maxConcurrentExports: 2,
      );
      Context().withChronicler(chronicler.recorder).logs
        ..info('one')
        ..info('two')
        ..info('three');
      await _waitFor(() => exporter.attempts.length == 2);
      await _settle();
      expect(exporter.attempts, hasLength(2));

      exporter.attempts.first.completer.complete(const ExportResult.retryable());
      await _waitFor(() => exporter.attempts.length == 3);
      expect(exporter.batches[2].records.single, exporter.batches.first.records.single);
    });

    test('timeout requests cancellation and retains capacity until late acceptance', () async {
      final exporter = TestExporter();
      final chronicler = _chronicler(
        exporter,
        attemptTimeout: const Duration(milliseconds: 2),
      );
      Context().withChronicler(chronicler.recorder).logs
        ..info('timed-out')
        ..info('waiting');
      await _waitFor(() => exporter.attempts.length == 1);
      await _waitFor(() => exporter.attempts.single.cancelCount == 1);
      await _settle();

      expect(exporter.batches, hasLength(1));
      expect(chronicler.diagnosticCounts[DiagnosticReason.exportTimedOut], BigInt.one);
      exporter.attempts.single.completer.complete(const ExportResult.accepted());
      await _waitFor(() => exporter.attempts.length == 2);
      expect((exporter.batches.last.records.single as LogRecord).payload.message, 'waiting');
    });

    test('counts synchronous exporter work against the attempt deadline', () async {
      final exporter = _BlockingAcceptedExporter(const Duration(milliseconds: 10));
      final chronicler = Chronicler(
        appId: 'app',
        release: 'release',
        source: ChroniclerSource.server,
        exporter: exporter,
        options: const ChroniclerOptions(
          delivery: DeliveryOptions(
            maxBatchRecords: 1,
            attemptTimeout: Duration(milliseconds: 1),
          ),
        ),
      );

      Context().withChronicler(chronicler.recorder).logs.info('blocked export');
      await _waitFor(() => exporter.attempt != null);
      await _settle();

      expect(exporter.attempt!.cancelCount, 1);
      expect(chronicler.diagnosticCounts[DiagnosticReason.exportTimedOut], BigInt.one);
      await chronicler.close();
    });

    test('late rejection is terminal and cancellation throws are diagnosed', () async {
      final exporter = TestExporter();
      final chronicler = _chronicler(
        exporter,
        attemptTimeout: const Duration(milliseconds: 2),
      );
      Context().withChronicler(chronicler.recorder).logs.info('late rejection');
      await _waitFor(() => exporter.attempts.length == 1);
      exporter.attempts.single.cancelError = Exception('cancel failed');
      await _waitFor(() => exporter.attempts.single.cancelCount == 1);
      exporter.attempts.single.completer.complete(const ExportResult.rejected());
      await _settle();

      expect(exporter.batches, hasLength(1));
      expect(
        chronicler.diagnosticCounts[DiagnosticReason.exportCancellationFailed],
        BigInt.one,
      );
      expect(chronicler.diagnosticCounts[DiagnosticReason.exportRejected], BigInt.one);
    });

    test('retry does not repeat capture hooks', () async {
      var hookCalls = 0;
      final exporter = TestExporter();
      final chronicler = Chronicler(
        appId: 'app',
        release: 'release',
        source: ChroniclerSource.server,
        exporter: exporter,
        options: ChroniclerOptions(
          delivery: const DeliveryOptions(
            maxBatchRecords: 1,
            maxAttempts: 2,
            initialRetryDelay: Duration(microseconds: 1),
          ),
          redaction: RedactionOptions(
            beforeRecord: (record) {
              hookCalls++;
              return record;
            },
          ),
        ),
      );
      Context().withChronicler(chronicler.recorder).logs.info('hook');
      await _waitFor(() => exporter.attempts.length == 1);
      exporter.attempts.single.completer.complete(const ExportResult.retryable());
      await _waitFor(() => exporter.attempts.length == 2);

      expect(hookCalls, 1);
    });
  });
}

Chronicler _chronicler(
  TestExporter exporter, {
  int maxBatchRecords = 1,
  int maxAttempts = 5,
  int maxConcurrentExports = 1,
  Duration attemptTimeout = const Duration(seconds: 1),
  Duration initialRetryDelay = const Duration(microseconds: 1),
  Duration maxRetryDelay = const Duration(seconds: 30),
}) => Chronicler(
  appId: 'app',
  release: 'release',
  source: ChroniclerSource.server,
  exporter: exporter,
  options: ChroniclerOptions(
    delivery: DeliveryOptions(
      maxBatchRecords: maxBatchRecords,
      maxAttempts: maxAttempts,
      maxConcurrentExports: maxConcurrentExports,
      attemptTimeout: attemptTimeout,
      initialRetryDelay: initialRetryDelay,
      maxRetryDelay: maxRetryDelay,
    ),
  ),
);

Future<void> _settle() => Future<void>.delayed(const Duration(milliseconds: 4));

final class _BlockingAcceptedExporter implements ChroniclerExporter {
  _BlockingAcceptedExporter(this.blockFor);

  final Duration blockFor;
  TestExportAttempt? attempt;

  @override
  ExportAttempt export(ChroniclerBatch batch) {
    final current = TestExportAttempt();
    current.completer.complete(const ExportResult.accepted());
    final elapsed = Stopwatch()..start();
    while (elapsed.elapsed < blockFor) {}
    attempt = current;
    return current;
  }

  @override
  Future<void> close() async {}
}

Future<void> _waitFor(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 1));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) fail('Condition was not met before timeout.');
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
}
