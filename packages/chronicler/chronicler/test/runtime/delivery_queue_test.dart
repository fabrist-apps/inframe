import 'dart:async';

import 'package:chronicler/chronicler.dart';
import 'package:chronicler/src/runtime/delivery_queue.dart';
import 'package:conflux/effect.dart';
import 'package:conflux/moment.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

import '../support/exporter.dart';
import '../support/records.dart';

void main() {
  setUpAll(Chronicler.initialize);
  group('DeliveryQueue', () {
    test('should use five total attempts with default exponential ceilings', () {
      _expectRetrySchedule(
        options: const DeliveryOptions(maxBatchRecords: 1),
        randomValues: const [0.999999999999, 0.999999999999, 0.999999999999, 0.999999999999],
        delays: const [
          Duration(seconds: 1),
          Duration(seconds: 2),
          Duration(seconds: 4),
          Duration(seconds: 8),
        ],
      );
    });

    test('should cap retry ceilings and include both full-jitter boundaries', () {
      _expectRetrySchedule(
        options: const DeliveryOptions(
          maxBatchRecords: 1,
          maxAttempts: 6,
          initialRetryDelay: Duration(microseconds: 2),
          maxRetryDelay: Duration(microseconds: 3),
        ),
        randomValues: const [0.999999999999, 0.999999999999, 0, 0.5, 0.999999999999],
        delays: const [
          Duration(microseconds: 2),
          Duration(microseconds: 3),
          Duration.zero,
          Duration(microseconds: 2),
          Duration(microseconds: 3),
        ],
      );
    });

    test('should support ceilings larger than Random.nextInt permits', () {
      _expectRetrySchedule(
        options: const DeliveryOptions(
          maxBatchRecords: 1,
          maxAttempts: 2,
          initialRetryDelay: Duration(hours: 2),
          maxRetryDelay: Duration(hours: 2),
        ),
        randomValues: const [0.999999999999],
        delays: const [Duration(hours: 2)],
      );
    });

    test('should pass records in backoff and retain enqueue order when eligible', () {
      fakeAsync((time) {
        final exporter = TestExporter();
        final runtime = Runtime(clock: _QueueClock(time));
        final queue = DeliveryQueue(
          runtime: runtime,
          options: const DeliveryOptions(
            maxBatchRecords: 2,
            initialRetryDelay: Duration(milliseconds: 20),
          ),
          exporter: exporter,
          diagnostics: DiagnosticChannel(const DiagnosticOptions(), runtime: runtime),
          nextRandom: () => 0.999999999999,
        );
        final oldRecords = [testLogRecord('old-one'), testLogRecord('old-two')];
        final newRecords = [testLogRecord('new-one'), testLogRecord('new-two')];
        for (final record in oldRecords) {
          queue.enqueue(record, const ChroniclerCodec().encodeRecord(record).length);
        }
        time.elapse(Duration.zero);
        exporter.attempts.single.completer.complete(const ExportResult.retryable());
        time.flushMicrotasks();

        for (final record in newRecords) {
          queue.enqueue(record, const ChroniclerCodec().encodeRecord(record).length);
        }
        time.elapse(Duration.zero);
        expect(exporter.batches[1].records, newRecords);
        exporter.attempts[1].completer.complete(const ExportResult.accepted());
        time
          ..flushMicrotasks()
          ..elapse(const Duration(microseconds: 19999));
        expect(exporter.batches, hasLength(2));
        time.elapse(const Duration(microseconds: 1));
        expect(exporter.batches[2].records, oldRecords);
        exporter.attempts[2].completer.complete(const ExportResult.accepted());
        time.flushMicrotasks();
        _close(queue, runtime, time);
      });
    });
  });
}

void _expectRetrySchedule({
  required DeliveryOptions options,
  required List<double> randomValues,
  required List<Duration> delays,
}) {
  fakeAsync((time) {
    final exporter = TestExporter();
    final runtime = Runtime(clock: _QueueClock(time));
    final diagnostics = DiagnosticChannel(const DiagnosticOptions(), runtime: runtime);
    var randomCalls = 0;
    final queue = DeliveryQueue(
      runtime: runtime,
      options: options,
      exporter: exporter,
      diagnostics: diagnostics,
      nextRandom: () => randomValues[randomCalls++],
    );
    final record = testLogRecord('retry');
    queue.enqueue(record, const ChroniclerCodec().encodeRecord(record).length);
    time.elapse(Duration.zero);
    expect(exporter.attempts, hasLength(1));

    for (var index = 0; index < delays.length; index++) {
      exporter.attempts.last.completer.complete(const ExportResult.retryable());
      time.flushMicrotasks();
      final delay = delays[index];
      if (delay > Duration.zero) {
        time.elapse(delay - const Duration(microseconds: 1));
        expect(exporter.attempts, hasLength(index + 1));
        time.elapse(const Duration(microseconds: 1));
      } else {
        time.elapse(Duration.zero);
      }
      expect(exporter.attempts, hasLength(index + 2));
      expect(exporter.batches.last.records.single, same(record));
    }
    exporter.attempts.last.completer.complete(const ExportResult.retryable());
    time
      ..flushMicrotasks()
      ..elapse(options.maxRetryDelay);

    expect(exporter.attempts, hasLength(options.maxAttempts));
    expect(randomCalls, delays.length);
    expect(diagnostics.counts[DiagnosticReason.attemptsExhausted], BigInt.one);
    expect(diagnostics.counts[DiagnosticReason.exportFailed], isNull);
    _close(queue, runtime, time);
  });
}

void _close(DeliveryQueue queue, Runtime runtime, FakeAsync time) {
  DeliveryReport? report;
  unawaited(queue.close(finalize: () => const []).then((value) => report = value));
  time
    ..flushMicrotasks()
    ..elapse(Duration.zero);
  expect(report?.runtimeState, ChroniclerRuntimeState.closed);
  unawaited(runtime.close());
  time.flushMicrotasks();
  expect(time.pendingTimers, isEmpty);
}

final class _QueueClock implements Clock {
  _QueueClock(this.time);

  final FakeAsync time;
  final _system = SystemClock();

  @override
  Duration monotonic() => time.elapsed;

  @override
  UtcMoment wallTime() => _system.wallTime();

  @override
  CancellableWait sleep(Duration duration) => _system.sleep(duration);
}
