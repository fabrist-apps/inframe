import 'package:chronicler/chronicler.dart';
import 'package:chronicler/src/metrics/aggregation.dart';
import 'package:chronicler/src/runtime/record_processing.dart';
import 'package:test/test.dart';

import 'metric_clock.dart';
import 'records.dart';

/// Exercises the real registry with controlled clocks and a recording sink.
final class MetricHarness {
  MetricHarness({
    MetricOptions options = const MetricOptions(),
    MetricRecord Function(MetricPayload)? createRecord,
  }) {
    final processor = RecordProcessor(
      codec: const ChroniclerCodec(),
      redaction: const RedactionOptions(),
      maxRecordBytes: 64 * 1024,
    );
    metrics = MetricAggregation(
      options: options,
      canRecord: () => true,
      diagnose: reasons.add,
      redact: processor.redactAttributes,
      createRecord: createRecord ?? record,
      finalize: records.add,
      startEnabled: true,
      now: () => clock.now,
      elapsed: () => clock.elapsed,
    );
    addTearDown(metrics.stop);
  }

  final clock = MetricClock();
  final records = <MetricRecord>[];
  final reasons = <DiagnosticReason>[];
  late final MetricAggregation metrics;

  List<MetricRecord> seal() {
    final finalized = metrics.seal(scheduleNext: false);
    records.addAll(finalized);
    return finalized;
  }

  static MetricRecord record(MetricPayload payload) => MetricRecord(
    envelope: testEnvelope().copyWith(timestamp: payload.intervalEnd),
    payload: payload,
  );
}
