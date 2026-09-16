import 'package:chronicler/chronicler.dart';
import 'package:conflux/effect.dart';
import 'package:test/test.dart';

import 'support/metric_aggregation.dart';
import 'support/metric_clock.dart';

void main() {
  setUpAll(Chronicler.initialize);
  late MetricClock clock;
  late Runtime runtime;

  setUp(() {
    clock = MetricClock();
    runtime = Runtime(clock: clock);
  });
  tearDown(() => runtime.close());

  group('MetricAggregation', () {
    test('should start the interval deadline when scheduling, before execution', () async {
      final harness = MetricHarness(runtime: runtime);
      harness.metrics.counter('requests').add(3);

      clock.advance(const Duration(seconds: 10));
      await _settle();

      expect(harness.records.single.payload.sum, 3);
    });

    test('should seal intervals using the runtime clock and cancel on stop', () async {
      final harness = MetricHarness(
        runtime: runtime,
      );
      final start = clock.now;
      harness.metrics.counter('requests').add(3);
      await _settle();

      clock.advance(const Duration(seconds: 9));
      await _settle();
      expect(harness.records, isEmpty);
      clock.advance(const Duration(seconds: 1));
      await _settle();

      final payload = harness.records.single.payload;
      expect(payload.sum, 3);
      expect(payload.intervalStart, start);
      expect(payload.intervalEnd, clock.now);
      expect(payload.durationMicros, 10000000);
      harness.metrics.stop();
      await _settle();
      expect(clock.activeWaits, 0);
    });

    test('should discard an elapsed callback when disabled before it resumes', () async {
      final harness = MetricHarness(
        runtime: runtime,
      );
      harness.metrics.counter('requests').add(3);
      await _settle();
      clock.advance(const Duration(seconds: 10));
      harness.metrics.disable();
      await _settle();
      expect(harness.records, isEmpty);
      expect(clock.activeWaits, 0);
    });
  });

  group('DiagnosticChannel', () {
    test('should retain a notification deadline before its task starts', () async {
      final notifications = <ChroniclerDiagnostic>[];
      final channel = DiagnosticChannel(
        DiagnosticOptions(
          notificationInterval: const Duration(seconds: 10),
          onDiagnostic: notifications.add,
        ),
        runtime: runtime,
      );
      addTearDown(channel.close);
      channel.record(DiagnosticReason.invalidRecord);
      await _settle();

      channel.record(DiagnosticReason.invalidRecord);
      clock.advance(const Duration(seconds: 10));
      await _settle();

      expect(notifications, hasLength(2));
    });

    test('should coalesce notifications against runtime monotonic time', () async {
      final notifications = <ChroniclerDiagnostic>[];
      final channel = DiagnosticChannel(
        DiagnosticOptions(
          notificationInterval: const Duration(seconds: 10),
          onDiagnostic: notifications.add,
        ),
        runtime: runtime,
      );
      addTearDown(channel.close);
      channel.record(DiagnosticReason.invalidRecord);
      await _settle();
      expect(notifications.single.count, BigInt.one);

      channel
        ..record(DiagnosticReason.invalidRecord)
        ..record(DiagnosticReason.invalidRecord);
      await _settle();
      clock.advance(const Duration(seconds: 9));
      await _settle();
      expect(notifications, hasLength(1));
      clock.advance(const Duration(seconds: 1));
      await _settle();
      expect(notifications.last.count, BigInt.two);
      expect(channel.counts[DiagnosticReason.invalidRecord], BigInt.from(3));

      channel
        ..record(DiagnosticReason.invalidRecord)
        ..close();
      await _settle();
      expect(clock.activeWaits, 0);
      clock.advance(const Duration(seconds: 10));
      await _settle();
      expect(notifications, hasLength(2));
    });
  });
}

Future<void> _settle() => Future<void>.delayed(Duration.zero);
