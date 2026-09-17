import 'dart:async';

import 'package:chronicler/chronicler.dart';
import 'package:context/context.dart';
import 'package:test/test.dart';

import 'support/exporter.dart';
import 'support/moments.dart';
import 'support/trace_controller.dart';
import 'support/tracing_support.dart';

void main() {
  setUpAll(Chronicler.initialize);
  group('Chronicler tracing lifecycle', () {
    test('should record nested callback spans and correlate logs', () async {
      final exporter = TestExporter(acceptImmediately: true);
      final chronicler = createTracingChronicler(exporter, maxBatchRecords: 3);
      final context = Context().withChronicler(chronicler.recorder);

      final result = await context.trace(
        'request',
        (request) => request.span(
          'database',
          (database) {
            database.logs.info('query complete');
            return 42;
          },
          kind: SpanKind.client,
        ),
        kind: SpanKind.server,
      );
      await chronicler.flush();

      expect(result, 42);
      final records = exporter.batches.single.records;
      final log = records.whereType<LogRecord>().single;
      final spans = records.whereType<SpanRecord>().toList();
      final child = spans.singleWhere((span) => span.payload.name == 'database');
      final parent = spans.singleWhere((span) => span.payload.name == 'request');
      expect(child.envelope.traceId, parent.envelope.traceId);
      expect(child.envelope.parentSpanId, parent.envelope.spanId);
      expect(log.envelope.traceId, child.envelope.traceId);
      expect(log.envelope.spanId, child.envelope.spanId);
      expect(child.payload.spanKind, SpanKind.client);
      expect(parent.payload.spanKind, SpanKind.server);
      expect(spans.map((span) => span.payload.status), everyElement(SpanStatus.success));
    });

    test('should preserve sync and async failures with their original stacks', () async {
      final exporter = TestExporter();
      final chronicler = createTracingChronicler(exporter, maxBatchRecords: 2);
      final context = Context().withChronicler(chronicler.recorder);
      final syncError = StateError('sync');
      final originalSyncStack = StackTrace.fromString('original sync stack');
      late StackTrace syncStack;
      try {
        context.spanSync<void>(
          'sync',
          (_) => Error.throwWithStackTrace(syncError, originalSyncStack),
        );
      } on Object catch (error, stackTrace) {
        expect(identical(error, syncError), isTrue);
        syncStack = stackTrace;
      }
      final asyncError = StateError('async');
      final originalAsyncStack = StackTrace.fromString('original async stack');
      late StackTrace asyncStack;
      try {
        await context.span<void>(
          'async',
          (_) async => Error.throwWithStackTrace(asyncError, originalAsyncStack),
        );
      } on Object catch (error, stackTrace) {
        expect(identical(error, asyncError), isTrue);
        asyncStack = stackTrace;
      }
      expect(syncStack.toString(), originalSyncStack.toString());
      expect(asyncStack.toString(), originalAsyncStack.toString());

      await Future<void>.delayed(Duration.zero);
      final spans = exporter.batches.single.records.cast<SpanRecord>();
      expect(spans.map((span) => span.payload.status), everyElement(SpanStatus.error));
    });

    test('should keep concurrent branches and detached children isolated', () async {
      final exporter = TestExporter();
      final chronicler = createTracingChronicler(exporter, maxBatchRecords: 7);
      final base = Context().withChronicler(chronicler.recorder);
      late Context endedParent;
      final detached = Completer<void>();

      await base.trace(
        'parent',
        (parent) async {
          endedParent = parent;
          unawaited(parent.span('detached', (_) => detached.future));
          await Future.wait([
            parent.span('left', (left) async => left.logs.info('left')),
            parent.span('right', (right) async => right.logs.info('right')),
          ]);
        },
      );
      detached.complete();
      await Future<void>.delayed(Duration.zero);

      await endedParent.span('fresh', (_) {});
      await Future<void>.delayed(Duration.zero);
      final spans = exporter.batches
          .expand((batch) => batch.records)
          .whereType<SpanRecord>()
          .toList();
      final parent = spans.singleWhere((span) => span.payload.name == 'parent');
      for (final name in ['left', 'right', 'detached']) {
        expect(
          spans.singleWhere((span) => span.payload.name == name).envelope.parentSpanId,
          parent.envelope.spanId,
        );
      }
      final fresh = spans.singleWhere((span) => span.payload.name == 'fresh');
      expect(fresh.envelope.parentSpanId, isNull);
      expect(fresh.envelope.traceId, isNot(parent.envelope.traceId));
    });

    test('should return an exact Future from a misused sync wrapper', () async {
      final exporter = TestExporter();
      final chronicler = createTracingChronicler(exporter);
      final context = Context().withChronicler(chronicler.recorder);
      final original = Future<int>.value(7);

      final returned = context.spanSync<Future<int>>('sync misuse', (_) => original);

      expect(identical(returned, original), isTrue);
      expect(await returned, 7);
      expect(chronicler.diagnosticCounts[DiagnosticReason.syncCallbackReturnedFuture], BigInt.one);
    });

    test('should keep async spans open and explicit traces independent', () async {
      final exporter = TestExporter();
      final chronicler = createTracingChronicler(exporter, maxBatchRecords: 3);
      final base = Context().withChronicler(chronicler.recorder);
      final release = Completer<void>();
      late Context outerContext;

      final operation = base.span(
        'outer',
        (outer) async {
          outerContext = outer;
          await outer.trace('nested root', (_) async => release.future);
        },
      );
      await Future<void>.delayed(Duration.zero);
      expect(exporter.batches, isEmpty);
      release.complete();
      await operation;

      await outerContext.span('after end', (_) {});
      await Future<void>.delayed(Duration.zero);
      final spans = exporter.batches.single.records.cast<SpanRecord>().toList();
      final outer = spans.singleWhere((span) => span.payload.name == 'outer');
      final nested = spans.singleWhere((span) => span.payload.name == 'nested root');
      final after = spans.singleWhere((span) => span.payload.name == 'after end');
      expect(nested.envelope.parentSpanId, isNull);
      expect(nested.envelope.traceId, isNot(outer.envelope.traceId));
      expect(after.envelope.parentSpanId, isNull);
      expect(after.envelope.traceId, isNot(outer.envelope.traceId));
    });

    test('should preserve starting identity and unrelated Context bindings', () async {
      final exporter = TestExporter();
      final chronicler = createTracingChronicler(exporter, maxBatchRecords: 2);
      final markerKey = ContextKey<Object>('marker');
      final marker = Object();
      final base = Context()
          .withBinding(markerKey.bind(marker))
          .withChronicler(chronicler.recorder.withIdentity(userId: 'start'));

      await base.span(
        'identity',
        (span) async {
          expect(identical(span.require(markerKey), marker), isTrue);
          span.withIdentity(userId: 'changed').logs.info('changed identity');
        },
      );
      await Future<void>.delayed(Duration.zero);

      final span = exporter.batches.single.records.whereType<SpanRecord>().single;
      expect(span.envelope.userId, 'start');
    });

    test('should invoke callbacks once when span input is invalid', () async {
      final exporter = TestExporter();
      final chronicler = createTracingChronicler(exporter);
      final context = Context().withChronicler(chronicler.recorder);
      var calls = 0;

      await context.span(
        '',
        (invalid) async {
          calls++;
          await invalid.span('valid child', (_) {});
        },
      );
      await Future<void>.delayed(Duration.zero);

      expect(calls, 1);
      expect(
        exporter.batches.single.records.whereType<SpanRecord>().single.payload.name,
        'valid child',
      );
      expect(chronicler.diagnosticCounts[DiagnosticReason.invalidRecord], BigInt.one);
    });

    test('should suppress sync and async tracing started inside a hook', () async {
      final exporter = TestExporter();
      late Context context;
      var hookCalls = 0;
      var callbackCalls = 0;
      final chronicler = Chronicler(
        appId: 'app',
        release: 'release',
        source: ChroniclerSource.server,
        exporter: exporter,
        options: ChroniclerOptions(
          delivery: const DeliveryOptions(maxBatchRecords: 1),
          redaction: RedactionOptions(
            beforeRecord: (record) {
              hookCalls++;
              if (hookCalls == 1) {
                context.spanSync(
                  'recursive sync',
                  (_) => callbackCalls++,
                );
                unawaited(
                  context.span(
                    'recursive async',
                    (_) => callbackCalls++,
                  ),
                );
              }
              return record;
            },
          ),
        ),
      );
      context = Context().withChronicler(chronicler.recorder);

      context.logs.info('outer');
      await Future<void>.delayed(Duration.zero);

      expect(callbackCalls, 2);
      expect(hookCalls, 1);
      expect(exporter.batches.single.records.single, isA<LogRecord>());
      expect(chronicler.diagnosticCounts[DiagnosticReason.reentrantRecording], BigInt.two);
    });

    test('should require a configured Chronicler before invoking a callback', () {
      var invoked = false;

      expect(
        () => Context().spanSync<void>('missing', (_) => invoked = true),
        throwsA(isA<MissingContextValue>()),
      );
      expect(invoked, isFalse);
    });

    test('should record nonnegative integer microsecond durations', () async {
      final exporter = TestExporter();
      final chronicler = createTracingChronicler(exporter);

      await Context()
          .withChronicler(chronicler.recorder)
          .span(
            'duration',
            (_) => Future<void>.delayed(const Duration(milliseconds: 2)),
          );
      await Future<void>.delayed(Duration.zero);

      final span = exporter.batches.single.records.single as SpanRecord;
      expect(span.payload.durationMicros, isA<int>());
      expect(span.payload.durationMicros, isNonNegative);
      expect(span.envelope.timestamp.isUtc, isTrue);
    });

    test('should measure duration with a monotonic clock', () {
      var elapsed = Duration.zero;
      var wallClock = utcMoment(2026, 9, 12, 10);
      final bed = TraceControllerTestBed(now: () => wallClock, elapsed: () => elapsed);

      final active = bed.start('clock');
      wallClock = utcMoment(2020);
      elapsed = const Duration(microseconds: 1234);
      bed.controller.finish(active, SpanStatus.success);

      final span = bed.records.single;
      expect(span.envelope.timestamp, utcMoment(2026, 9, 12, 10));
      expect(span.payload.durationMicros, 1234);
    });
  });
}
