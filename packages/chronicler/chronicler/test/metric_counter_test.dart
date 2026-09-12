import 'package:chronicler/chronicler.dart';
import 'package:chronicler/src/runtime.dart' show ChroniclerMetricFixture;
import 'package:context/context.dart';
import 'package:test/test.dart';

import 'support/async.dart';
import 'support/exporter.dart';
import 'support/metric_clock.dart';

void main() {
  group('ChroniclerCounter', () {
    test('should export one delta aggregate for a measured interval', () async {
      final exporter = TestExporter(acceptImmediately: true);
      final chronicler = Chronicler(
        appId: 'app',
        release: 'release',
        source: ChroniclerSource.server,
        exporter: exporter,
        options: const ChroniclerOptions(
          delivery: DeliveryOptions(maxBatchRecords: 1),
          metrics: MetricOptions(interval: Duration(milliseconds: 1)),
        ),
      );
      final context = Context().withChronicler(chronicler.recorder);

      context.metrics.counter('orders.completed', unit: 'orders')
        ..add(2, attributes: {'channel': 'mobile'})
        ..add(3, attributes: {'channel': 'mobile'});
      await waitForCondition(() => exporter.batches.isNotEmpty);

      final record = exporter.batches.single.records.single as MetricRecord;
      expect(record.envelope.userId, isNull);
      expect(record.envelope.traceId, isNull);
      expect(record.envelope.timestamp, record.payload.intervalEnd);
      expect(record.payload.name, 'orders.completed');
      expect(record.payload.instrument, MetricInstrument.counter);
      expect(record.payload.unit, 'orders');
      expect(record.payload.attributes, {'channel': 'mobile'});
      expect(record.payload.temporality, MetricTemporality.delta);
      expect(record.payload.sum, 5);
      expect(record.payload.observationCount, 2);
      expect(record.payload.durationMicros, greaterThan(0));

      await chronicler.close();
    });

    test('should reuse definitions and reject conflicts and invalid setup', () async {
      final chronicler = _chronicler(TestExporter());
      final metrics = Context().withChronicler(chronicler.recorder).metrics;

      expect(
        identical(
          metrics.counter('requests', unit: 'items'),
          metrics.counter('requests', unit: 'items'),
        ),
        isTrue,
      );
      expect(
        () => metrics.counter('requests', unit: 'seconds'),
        throwsA(isA<ChroniclerConfigurationException>()),
      );
      for (final name in ['', '1request', 'request status', 'a' * 256]) {
        expect(
          () => metrics.counter(name),
          throwsA(isA<ChroniclerConfigurationException>()),
        );
      }
      for (final unit in ['', '\n', 'a' * 64]) {
        expect(
          () => metrics.counter('valid', unit: unit),
          throwsA(isA<ChroniclerConfigurationException>()),
        );
      }

      await chronicler.close();
      expect(
        () => _chronicler(
          TestExporter(),
          metrics: const MetricOptions(maxSeries: 0),
        ),
        throwsA(
          isA<ChroniclerConfigurationException>().having(
            (error) => error.setting,
            'setting',
            'maxSeries',
          ),
        ),
      );
    });

    test('should reject definitions outside the shared label byte limit', () async {
      final chronicler = _chronicler(
        TestExporter(),
        limits: const ChroniclerLimits(maxLabelBytes: 7),
      );
      final metrics = chronicler.recorder.metrics;

      expect(
        () => metrics.counter('requests'),
        throwsA(isA<ChroniclerConfigurationException>()),
      );
      expect(
        () => metrics.counter('ok', unit: 'seconds2'),
        throwsA(isA<ChroniclerConfigurationException>()),
      );

      await chronicler.close();
    });

    test('should canonicalize and redact dimensions before selecting a series', () async {
      final exporter = TestExporter(acceptImmediately: true);
      final clock = MetricClock();
      final chronicler = _chronicler(exporter);
      ChroniclerMetricFixture.overrideClocks(
        chronicler,
        now: () => clock.now,
        elapsed: () => clock.elapsed,
      );
      final context = Context()
          .withChronicler(chronicler.recorder)
          .withIdentity(userId: 'request-user');
      context.metrics.counter('requests')
        ..add(1, attributes: {'number': 1, 'token': 'first', 'enabled': true})
        ..add(2, attributes: {'enabled': true, 'token': 'second', 'number': 1.0})
        ..add(3, attributes: {'number': -0.0, 'token': 'third', 'enabled': true});
      clock
        ..advance(const Duration(seconds: 10))
        ..rewindWall(const Duration(seconds: 20));
      ChroniclerMetricFixture.rotate(chronicler);
      await waitForCondition(() => exporter.batches.expand((batch) => batch.records).length == 2);

      final records = exporter.batches
          .expand((batch) => batch.records)
          .cast<MetricRecord>()
          .toList();
      expect(records, hasLength(2));
      expect(records.map((record) => record.payload.sum), containsAll(<double>[3, 3]));
      expect(records.first.envelope.userId, isNull);
      expect(records.first.payload.attributes['token'], '[REDACTED]');
      expect(records.first.payload.durationMicros, 10000000);
      expect(records.first.payload.intervalEnd, clock.now);
      expect(
        records.first.payload.intervalEnd.isBefore(records.first.payload.intervalStart),
        isTrue,
      );

      await chronicler.close();
    });

    test('should reject invalid measurements without changing prior state', () async {
      final exporter = TestExporter(acceptImmediately: true);
      final clock = MetricClock();
      final chronicler = _chronicler(exporter);
      ChroniclerMetricFixture.overrideClocks(
        chronicler,
        now: () => clock.now,
        elapsed: () => clock.elapsed,
      );
      final counter = Context().withChronicler(chronicler.recorder).metrics.counter('requests')
        ..add(4)
        ..add(4, attributes: {'boundary': 'count'})
        ..add(-1)
        ..add(double.nan)
        ..add(double.infinity)
        ..add(1, attributes: {'nested': <String, Object?>{}})
        ..add(1, attributes: {'missing': null});
      ChroniclerMetricFixture.setCounterAggregate(
        chronicler,
        name: 'requests',
        count: 2,
        sum: double.maxFinite,
      );
      ChroniclerMetricFixture.setCounterAggregate(
        chronicler,
        name: 'requests',
        attributes: {'boundary': 'count'},
        count: 9007199254740991,
        sum: 4,
      );
      counter
        ..add(double.maxFinite)
        ..add(1, attributes: {'boundary': 'count'});
      clock.advance(const Duration(seconds: 10));
      ChroniclerMetricFixture.rotate(chronicler);
      await waitForCondition(() => exporter.batches.expand((batch) => batch.records).length == 2);

      final payloads = exporter.batches
          .expand((batch) => batch.records)
          .cast<MetricRecord>()
          .map((record) => record.payload)
          .toList();
      expect(payloads, hasLength(2));
      expect(
        payloads.singleWhere((payload) => payload.attributes.isEmpty),
        isA<MetricPayload>()
            .having((payload) => payload.sum, 'sum', double.maxFinite)
            .having((payload) => payload.observationCount, 'count', 2),
      );
      expect(
        payloads.singleWhere((payload) => payload.attributes.isNotEmpty),
        isA<MetricPayload>()
            .having((payload) => payload.sum, 'sum', 4)
            .having((payload) => payload.observationCount, 'count', 9007199254740991),
      );
      expect(chronicler.diagnosticCounts[DiagnosticReason.invalidMeasurement], BigInt.from(7));

      await chronicler.close();
    });

    test('should keep string, boolean, and numeric dimensions distinct', () async {
      final exporter = TestExporter(acceptImmediately: true);
      final clock = MetricClock();
      final chronicler = _chronicler(exporter);
      ChroniclerMetricFixture.overrideClocks(
        chronicler,
        now: () => clock.now,
        elapsed: () => clock.elapsed,
      );
      final counter = Context().withChronicler(chronicler.recorder).metrics.counter('types')
        ..add(1, attributes: {'value': 1})
        ..add(1, attributes: {'value': '1'})
        ..add(1, attributes: {'value': true});

      clock.advance(const Duration(seconds: 10));
      ChroniclerMetricFixture.rotate(chronicler);
      await waitForCondition(() => exporter.batches.expand((batch) => batch.records).length == 3);

      expect(
        exporter.batches.expand((batch) => batch.records),
        hasLength(3),
      );
      expect(counter, isA<ChroniclerCounter>());
      await chronicler.close();
    });

    test(
      'should enforce instrument and series capacities without disabling existing series',
      () async {
        final exporter = TestExporter(acceptImmediately: true);
        final clock = MetricClock();
        final chronicler = _chronicler(
          exporter,
          metrics: const MetricOptions(
            maxInstruments: 1,
            maxSeries: 1,
            maxSeriesPerInstrument: 1,
          ),
        );
        ChroniclerMetricFixture.overrideClocks(
          chronicler,
          now: () => clock.now,
          elapsed: () => clock.elapsed,
        );
        final metrics = Context().withChronicler(chronicler.recorder).metrics;
        final counter = metrics.counter('requests')
          ..add(1, attributes: {'route': 'one'})
          ..add(2, attributes: {'route': 'two'})
          ..add(3, attributes: {'route': 'one'});
        expect(identical(metrics.counter('requests'), counter), isTrue);
        expect(
          () => metrics.counter('other'),
          throwsA(isA<ChroniclerConfigurationException>()),
        );
        clock.advance(const Duration(seconds: 10));
        ChroniclerMetricFixture.rotate(chronicler);
        await Future<void>.delayed(Duration.zero);

        final payload = (exporter.batches.single.records.single as MetricRecord).payload;
        expect(payload.sum, 4);
        expect(chronicler.diagnosticCounts[DiagnosticReason.seriesLimitReached], BigInt.one);

        await chronicler.close();
      },
    );
  });
}

Chronicler _chronicler(
  TestExporter exporter, {
  ChroniclerLimits limits = const ChroniclerLimits(),
  MetricOptions metrics = const MetricOptions(),
}) => Chronicler(
  appId: 'app',
  release: 'release',
  source: ChroniclerSource.server,
  exporter: exporter,
  options: ChroniclerOptions(
    delivery: const DeliveryOptions(maxBatchRecords: 1),
    limits: limits,
    metrics: metrics,
  ),
);
