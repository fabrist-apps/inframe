import 'package:chronicler/chronicler.dart';
import 'package:context/context.dart';
import 'package:test/test.dart';

import 'support/exporter.dart';

void main() {
  group('ChroniclerErrors', () {
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
      final chronicler = _chronicler(exporter, maxBatchRecords: 2);
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
      final chronicler = _chronicler(exporter);

      Context()
          .withChronicler(chronicler.recorder)
          .errors
          .capture(
            _ThrowingText(),
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
      final chronicler = _chronicler(exporter);

      Context()
          .withChronicler(chronicler.recorder)
          .errors
          .capture(
            'failed',
            stackTrace: _ThrowingStack(),
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
      final chronicler = _chronicler(exporter, maxBatchRecords: 3);
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
      await Future<void>.delayed(const Duration(milliseconds: 10));

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
          limits: ChroniclerLimits(
            maxErrorMessageBytes: 3,
            maxStackTraceBytes: 3,
          ),
          delivery: DeliveryOptions(maxBatchRecords: 1),
        ),
      );
      Context().withChronicler(chronicler.recorder).errors
        ..capture('four')
        ..capture('', stackTrace: StackTrace.fromString('four'));
      await Future<void>.delayed(Duration.zero);

      expect(exporter.batches, isEmpty);
      expect(chronicler.diagnosticCounts[DiagnosticReason.invalidRecord], BigInt.two);
    });

    test('should throw MissingContextValue when setup is absent', () {
      expect(() => Context().errors, throwsA(isA<MissingContextValue>()));
    });

    test('should preserve explicitly supplied causes in order with repetitions', () async {
      final exporter = TestExporter();
      final chronicler = _chronicler(exporter);
      final repeated = StateError('repeated');

      Context()
          .withChronicler(chronicler.recorder)
          .errors
          .capture(
            StateError('root'),
            causes: [
              ChroniclerCause(repeated, stackTrace: StackTrace.fromString('nearest')),
              const ChroniclerCause('deepest'),
              ChroniclerCause(repeated),
            ],
          );
      await Future<void>.delayed(Duration.zero);

      final error = exporter.batches.single.records.single as ErrorRecord;
      expect(error.payload.causes.map((cause) => cause.message), [
        'Bad state: repeated',
        'deepest',
        'Bad state: repeated',
      ]);
      expect(error.payload.causes.first.stackTrace, 'nearest');
    });

    test('should contain conversion failures for each explicit cause', () async {
      final exporter = TestExporter();
      final chronicler = _chronicler(exporter);

      Context()
          .withChronicler(chronicler.recorder)
          .errors
          .capture(
            'root',
            causes: [
              ChroniclerCause(
                _ThrowingText(),
                stackTrace: _ThrowingStack(),
              ),
            ],
          );
      await Future<void>.delayed(Duration.zero);

      final cause = (exporter.batches.single.records.single as ErrorRecord).payload.causes.single;
      expect(cause.message, '[Error message unavailable]');
      expect(cause.stackTrace, '[Stack trace unavailable]');
      expect(chronicler.diagnosticCounts[DiagnosticReason.textConversionFailed], BigInt.two);
    });

    test('should snapshot cause inputs and retain ended-span correlation', () async {
      final exporter = TestExporter();
      final chronicler = _chronicler(exporter, maxBatchRecords: 2);
      final base = Context().withChronicler(chronicler.recorder);
      final causeText = _MutableText('before');
      final causeStack = _MutableStack('stack-before');
      final causes = <ChroniclerCause>[
        ChroniclerCause(causeText, stackTrace: causeStack),
      ];
      late Context retained;

      base.spanSync('operation', run: (span) => retained = span);
      retained.errors.capture('root', causes: causes);
      causes.clear();
      causeText.value = 'after';
      causeStack.value = 'stack-after';
      await Future<void>.delayed(Duration.zero);

      final records = exporter.batches.single.records;
      final span = records.whereType<SpanRecord>().single;
      final error = records.whereType<ErrorRecord>().single;
      expect(error.envelope.traceId, span.envelope.traceId);
      expect(error.envelope.spanId, span.envelope.spanId);
      expect(error.payload.causes.single.message, 'before');
      expect(error.payload.causes.single.stackTrace, 'stack-before');
    });

    test('should reject an excessive chain before converting its values', () async {
      final exporter = TestExporter();
      final chronicler = _chronicler(exporter);
      final root = _CountingText();
      final cause = _CountingText();

      Context()
          .withChronicler(chronicler.recorder)
          .errors
          .capture(
            root,
            causes: List.filled(5, ChroniclerCause(cause)),
          );
      await Future<void>.delayed(Duration.zero);

      expect(exporter.batches, isEmpty);
      expect(root.conversions, 0);
      expect(cause.conversions, 0);
      expect(chronicler.diagnosticCounts[DiagnosticReason.invalidRecord], BigInt.one);
    });

    test('should accept four causes and honor a configured zero limit', () async {
      final exporter = TestExporter();
      final chronicler = _chronicler(exporter);

      Context()
          .withChronicler(chronicler.recorder)
          .errors
          .capture(
            'root',
            causes: List.generate(4, (index) => ChroniclerCause('cause-$index')),
          );
      await Future<void>.delayed(Duration.zero);
      expect(
        (exporter.batches.single.records.single as ErrorRecord).payload.causes,
        hasLength(4),
      );

      final zeroExporter = TestExporter();
      final zero = Chronicler(
        appId: 'app',
        release: 'release',
        source: ChroniclerSource.server,
        exporter: zeroExporter,
        options: const ChroniclerOptions(
          limits: ChroniclerLimits(maxCauses: 0),
          delivery: DeliveryOptions(maxBatchRecords: 1),
        ),
      );
      Context()
          .withChronicler(zero.recorder)
          .errors
          .capture(
            'root',
            causes: const [ChroniclerCause('cause')],
          );
      await Future<void>.delayed(Duration.zero);
      expect(zeroExporter.batches, isEmpty);
      expect(zero.diagnosticCounts[DiagnosticReason.invalidRecord], BigInt.one);
    });

    test('should enforce UTF-8 field limits on every cause', () async {
      Future<Chronicler> capture(ChroniclerCause cause) async {
        final exporter = TestExporter();
        final chronicler = Chronicler(
          appId: 'app',
          release: 'release',
          source: ChroniclerSource.server,
          exporter: exporter,
          options: const ChroniclerOptions(
            limits: ChroniclerLimits(
              maxErrorMessageBytes: 3,
              maxStackTraceBytes: 3,
            ),
            delivery: DeliveryOptions(maxBatchRecords: 1),
          ),
        );
        Context()
            .withChronicler(chronicler.recorder)
            .errors
            .capture(
              '',
              causes: [cause],
            );
        await Future<void>.delayed(Duration.zero);
        expect(exporter.batches, isEmpty);
        return chronicler;
      }

      final message = await capture(const ChroniclerCause('éé'));
      final stack = await capture(
        ChroniclerCause('', stackTrace: StackTrace.fromString('éé')),
      );
      expect(message.diagnosticCounts[DiagnosticReason.invalidRecord], BigInt.one);
      expect(stack.diagnosticCounts[DiagnosticReason.invalidRecord], BigInt.one);
    });

    test('should enforce the complete encoded bound across a cause chain', () async {
      final exporter = TestExporter();
      final chronicler = Chronicler(
        appId: 'app',
        release: 'release',
        source: ChroniclerSource.server,
        exporter: exporter,
        options: const ChroniclerOptions(
          delivery: DeliveryOptions(
            maxRecordBytes: 400,
            maxBatchRecords: 1,
          ),
        ),
      );

      Context()
          .withChronicler(chronicler.recorder)
          .errors
          .capture(
            'r' * 100,
            causes: const [ChroniclerCause('placeholder')],
            attributes: {'extra': 'a' * 180},
          );
      await Future<void>.delayed(Duration.zero);

      expect(exporter.batches, isEmpty);
      expect(chronicler.diagnosticCounts[DiagnosticReason.recordTooLarge], BigInt.one);
    });
  });
}

final class _ThrowingText {
  @override
  String toString() => throw StateError('sensitive');
}

final class _ThrowingStack implements StackTrace {
  @override
  String toString() => throw StateError('sensitive');
}

final class _MutableText {
  _MutableText(this.value);

  String value;

  @override
  String toString() => value;
}

final class _MutableStack implements StackTrace {
  _MutableStack(this.value);

  String value;

  @override
  String toString() => value;
}

final class _CountingText {
  int conversions = 0;

  @override
  String toString() {
    conversions++;
    return 'converted';
  }
}

Chronicler _chronicler(TestExporter exporter, {int maxBatchRecords = 1}) => Chronicler(
  appId: 'app',
  release: 'release',
  source: ChroniclerSource.server,
  exporter: exporter,
  options: ChroniclerOptions(
    delivery: DeliveryOptions(maxBatchRecords: maxBatchRecords),
  ),
);
