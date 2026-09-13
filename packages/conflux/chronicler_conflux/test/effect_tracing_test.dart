import 'dart:async';

import 'package:chronicler/chronicler.dart';
import 'package:chronicler/src/runtime.dart' show ChroniclerTracingFixture;
import 'package:chronicler_conflux/chronicler_conflux.dart';
import 'package:conflux/conflux.dart';
import 'package:context/context.dart';
import 'package:test/test.dart';

import 'support/memory_exporter.dart';

void main() {
  group('Chronicler Effect tracing', () {
    test('should stay lazy and create isolated spans for every execution', () async {
      final harness = _Harness();
      addTearDown(harness.close);
      var executions = 0;
      final operation = Effect.build<int, Never>(($) async {
        executions += 1;
        await $(
          Effect.all([
            Effect.sync<void>((context) => context.logs.info('left')).withSpan('left'),
            Effect.sync<void>((context) => context.logs.info('right')).withSpan('right'),
          ], concurrency: 2),
        );
        return executions;
      }).withSpan('operation');

      expect(executions, 0);
      expect(harness.exporter.records, isEmpty);

      expect(await harness.runtime.run(operation), isA<Succeeded<int, Never>>());
      expect(await harness.runtime.run(operation), isA<Succeeded<int, Never>>());
      await harness.chronicler.flush();

      final spans = harness.exporter.records.whereType<SpanRecord>().toList();
      final parents = spans.where((span) => span.payload.name == 'operation').toList();
      final children = spans.where((span) => span.payload.name != 'operation').toList();
      expect(parents, hasLength(2));
      expect(parents.map((span) => span.envelope.spanId).toSet(), hasLength(2));
      expect(children, hasLength(4));
      expect(
        children.map((span) => span.envelope.parentSpanId).toSet(),
        parents.map((span) => span.envelope.spanId).toSet(),
      );
      final childIds = children.map((span) => span.envelope.spanId).toSet();
      expect(
        harness.exporter.records.whereType<LogRecord>().map((log) => log.envelope.spanId),
        everyElement(isIn(childIds)),
      );
    });

    test('should end after owned cleanup and classify complete causes', () async {
      final events = <String>[];
      final harness = _Harness(
        options: ChroniclerOptions(
          redaction: RedactionOptions(
            beforeRecord: (record) {
              if (record case SpanRecord()) events.add('span');
              return record;
            },
          ),
        ),
      );
      addTearDown(harness.close);
      final pending = Completer<void>();
      final started = Completer<void>();
      final operation = Effect.build<void, String>(($) async {
        await $.acquireRelease(
          Effect.succeed<void, Never>(null),
          release: (_, _) => Effect.sync((_) {
            events.add('release');
            throw StateError('cleanup failed');
          }),
        );
        await $(
          Effect.tryFuture<void, String>(
            (_) {
              started.complete();
              return pending.future;
            },
            onError: (error, _, _) => '$error',
          ),
        );
      }).withSpan('cancelled with cleanup failure');
      final fiber = harness.runtime.fork(operation);
      await started.future;

      final exit = await fiber.interrupt('stop');
      pending.complete();
      await harness.chronicler.flush();

      expect(exit, isA<Failed<void, String>>());
      expect((exit as Failed<void, String>).cause, isA<Sequential<String>>());
      expect(events, ['release', 'span']);
      expect(
        harness.exporter.records.whereType<SpanRecord>().single.payload.status,
        SpanStatus.error,
      );
    });

    test('should classify interruption-only failure as cancelled', () async {
      final harness = _Harness();
      addTearDown(harness.close);
      final pending = Completer<void>();
      final started = Completer<void>();
      final fiber = harness.runtime.fork(
        Effect.tryFuture<void, String>(
          (_) {
            started.complete();
            return pending.future;
          },
          onError: (error, _, _) => '$error',
        ).withSpan('cancelled'),
      );
      await started.future;

      final exit = await fiber.interrupt('stop');
      pending.complete();
      await harness.chronicler.flush();

      expect((exit as Failed<void, String>).cause, isA<Interrupted<String>>());
      expect(
        harness.exporter.records.whereType<SpanRecord>().single.payload.status,
        SpanStatus.cancelled,
      );
    });

    test('should preserve typed causes and never capture error occurrences', () async {
      final harness = _Harness();
      addTearDown(harness.close);
      const expected = Expected<String>('declined');
      final defectError = StateError('broken');
      final defectStack = StackTrace.fromString('original defect stack');
      final defect = Defect<String>(defectError, defectStack);

      final expectedExit = await harness.runtime.run(
        Effect.failCause<int, String>(expected).withSpan('expected'),
      );
      final defectExit = await harness.runtime.run(
        Effect.failCause<int, String>(defect).withSpan('defect'),
      );
      await harness.chronicler.flush();

      expect(identical((expectedExit as Failed<int, String>).cause, expected), isTrue);
      expect(identical((defectExit as Failed<int, String>).cause, defect), isTrue);
      expect(defect.stackTrace, same(defectStack));
      expect(
        harness.exporter.records.whereType<SpanRecord>().map((span) => span.payload.status),
        everyElement(SpanStatus.error),
      );
      expect(harness.exporter.records.whereType<ErrorRecord>(), isEmpty);
    });

    test('should avoid acquisition after prior cancellation', () async {
      final harness = _Harness();
      addTearDown(harness.close);
      var ran = false;
      final fiber = harness.runtime.fork(
        Effect.sync<void>((_) => ran = true).withSpan('never started'),
      );

      final exit = await fiber.interrupt('stop');
      await harness.chronicler.flush();

      expect(exit, isA<Failed<void, Never>>());
      expect(ran, isFalse);
      expect(harness.exporter.records.whereType<SpanRecord>(), isEmpty);
    });

    test('should preserve setup defects before running instrumented work', () async {
      final runtime = Runtime();
      addTearDown(runtime.close);
      var ran = false;

      final exit = await runtime.run(
        Effect.sync<void>((_) => ran = true).withSpan('missing setup'),
      );

      expect(ran, isFalse);
      final cause = (exit as Failed<void, Never>).cause;
      expect(cause, isA<Defect<Never>>());
      expect((cause as Defect<Never>).error, isA<MissingContextValue>());
    });

    test('should continue a remote parent for explicit root spans', () async {
      final harness = _Harness();
      addTearDown(harness.close);
      final parent = TracePropagation.extract({
        'traceparent': '00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01',
      });

      await harness.runtime.run(
        Effect.succeed<void, Never>(null).withRootSpan('server', parent: parent),
      );
      await harness.chronicler.flush();

      final span = harness.exporter.records.whereType<SpanRecord>().single;
      expect(span.envelope.traceId, '4bf92f3577b34da6a3ce929d0e0e4736');
      expect(span.envelope.parentSpanId, '00f067aa0ba902b7');
    });

    test('should preserve outcomes when SDK span telemetry fails', () async {
      final harness = _Harness();
      addTearDown(harness.close);
      ChroniclerTracingFixture.failNextSpanStart(harness.chronicler);

      final afterStartFailure = await harness.runtime.run(
        Effect.succeed<int, Never>(1).withSpan('start failure'),
      );

      var elapsedCalls = 0;
      ChroniclerTracingFixture.overrideClocks(
        harness.chronicler,
        now: () => DateTime.utc(2026),
        elapsed: () {
          elapsedCalls += 1;
          if (elapsedCalls == 2) throw StateError('clock failed');
          return Duration.zero;
        },
      );
      final afterEndFailure = await harness.runtime.run(
        Effect.succeed<int, Never>(2).withSpan('end failure'),
      );

      expect((afterStartFailure as Succeeded<int, Never>).value, 1);
      expect((afterEndFailure as Succeeded<int, Never>).value, 2);
      expect(
        harness.chronicler.diagnosticCounts[DiagnosticReason.spanStartFailed],
        BigInt.one,
      );
      expect(
        harness.chronicler.diagnosticCounts[DiagnosticReason.spanEndFailed],
        BigInt.one,
      );
    });
  });
}

final class _Harness {
  _Harness({
    ChroniclerOptions options = const ChroniclerOptions(),
  }) {
    chronicler = Chronicler(
      appId: 'app',
      release: 'test',
      source: ChroniclerSource.server,
      exporter: exporter,
      options: options,
    );
    runtime = Runtime(
      context: Context().withChronicler(chronicler.recorder),
    );
  }

  final exporter = MemoryExporter();
  late final Chronicler chronicler;
  late final Runtime runtime;

  Future<void> close() async {
    await runtime.close();
    await chronicler.close();
  }
}
