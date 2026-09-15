import 'package:chronicler/chronicler.dart';
import 'package:context/context.dart';
import 'package:test/test.dart';

import 'support/error_capture_support.dart';
import 'support/exporter.dart';

void main() {
  group('ChroniclerErrors causes', () {
    test('should reject hook-modified causes that exceed the chain limit', () async {
      final exporter = TestExporter();
      final chronicler = Chronicler(
        appId: 'app',
        release: 'release',
        source: ChroniclerSource.server,
        exporter: exporter,
        options: ChroniclerOptions(
          delivery: const DeliveryOptions(maxBatchRecords: 1),
          redaction: RedactionOptions(
            beforeRecord: (record) {
              final error = record as ErrorRecord;
              return error.copyWith(
                payload: error.payload.copyWith(
                  causes: List.filled(
                    5,
                    const ErrorDetails(type: 'Cause', message: 'invalid'),
                  ),
                ),
              );
            },
          ),
        ),
      );

      Context().withChronicler(chronicler.recorder).errors.capture('root');
      await Future<void>.delayed(Duration.zero);

      expect(exporter.batches, isEmpty);
      expect(chronicler.diagnosticCounts[DiagnosticReason.invalidRecord], BigInt.one);
    });

    test('should preserve explicitly supplied causes in order with repetitions', () async {
      final exporter = TestExporter();
      final chronicler = createErrorChronicler(exporter);
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

    test('should preserve root and cause line endings through the codec', () async {
      final exporter = TestExporter();
      final chronicler = createErrorChronicler(exporter);

      Context()
          .withChronicler(chronicler.recorder)
          .errors
          .capture(
            'root',
            stackTrace: StackTrace.fromString('root-a\r\nroot-b\n'),
            causes: [
              ChroniclerCause(
                'cause',
                stackTrace: StackTrace.fromString('cause-a\ncause-b\r\n'),
              ),
            ],
          );
      await Future<void>.delayed(Duration.zero);
      final captured = exporter.batches.single.records.single as ErrorRecord;
      const codec = ChroniclerCodec();

      final decoded = codec.decodeRecord(codec.encodeRecord(captured));
      expect(decoded, isA<Decoded<ChroniclerRecord>>());
      final error = (decoded as Decoded<ChroniclerRecord>).value as ErrorRecord;
      expect(error.payload.error.stackTrace, 'root-a\r\nroot-b\n');
      expect(error.payload.causes.single.stackTrace, 'cause-a\ncause-b\r\n');
    });

    test('should contain conversion failures for each explicit cause', () async {
      final exporter = TestExporter();
      final chronicler = createErrorChronicler(exporter);

      Context()
          .withChronicler(chronicler.recorder)
          .errors
          .capture(
            'root',
            causes: [
              ChroniclerCause(
                ThrowingText(),
                stackTrace: ThrowingStack(),
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
      final chronicler = createErrorChronicler(exporter, maxBatchRecords: 2);
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
      final chronicler = createErrorChronicler(exporter);
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

    test('should accept four causes', () async {
      final exporter = TestExporter();
      final chronicler = createErrorChronicler(exporter);

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
