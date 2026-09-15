import 'package:chronicler/chronicler.dart';
import 'package:chronicler/src/metrics/aggregation.dart';
import 'package:chronicler/src/runtime/record_processing.dart';
import 'package:conflux/effect.dart';
import 'package:test/test.dart';

import 'metric_clock.dart';
import 'records.dart';

/// Exercises the real registry with controlled clocks and a recording sink.
final class MetricHarness {
  MetricHarness({
    MetricOptions options = const MetricOptions(),
    MetricRecord Function(MetricPayload)? createRecord,
    Runtime? runtime,
  }) {
    clock = runtime == null ? MetricClock() : runtime.clock as MetricClock;
    final execution = runtime ?? Runtime(clock: clock);
    if (runtime == null) addTearDown(execution.close);
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
      runtime: execution,
    );
    addTearDown(metrics.stop);
  }

  late final MetricClock clock;
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
