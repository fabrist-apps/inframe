import 'package:chronicler/chronicler.dart';
import 'package:context/context.dart';
import 'package:test/test.dart';

import 'support/exporter.dart';
import 'support/tracing_support.dart';

void main() {
  group('ChroniclerSpan', () {
    test('should derive nested recorders and honor explicit status precedence', () async {
      final exporter = TestExporter();
      final chronicler = createTracingChronicler(exporter, maxBatchRecords: 2);
      final base = Context().withChronicler(chronicler.recorder);

      final parent = base.tracing.startRootSpan('parent');
      final parentContext = base.withChronicler(parent.recorder);
      final child = parentContext.tracing.startSpan('child');
      final childContext = parentContext.withChronicler(child.recorder);
      childContext.tracing.setError();
      child
        ..end(SpanStatus.success)
        ..end(SpanStatus.cancelled);
      parent.end(SpanStatus.cancelled);

      await Future<void>.delayed(Duration.zero);
      final spans = exporter.batches.single.records.cast<SpanRecord>().toList();
      final parentRecord = spans.singleWhere((span) => span.payload.name == 'parent');
      final childRecord = spans.singleWhere((span) => span.payload.name == 'child');
      expect(childRecord.envelope.traceId, parentRecord.envelope.traceId);
      expect(childRecord.envelope.parentSpanId, parentRecord.envelope.spanId);
      expect(childRecord.payload.status, SpanStatus.error);
      expect(parentRecord.payload.status, SpanStatus.cancelled);
    });

    test('should continue a remote parent from an explicit root span', () async {
      final exporter = TestExporter();
      final chronicler = createTracingChronicler(exporter);
      final context = Context().withChronicler(chronicler.recorder);
      final remote = TracePropagation.extract({
        'chronicler-trace-id': 'trc_0123456789ABCDEFGHIJKLMN',
        'chronicler-span-id': 'spn_0123456789ABCDEFGHIJKLMN',
        'chronicler-sampled': '1',
      });

      context.tracing.startRootSpan('server', parent: remote).end(SpanStatus.success);
      await Future<void>.delayed(Duration.zero);

      final span = exporter.batches.single.records.single as SpanRecord;
      expect(span.envelope.traceId, 'trc_0123456789ABCDEFGHIJKLMN');
      expect(span.envelope.parentSpanId, 'spn_0123456789ABCDEFGHIJKLMN');
    });

    test('should preserve recorder work and contain invalid span input', () async {
      final exporter = TestExporter(acceptImmediately: true);
      final chronicler = createTracingChronicler(exporter);
      final context = Context().withChronicler(chronicler.recorder);

      final invalid = context.tracing.startSpan('');
      invalid.recorder.recordLog(LogSeverity.info, 'work continued');
      invalid
        ..end(SpanStatus.success)
        ..end(SpanStatus.error);
      await chronicler.flush();

      expect(chronicler.diagnosticCounts[DiagnosticReason.invalidRecord], BigInt.one);
      final records = exporter.batches.expand((batch) => batch.records).toList();
      expect((records.single as LogRecord).payload.message, 'work continued');
      expect(records.single.envelope.traceId, isNotNull);
      expect(records.whereType<SpanRecord>(), isEmpty);
    });
  });
}
