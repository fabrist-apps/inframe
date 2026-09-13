import 'package:chronicler/chronicler.dart';
import 'package:chronicler/src/runtime.dart' show ChroniclerTracingFixture;
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
        'traceparent': '00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01',
      });

      context.tracing.startRootSpan('server', parent: remote).end(SpanStatus.success);
      await Future<void>.delayed(Duration.zero);

      final span = exporter.batches.single.records.single as SpanRecord;
      expect(span.envelope.traceId, '4bf92f3577b34da6a3ce929d0e0e4736');
      expect(span.envelope.parentSpanId, '00f067aa0ba902b7');
    });

    test('should contain unexpected start and end failures', () async {
      final exporter = TestExporter();
      final chronicler = createTracingChronicler(exporter);
      final context = Context().withChronicler(chronicler.recorder);

      ChroniclerTracingFixture.failNextSpanStart(chronicler);
      final unstarted = context.tracing.startSpan('unstarted');
      unstarted.recorder.recordLog(LogSeverity.info, 'work continued');
      unstarted.end(SpanStatus.success);

      var elapsedCalls = 0;
      ChroniclerTracingFixture.overrideClocks(
        chronicler,
        now: () => DateTime.utc(2026),
        elapsed: () {
          elapsedCalls += 1;
          if (elapsedCalls == 2) throw StateError('clock failed');
          return Duration.zero;
        },
      );
      context.tracing.startSpan('unfinished')
        ..end(SpanStatus.success)
        ..end(SpanStatus.error);

      expect(chronicler.diagnosticCounts[DiagnosticReason.spanStartFailed], BigInt.one);
      expect(chronicler.diagnosticCounts[DiagnosticReason.spanEndFailed], BigInt.one);
      await Future<void>.delayed(Duration.zero);
      final records = exporter.batches.expand((batch) => batch.records).toList();
      expect(records.whereType<LogRecord>().single.envelope.traceId, isNull);
      expect(records.whereType<SpanRecord>(), isEmpty);
    });
  });
}
