import 'dart:async';

import 'package:chronicler/chronicler.dart';
import 'package:context/context.dart';
import 'package:test/test.dart';

import 'support/async.dart';
import 'support/exporter.dart';
import 'support/metric_aggregation.dart';

void main() {
  group('Chronicler metric lifecycle', () {
    test('should reject oversized dimensions before retaining a series', () async {
      final exporter = TestExporter(acceptImmediately: true);
      final chronicler = Chronicler(
        appId: 'app',
        release: 'release',
        source: ChroniclerSource.server,
        exporter: exporter,
        options: const ChroniclerOptions(
          delivery: DeliveryOptions(maxRecordBytes: 1024),
          metrics: MetricOptions(maxSeries: 1, maxSeriesPerInstrument: 1),
        ),
      );
      addTearDown(chronicler.close);
      chronicler.recorder.metrics.counter('requests')
        ..add(1, attributes: {'route': 'x' * 1024})
        ..add(2, attributes: {'route': '/orders'});

      final report = await chronicler.flush();

      expect(report.accepted, 1);
      expect(_sums(exporter), [2]);
      expect(chronicler.diagnosticCounts[DiagnosticReason.invalidMeasurement], BigInt.one);
      expect(chronicler.diagnosticCounts[DiagnosticReason.seriesLimitReached], isNull);
    });

    test('should seal a partial interval into the calling flush snapshot', () async {
      final exporter = TestExporter(acceptImmediately: true);
      final chronicler = _chronicler(exporter);
      final counter = Context().withChronicler(chronicler.recorder).metrics.counter('requests')
        ..add(2);
      final firstFlush = chronicler.flush();
      counter.add(3);

      final firstReport = await firstFlush;
      expect(firstReport.accepted, 1);
      expect(_sums(exporter), [2]);

      final secondReport = await chronicler.flush();
      expect(secondReport.accepted, 1);
      expect(_sums(exporter), [2, 3]);

      await chronicler.close();
    });

    test('should restart the full interval after a partial flush', () async {
      final exporter = TestExporter(acceptImmediately: true);
      final timers = <_ManualTimer>[];
      await runZoned(
        () async {
          final chronicler = _chronicler(
            exporter,
            metricInterval: const Duration(milliseconds: 100),
          );
          final counter = chronicler.recorder.metrics.counter('requests')..add(1);

          await chronicler.flush();
          counter.add(2);
          final staleTimer = timers.first;
          final currentTimer = timers.last;

          staleTimer.fire();
          await Future<void>.delayed(Duration.zero);
          expect(_sums(exporter), [1]);

          currentTimer.fire();
          await waitForCondition(() => _sums(exporter).length == 2);
          expect(_sums(exporter), [1, 2]);
          await chronicler.close();
        },
        zoneSpecification: ZoneSpecification(
          createTimer: (self, parent, zone, duration, callback) {
            if (duration == const Duration(milliseconds: 100)) {
              final timer = _ManualTimer(callback);
              timers.add(timer);
              return timer;
            }
            return parent.createTimer(zone, duration, callback);
          },
        ),
      );
    });

    test('should discard unfinished and queued metrics while retaining handles', () async {
      final exporter = TestExporter(acceptImmediately: true);
      final timers = <_ManualTimer>[];
      const interval = Duration(seconds: 17);
      await runZoned(
        () async {
          final chronicler = _chronicler(
            exporter,
            maxBatchRecords: 10,
            batchInterval: const Duration(minutes: 1),
            metricInterval: interval,
          );
          final metrics = chronicler.recorder.metrics;
          final counter = metrics.counter('requests')..add(1);
          timers.single.fire();
          counter.add(5);

          chronicler.setCollectionEnabled(ChroniclerSignal.metrics, false);
          counter.add(10);
          chronicler.setCollectionEnabled(ChroniclerSignal.metrics, true);
          expect(identical(metrics.counter('requests'), counter), isTrue);
          counter.add(2);
          final report = await chronicler.flush();

          expect(report.accepted, 1);
          expect(_sums(exporter), [2]);
          expect(
            chronicler.diagnosticCounts[DiagnosticReason.collectionDisabled],
            BigInt.from(2),
          );
          await chronicler.close();
        },
        zoneSpecification: ZoneSpecification(
          createTimer: (self, parent, zone, duration, callback) {
            if (duration != interval) return parent.createTimer(zone, duration, callback);
            final timer = _ManualTimer(callback);
            timers.add(timer);
            return timer;
          },
        ),
      );
    });

    test('should seal pending metrics during close after blocking new recording', () async {
      final exporter = TestExporter(acceptImmediately: true);
      final chronicler = _chronicler(exporter);
      final counter = Context().withChronicler(chronicler.recorder).metrics.counter('requests')
        ..add(4);

      final close = chronicler.close();
      counter.add(8);
      final report = await close;

      expect(report.accepted, 1);
      expect(report.runtimeState, ChroniclerRuntimeState.closed);
      expect(_sums(exporter), [4]);
      expect(chronicler.diagnosticCounts[DiagnosticReason.runtimeClosed], BigInt.one);
    });

    test('should include an immediately dropped aggregate in flush accounting', () async {
      final exporter = TestExporter(acceptImmediately: true);
      final chronicler = _chronicler(
        exporter,
        maxPendingRecords: 1,
        batchInterval: const Duration(minutes: 1),
      );
      final context = Context().withChronicler(chronicler.recorder);
      context.logs.info('occupies queue');
      context.metrics.counter('requests').add(1);

      final report = await chronicler.flush();

      expect(report.accepted, 1);
      expect(report.dropped, {DropReason.queueFull: 1});
      expect(report.pending, 0);
      expect(report.accepted + report.dropped.values.single + report.pending, 2);
      await chronicler.close();
    });

    test('should retry immutable aggregates while newer measurements accumulate', () async {
      final exporter = TestExporter();
      final chronicler = _chronicler(
        exporter,
        maxAttempts: 2,
        retryDelay: const Duration(milliseconds: 1),
      );
      final counter = Context().withChronicler(chronicler.recorder).metrics.counter('requests')
        ..add(1);

      final firstFlush = chronicler.flush();
      await waitForCondition(() => exporter.attempts.isNotEmpty);
      final original = exporter.batches.single.records.single as MetricRecord;
      counter.add(9);
      exporter.attempts.single.completer.complete(const ExportResult.retryable());
      await waitForCondition(() => exporter.attempts.length == 2);

      final retry = exporter.batches.last.records.single as MetricRecord;
      expect(retry.envelope.eventId, original.envelope.eventId);
      expect(retry.payload, original.payload);
      exporter.attempts.last.completer.complete(const ExportResult.accepted());
      expect((await firstFlush).accepted, 1);

      final secondFlush = chronicler.flush();
      await waitForCondition(() => exporter.attempts.length == 3);
      expect(
        (exporter.batches.last.records.single as MetricRecord).payload.sum,
        9,
      );
      exporter.attempts.last.completer.complete(const ExportResult.accepted());
      expect((await secondFlush).accepted, 1);
      await chronicler.close();
    });

    test('should reject hooks that rewrite metric interval identity', () async {
      final exporter = TestExporter(acceptImmediately: true);
      final chronicler = _chronicler(
        exporter,
        redaction: RedactionOptions(
          beforeRecord: (record) {
            final metric = record as MetricRecord;
            return metric.copyWith(
              payload: metric.payload.copyWith(name: 'rewritten'),
            );
          },
        ),
      );
      Context().withChronicler(chronicler.recorder).metrics.counter('requests').add(1);

      final report = await chronicler.flush();

      expect(report.accepted, 0);
      expect(report.dropped, {DropReason.invalidRecord: 1});
      expect(exporter.batches, isEmpty);
      await chronicler.close();
    });

    test('should contain record construction failures and start a fresh interval', () {
      var fail = true;
      final harness = MetricHarness(
        createRecord: (payload) {
          if (fail) {
            fail = false;
            throw StateError('record construction failed');
          }
          return MetricHarness.record(payload);
        },
      );
      final counter = harness.metrics.counter('requests')..add(1);
      expect(harness.seal(), isEmpty);
      counter.add(2);
      expect(harness.seal().single.payload.sum, 2);
      expect(harness.reasons, [DiagnosticReason.invalidRecord]);
    });

    test('should validate finalized dimensions with the metric attribute limit', () async {
      final exporter = TestExporter(acceptImmediately: true);
      final chronicler = Chronicler(
        appId: 'app',
        release: 'release',
        source: ChroniclerSource.server,
        exporter: exporter,
        options: const ChroniclerOptions(
          metrics: MetricOptions(maxAttributes: 2),
        ),
      );
      chronicler.recorder.metrics
          .counter('requests')
          .add(
            1,
            attributes: {'route': '/orders', 'method': 'GET'},
          );

      final report = await chronicler.flush();

      expect(report.accepted, 1);
      expect(report.dropped, isEmpty);
      await chronicler.close();
    });

    for (final invalid in <String, MetricPayload Function(MetricPayload)>{
      'negative counter sum': (payload) => payload.copyWith(sum: -1),
      'nested dimension': (payload) => payload.copyWith(
        attributes: {
          'nested': {'value': 1},
        },
      ),
      'null dimension': (payload) => payload.copyWith(attributes: {'missing': null}),
    }.entries) {
      test('should reject a hook-created ${invalid.key}', () async {
        final exporter = TestExporter(acceptImmediately: true);
        final chronicler = _chronicler(
          exporter,
          redaction: RedactionOptions(
            beforeRecord: (record) {
              final metric = record as MetricRecord;
              return metric.copyWith(payload: invalid.value(metric.payload));
            },
          ),
        );
        chronicler.recorder.metrics.counter('requests').add(1);
        final report = await chronicler.flush();
        expect(report.accepted, 0);
        expect(report.dropped, {DropReason.invalidRecord: 1});
        expect(exporter.batches, isEmpty);
        await chronicler.close();
      });
    }

    test('should keep interval scheduling paused while metrics are disabled', () async {
      var metricTimers = 0;
      await runZoned(
        () async {
          final chronicler = Chronicler(
            appId: 'app',
            release: 'release',
            source: ChroniclerSource.server,
            exporter: TestExporter(acceptImmediately: true),
            options: const ChroniclerOptions(
              enabledSignals: {
                ChroniclerSignal.logs,
                ChroniclerSignal.events,
                ChroniclerSignal.traces,
                ChroniclerSignal.errors,
              },
              metrics: MetricOptions(interval: Duration(milliseconds: 10)),
            ),
          );
          chronicler.recorder.metrics.counter('requests');
          await chronicler.flush();
          await Future<void>.delayed(const Duration(milliseconds: 25));
          await chronicler.close();
        },
        zoneSpecification: ZoneSpecification(
          createTimer: (self, parent, zone, duration, callback) {
            if (duration == const Duration(milliseconds: 10)) metricTimers++;
            return parent.createTimer(zone, duration, callback);
          },
        ),
      );

      expect(metricTimers, 0);
    });

    test('should retain only one active timer when first enabled', () async {
      final timers = <_ManualTimer>[];
      await runZoned(
        () async {
          final chronicler = Chronicler(
            appId: 'app',
            release: 'release',
            source: ChroniclerSource.server,
            exporter: TestExporter(acceptImmediately: true),
            options: const ChroniclerOptions(
              enabledSignals: {
                ChroniclerSignal.logs,
                ChroniclerSignal.events,
                ChroniclerSignal.traces,
                ChroniclerSignal.errors,
              },
              metrics: MetricOptions(interval: Duration(milliseconds: 10)),
            ),
          )..setCollectionEnabled(ChroniclerSignal.metrics, true);

          expect(timers.where((timer) => timer.isActive), hasLength(1));
          await chronicler.close();
        },
        zoneSpecification: ZoneSpecification(
          createTimer: (self, parent, zone, duration, callback) {
            if (duration == const Duration(milliseconds: 10)) {
              final timer = _ManualTimer(callback);
              timers.add(timer);
              return timer;
            }
            return parent.createTimer(zone, duration, callback);
          },
        ),
      );
    });
  });
}

Chronicler _chronicler(
  TestExporter exporter, {
  Duration batchInterval = const Duration(seconds: 5),
  int maxAttempts = 5,
  int maxBatchRecords = 1,
  int maxPendingRecords = 5000,
  Duration metricInterval = const Duration(minutes: 1),
  RedactionOptions redaction = const RedactionOptions(),
  Duration retryDelay = const Duration(seconds: 1),
}) => Chronicler(
  appId: 'app',
  release: 'release',
  source: ChroniclerSource.server,
  exporter: exporter,
  options: ChroniclerOptions(
    delivery: DeliveryOptions(
      maxAttempts: maxAttempts,
      maxBatchRecords: maxBatchRecords,
      maxPendingRecords: maxPendingRecords,
      batchInterval: batchInterval,
      initialRetryDelay: retryDelay,
      maxRetryDelay: retryDelay,
    ),
    metrics: MetricOptions(interval: metricInterval),
    redaction: redaction,
  ),
);

List<double?> _sums(TestExporter exporter) => exporter.batches
    .expand((batch) => batch.records)
    .cast<MetricRecord>()
    .map((record) => record.payload.sum)
    .toList();

final class _ManualTimer implements Timer {
  _ManualTimer(this._callback);

  final void Function() _callback;

  @override
  int tick = 0;

  @override
  bool isActive = true;

  @override
  void cancel() => isActive = false;

  void fire() {
    if (!isActive) return;
    isActive = false;
    tick = 1;
    _callback();
  }
}
