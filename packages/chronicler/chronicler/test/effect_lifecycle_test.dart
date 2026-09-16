import 'dart:async';

import 'package:chronicler/chronicler.dart';
import 'package:conflux/effect.dart';
import 'package:context/context.dart';
import 'package:test/test.dart';

import 'support/async.dart';
import 'support/exporter.dart';
import 'support/metric_clock.dart';

void main() {
  group('Chronicler Effect lifecycle', () {
    test('should contain an exporter future that fails immediately', () async {
      final chronicler = Chronicler(
        appId: 'app',
        release: '1',
        source: ChroniclerSource.server,
        exporter: _ImmediatelyFailingExporter(),
        options: const ChroniclerOptions(delivery: DeliveryOptions(maxAttempts: 1)),
      );
      addTearDown(chronicler.close);
      Context().withChronicler(chronicler.recorder).logs.info('record');
      final report = await chronicler.flush();
      expect(report.dropped, {DropReason.attemptsExhausted: 1});
    });

    test('should snapshot synchronously and keep batch deadlines from capture', () async {
      final clock = MetricClock();
      final exporter = TestExporter(acceptImmediately: true);
      final chronicler = _create(exporter, clock: clock);
      addTearDown(chronicler.close);
      final attributes = <String, Object?>{'value': 'original'};
      final capturedAt = clock.now;
      Context().withChronicler(chronicler.recorder).logs.info('record', attributes: attributes);
      attributes['value'] = 'changed';

      // No yield between capture and time advancing: starting a worker later
      // must not move the already-established batch deadline.
      clock.advance(const Duration(seconds: 5));
      await settleAsync();
      expect(exporter.batches, hasLength(1));
      final record = exporter.batches.single.records.single as LogRecord;
      expect(record.payload.attributes['value'], 'original');
      expect(record.envelope.timestamp, capturedAt);
    });

    test('should capture a flush snapshot at execution, not Effect construction', () async {
      final exporter = TestExporter(acceptImmediately: true);
      final chronicler = _create(exporter);
      addTearDown(chronicler.close);
      final flush = chronicler.flushEffect();
      Context().withChronicler(chronicler.recorder).logs.info('after construction');
      expect(exporter.batches, isEmpty);
      final report = await flush.runFuture();
      expect(report.accepted, 1);
    });

    test('should interrupt a flush caller without cancelling shared delivery', () async {
      final exporter = TestExporter();
      final chronicler = _create(exporter);
      final caller = Runtime();
      addTearDown(caller.close);
      addTearDown(() async {
        exporter.acceptRemaining();
        await chronicler.close();
      });
      Context().withChronicler(chronicler.recorder).logs.info('record');
      final waiting = caller.fork(chronicler.flushEffect());
      await waitForCondition(() => exporter.attempts.isNotEmpty);
      expect(await waiting.interrupt(), isA<Failed<DeliveryReport, Never>>());
      expect(exporter.attempts.single.cancelCount, 0);
      final nextFlush = chronicler.flushEffect().runFuture();
      exporter.attempts.single.completer.complete(const ExportResult.accepted());
      expect((await nextFlush).accepted, 1);
    });

    test('should bound a scope finalizer even when exporter cleanup never settles', () async {
      final clock = MetricClock();
      final exporter = TestExporter()..closeCompleter = Completer<void>();
      final chronicler = _create(exporter, clock: clock);
      final caller = Runtime();
      addTearDown(caller.close);
      DeliveryReport? shutdown;
      final operation = caller.run(
        Effect.build<void, Never>(($) {
          $.addFinalizer(
            chronicler.closeEffect().map((report, _) {
              shutdown = report;
            }),
          );
          Context().withChronicler(chronicler.recorder).logs.info('pending');
        }),
      );
      await waitForCondition(() => exporter.attempts.isNotEmpty);
      clock.advance(const Duration(seconds: 8));
      await waitForCondition(() => exporter.closeCount == 1);
      expect(exporter.attempts.single.cancelCount, 1);
      clock.advance(const Duration(seconds: 2));
      expect(await operation, isA<Succeeded<void, Never>>());
      expect(shutdown!.cleanupIncomplete, isTrue);
      expect(shutdown!.uncertainDropped, 1);
      expect(clock.activeWaits, 0);

      // Late transport failures stay observed and cannot mutate the report.
      exporter.attempts.single.completer.completeError(StateError('late failure'));
      exporter.closeCompleter!.complete();
      await settleAsync();
      expect(shutdown!.dropped, {DropReason.shutdown: 1});
    });

    test('should retain capacity after attempt timeout until transport settles', () async {
      final clock = MetricClock();
      final exporter = TestExporter();
      final chronicler = _create(exporter, clock: clock);
      addTearDown(() async {
        exporter.acceptRemaining();
        await chronicler.close();
      });
      final context = Context().withChronicler(chronicler.recorder);
      context.logs.info('first');
      final flush = chronicler.flush(timeout: const Duration(seconds: 30));
      await waitForCondition(() => exporter.attempts.isNotEmpty);
      context.logs.info('second');
      clock.advance(const Duration(seconds: 10));
      await settleAsync();
      expect(exporter.attempts.single.cancelCount, 1);
      expect(exporter.batches, hasLength(1));
      exporter.attempts.single.completer.complete(const ExportResult.accepted());
      await waitForCondition(() => exporter.attempts.length == 2);
      expect((await flush).accepted, 1);
    });
  });
}

Chronicler _create(TestExporter exporter, {Clock? clock}) => Chronicler(
  appId: 'app',
  release: '1',
  source: ChroniclerSource.server,
  exporter: exporter,
  clock: clock,
);

final class _ImmediatelyFailingExporter implements ChroniclerExporter {
  @override
  ExportAttempt export(ChroniclerBatch batch) => _ImmediatelyFailingAttempt();

  @override
  Future<void> close() async {}
}

final class _ImmediatelyFailingAttempt implements ExportAttempt {
  @override
  final Future<ExportResult> result = Future.error(StateError('immediate failure'));

  @override
  void cancel() {}
}
