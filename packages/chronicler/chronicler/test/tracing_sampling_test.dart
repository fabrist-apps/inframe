import 'dart:async';
import 'dart:collection';

import 'package:chronicler/chronicler.dart';
import 'package:chrono_id/chrono_id.dart';
import 'package:context/context.dart';
import 'package:test/test.dart';

import 'support/exporter.dart';
import 'support/trace_controller.dart';

void main() {
  group('Chronicler tracing sampling', () {
    test('should diagnose and abandon spans when ID generation fails', () {
      final bed = TraceControllerTestBed(
        generateId: (_) => throw UnsupportedError('ID generation unavailable'),
      );

      expect(bed.start('ID failure'), isNull);
      expect(bed.records, isEmpty);
      expect(bed.diagnostics.counts[DiagnosticReason.invalidRecord], BigInt.one);
    });

    test('should diagnose and abandon spans when sampling fails', () {
      final bed = TraceControllerTestBed(
        options: const ChroniclerOptions(sampling: SamplingOptions(traces: 0.5)),
        nextRandom: () => throw UnsupportedError('sampling unavailable'),
      );

      expect(bed.start('sampling failure'), isNull);
      expect(bed.records, isEmpty);
      expect(bed.diagnostics.counts[DiagnosticReason.invalidRecord], BigInt.one);
    });

    test('should keep correlation and callbacks for an unsampled trace', () async {
      final exporter = TestExporter();
      final chronicler = Chronicler(
        appId: 'app',
        release: 'release',
        source: ChroniclerSource.server,
        exporter: exporter,
        options: const ChroniclerOptions(
          delivery: DeliveryOptions(maxBatchRecords: 2),
          sampling: SamplingOptions(traces: 0),
        ),
      );
      var calls = 0;

      final value = await Context()
          .withChronicler(chronicler.recorder)
          .span(
            'unsampled root',
            run: (root) => root.span(
              'unsampled child',
              run: (child) {
                calls++;
                child.logs.info('still captured');
                child.events.track('still captured');
                return 7;
              },
            ),
          );
      await Future<void>.delayed(Duration.zero);

      expect(value, 7);
      expect(calls, 1);
      final records = exporter.batches.single.records;
      final log = records.whereType<LogRecord>().single;
      final event = records.whereType<ProductEventRecord>().single;
      expect(ChronoID.isValid(log.envelope.traceId!, prefix: 'trc'), isTrue);
      expect(ChronoID.isValid(log.envelope.spanId!, prefix: 'spn'), isTrue);
      expect(event.envelope.traceId, log.envelope.traceId);
      expect(event.envelope.spanId, log.envelope.spanId);
      expect(chronicler.diagnosticCounts[DiagnosticReason.sampledOut], BigInt.one);
    });

    test('should skip attributes and suppress spans after collection is disabled', () async {
      final exporter = TestExporter();
      final chronicler = Chronicler(
        appId: 'app',
        release: 'release',
        source: ChroniclerSource.server,
        exporter: exporter,
        options: const ChroniclerOptions(
          sampling: SamplingOptions(traces: 0),
        ),
      );
      final recorder = chronicler.recorder;
      final unreadable = _UnreadableAttributes();

      await recorder.span(
        'unsampled',
        attributes: unreadable,
        run: (_) {},
      );
      expect(unreadable.reads, 0);

      final recordingExporter = TestExporter(acceptImmediately: true);
      final recording = Chronicler(
        appId: 'app',
        release: 'release',
        source: ChroniclerSource.server,
        exporter: recordingExporter,
      );
      await recording.recorder.span(
        'disabled while active',
        attributes: {'secret': 'retained'},
        run: (active) {
          recording.setCollectionEnabled(ChroniclerSignal.traces, enabled: false);
          active.setSpanAttributes(unreadable);
        },
      );
      await recording.flush();
      expect(unreadable.reads, 0);
      expect(recordingExporter.batches, isEmpty);
      await recording.close();
      await chronicler.close();
    });

    test('should choose sampling once per root and inherit it in children', () {
      var randomCalls = 0;
      final bed = TraceControllerTestBed(
        options: const ChroniclerOptions(sampling: SamplingOptions(traces: 0.5)),
        nextRandom: () => [0.25, 0.75][randomCalls++],
      );

      final root = bed.start('sampled root');
      final child = bed.start('sampled child', parent: root);
      bed.controller.finish(child, SpanStatus.success);
      bed.controller.finish(root, SpanStatus.success);
      final excluded = bed.start('excluded root');
      final excludedChild = bed.start('excluded child', parent: excluded);
      bed.controller.finish(excludedChild, SpanStatus.success);
      bed.controller.finish(excluded, SpanStatus.success);

      expect(randomCalls, 2);
      expect(bed.records.map((span) => span.payload.name), ['sampled child', 'sampled root']);
      expect(bed.records.first.envelope.traceId, bed.records.last.envelope.traceId);
      expect(bed.records.first.envelope.parentSpanId, bed.records.last.envelope.spanId);
      expect(bed.diagnostics.counts[DiagnosticReason.sampledOut], BigInt.one);
    });
  });
}

final class _UnreadableAttributes extends MapBase<String, Object?> {
  int reads = 0;

  @override
  Iterable<String> get keys {
    reads++;
    throw StateError('attributes were read');
  }

  @override
  Object? operator [](Object? key) {
    reads++;
    throw StateError('attributes were read');
  }

  @override
  void operator []=(String key, Object? value) => throw UnsupportedError('read only');

  @override
  void clear() => throw UnsupportedError('read only');

  @override
  Object? remove(Object? key) => throw UnsupportedError('read only');
}
