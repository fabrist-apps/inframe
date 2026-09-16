import 'package:chronicler/chronicler.dart';
import 'package:context/context.dart';
import 'package:test/test.dart';

import 'support/async.dart';
import 'support/error_capture_support.dart';
import 'support/exporter.dart';

void main() {
  setUpAll(Chronicler.initialize);
  group('ChroniclerErrors capture', () {
    test('should export a handled error with attribution and raw stack', () async {
      final exporter = TestExporter();
      final chronicler = Chronicler(
        appId: 'app',
        release: '1.2.3',
        buildId: 'build-4',
        source: ChroniclerSource.server,
        exporter: exporter,
        options: const ChroniclerOptions(
          delivery: DeliveryOptions(maxBatchRecords: 2),
        ),
      );
      Context()
          .withChronicler(chronicler.recorder)
          .withIdentity(userId: 'user', anonymousId: 'anon', sessionId: 'session')
          .traceSync(
            'operation',
            run: (operation) {
              operation.errors.capture(
                StateError('failed'),
                stackTrace: StackTrace.fromString('first\r\nsecond\n'),
                attributes: {'feature': 'checkout'},
              );
            },
          );
      await Future<void>.delayed(Duration.zero);

      final records = exporter.batches.single.records;
      final error = records.whereType<ErrorRecord>().single;
      expect(error.payload.error.type, 'StateError');
      expect(error.payload.error.message, 'Bad state: failed');
      expect(error.payload.error.stackTrace, 'first\r\nsecond\n');
      expect(error.payload.handled, isTrue);
      expect(error.payload.causes, isEmpty);
      expect(error.payload.attributes, {'feature': 'checkout'});
      expect(error.envelope.release, '1.2.3');
      expect(error.envelope.buildId, 'build-4');
      expect(error.envelope.userId, 'user');
      expect(error.envelope.anonymousId, 'anon');
      expect(error.envelope.sessionId, 'session');
      expect(error.envelope.traceId, isNotNull);
      expect(error.envelope.spanId, isNotNull);
    });

    test('should capture arbitrary values and keep occurrences distinct', () async {
      final exporter = TestExporter();
      final chronicler = createErrorChronicler(exporter, maxBatchRecords: 2);
      final context = Context().withChronicler(chronicler.recorder);
      final thrownValue = Object();

      context.errors.capture(thrownValue, handled: false);
      context.errors.capture(thrownValue, handled: false);
      expect(exporter.batches, isEmpty);
      await Future<void>.delayed(Duration.zero);

      final errors = exporter.batches.single.records.cast<ErrorRecord>().toList();
      expect(errors, hasLength(2));
      expect(errors.map((record) => record.payload.handled), everyElement(isFalse));
      expect(errors.map((record) => record.envelope.eventId).toSet(), hasLength(2));
      expect(errors.map((record) => record.payload.error.stackTrace), everyElement(isNull));
      expect(errors.map((record) => record.envelope.buildId), everyElement(isNull));
    });

    test('should contain text conversion failures and preserve supplied stack', () async {
      final exporter = TestExporter();
      final chronicler = createErrorChronicler(exporter);

      Context()
          .withChronicler(chronicler.recorder)
          .errors
          .capture(
            ThrowingText(),
            stackTrace: StackTrace.fromString('application-stack'),
          );
      await Future<void>.delayed(Duration.zero);

      final error = exporter.batches.single.records.single as ErrorRecord;
      expect(error.payload.error.message, '[Error message unavailable]');
      expect(error.payload.error.stackTrace, 'application-stack');
      expect(chronicler.diagnosticCounts[DiagnosticReason.textConversionFailed], BigInt.one);
    });

    test('should use a fixed fallback when stack conversion fails', () async {
      final exporter = TestExporter();
      final chronicler = createErrorChronicler(exporter);

      Context()
          .withChronicler(chronicler.recorder)
          .errors
          .capture(
            'failed',
            stackTrace: ThrowingStack(),
          );
      await Future<void>.delayed(Duration.zero);

      final error = exporter.batches.single.records.single as ErrorRecord;
      expect(error.payload.error.stackTrace, '[Stack trace unavailable]');
      expect(chronicler.diagnosticCounts[DiagnosticReason.textConversionFailed], BigInt.one);
    });

    test('should apply redaction and hook changes before buffering', () async {
      final exporter = TestExporter();
      var hookCalls = 0;
      final chronicler = Chronicler(
        appId: 'app',
        release: 'release',
        source: ChroniclerSource.server,
        exporter: exporter,
        options: ChroniclerOptions(
          delivery: const DeliveryOptions(maxBatchRecords: 1),
          redaction: RedactionOptions(
            beforeRecord: (record) {
              hookCalls++;
              final error = record as ErrorRecord;
              return error.copyWith(
                payload: error.payload.copyWith(
                  error: error.payload.error.copyWith(message: '[REDACTED ERROR]'),
                  causes: [
                    for (final cause in error.payload.causes)
                      cause.copyWith(message: '[REDACTED CAUSE]'),
                  ],
                  attributes: {'accessToken': 'introduced'},
                ),
              );
            },
          ),
        ),
      );

      Context()
          .withChronicler(chronicler.recorder)
          .errors
          .capture(
            StateError('secret'),
            causes: [ChroniclerCause(StateError('cause secret'))],
            attributes: {'password': 'original'},
          );
      await Future<void>.delayed(Duration.zero);

      final error = exporter.batches.single.records.single as ErrorRecord;
      expect(hookCalls, 1);
      expect(error.payload.error.message, '[REDACTED ERROR]');
      expect(error.payload.causes.single.message, '[REDACTED CAUSE]');
      expect(error.payload.attributes, {'accessToken': '[REDACTED]'});
    });

    test('should keep error occurrences separate from error logs and failed spans', () async {
      final exporter = TestExporter();
      final chronicler = createErrorChronicler(exporter, maxBatchRecords: 3);
      final context = Context().withChronicler(chronicler.recorder);

      context.logs.error('log', error: StateError('logged'));
      context.spanSync('span', run: (span) => span.tracing.setError());
      context.errors.capture(StateError('captured'));
      await Future<void>.delayed(Duration.zero);

      final records = exporter.batches.single.records;
      expect(records.whereType<LogRecord>(), hasLength(1));
      expect(records.whereType<SpanRecord>(), hasLength(1));
      expect(records.whereType<ErrorRecord>(), hasLength(1));
    });

    test('should bypass random sampling and preserve payload on retry', () async {
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
          sampling: SamplingOptions(logs: 0, events: 0, traces: 0),
        ),
      );

      Context()
          .withChronicler(chronicler.recorder)
          .errors
          .capture(
            'retry',
            causes: const [ChroniclerCause('cause')],
          );
      await Future<void>.delayed(Duration.zero);
      final first = exporter.batches.single.records.single as ErrorRecord;
      exporter.attempts.single.completer.complete(const ExportResult.retryable());
      await waitForCondition(() => exporter.attempts.length == 2);

      final retried = exporter.batches.last.records.single as ErrorRecord;
      expect(exporter.batches, hasLength(2));
      expect(retried.envelope.eventId, first.envelope.eventId);
      expect(retried.envelope.timestamp, first.envelope.timestamp);
      expect(retried.payload, first.payload);
      expect(retried.payload.causes.single.message, 'cause');
    });

    test('should drop oversized root fields without truncation', () async {
      final exporter = TestExporter();
      final chronicler = Chronicler(
        appId: 'app',
        release: 'release',
        source: ChroniclerSource.server,
        exporter: exporter,
        options: const ChroniclerOptions(
          delivery: DeliveryOptions(maxBatchRecords: 1, maxRecordBytes: 400),
        ),
      );
      Context().withChronicler(chronicler.recorder).errors
        ..capture('x' * 400)
        ..capture('', stackTrace: StackTrace.fromString('x' * 400));
      await Future<void>.delayed(Duration.zero);

      expect(exporter.batches, isEmpty);
      expect(chronicler.diagnosticCounts[DiagnosticReason.recordTooLarge], BigInt.two);
    });

    test('should obey error collection and closed-runtime transitions', () async {
      final exporter = TestExporter(acceptImmediately: true);
      final chronicler = createErrorChronicler(exporter);
      final errors = Context().withChronicler(chronicler.recorder).errors;

      chronicler.setCollectionEnabled(ChroniclerSignal.errors, enabled: false);
      errors.capture('disabled');
      await Future<void>.delayed(Duration.zero);
      expect(exporter.batches, isEmpty);
      expect(
        chronicler.diagnosticCounts[DiagnosticReason.collectionDisabled],
        BigInt.one,
      );

      chronicler.setCollectionEnabled(ChroniclerSignal.errors, enabled: true);
      errors.capture('enabled');
      await Future<void>.delayed(Duration.zero);
      expect(exporter.batches, hasLength(1));

      await chronicler.close();
      errors.capture('closed');
      expect(chronicler.diagnosticCounts[DiagnosticReason.runtimeClosed], BigInt.one);
    });

    test('should throw MissingContextValue when setup is absent', () {
      expect(() => Context().errors, throwsA(isA<MissingContextValue>()));
    });
  });
}
