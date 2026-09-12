import 'dart:async';
import 'dart:math';

import 'package:chronicler/chronicler.dart';
import 'package:chronicler/src/runtime.dart' show ChroniclerTracingFixture;
import 'package:context/context.dart';
import 'package:test/test.dart';

import 'support/exporter.dart';

void main() {
  group('Chronicler tracing', () {
    test('should record nested callback spans and correlate logs', () async {
      final exporter = TestExporter();
      final chronicler = _chronicler(exporter, maxBatchRecords: 3);
      final context = Context().withChronicler(chronicler.recorder);

      final result = await context.trace(
        'request',
        kind: SpanKind.server,
        run: (request) => request.span(
          'database',
          kind: SpanKind.client,
          run: (database) {
            database.logs.info('query complete');
            return 42;
          },
        ),
      );
      await Future<void>.delayed(Duration.zero);

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
      final chronicler = _chronicler(exporter, maxBatchRecords: 2);
      final context = Context().withChronicler(chronicler.recorder);
      final syncError = StateError('sync');
      late StackTrace syncStack;
      try {
        context.spanSync<void>(
          'sync',
          run: (_) => Error.throwWithStackTrace(syncError, StackTrace.current),
        );
      } on Object catch (error, stackTrace) {
        expect(identical(error, syncError), isTrue);
        syncStack = stackTrace;
      }
      final asyncError = StateError('async');
      late StackTrace asyncStack;
      try {
        await context.span<void>(
          'async',
          run: (_) async => Error.throwWithStackTrace(asyncError, StackTrace.current),
        );
      } on Object catch (error, stackTrace) {
        expect(identical(error, asyncError), isTrue);
        asyncStack = stackTrace;
      }
      expect(syncStack, isNotNull);
      expect(asyncStack, isNotNull);

      await Future<void>.delayed(Duration.zero);
      final spans = exporter.batches.single.records.cast<SpanRecord>();
      expect(spans.map((span) => span.payload.status), everyElement(SpanStatus.error));
    });

    test('should keep concurrent branches and detached children isolated', () async {
      final exporter = TestExporter();
      final chronicler = _chronicler(exporter, maxBatchRecords: 7);
      final base = Context().withChronicler(chronicler.recorder);
      late Context endedParent;
      final detached = Completer<void>();

      await base.trace(
        'parent',
        run: (parent) async {
          endedParent = parent;
          unawaited(parent.span('detached', run: (_) => detached.future));
          await Future.wait([
            parent.span('left', run: (left) async => left.logs.info('left')),
            parent.span('right', run: (right) async => right.logs.info('right')),
          ]);
        },
      );
      detached.complete();
      await Future<void>.delayed(Duration.zero);

      await endedParent.span('fresh', run: (_) {});
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
      final chronicler = _chronicler(exporter);
      final context = Context().withChronicler(chronicler.recorder);
      final original = Future<int>.value(7);

      final returned = context.spanSync<Future<int>>('sync misuse', run: (_) => original);

      expect(identical(returned, original), isTrue);
      expect(await returned, 7);
      expect(chronicler.diagnosticCounts[DiagnosticReason.syncCallbackReturnedFuture], BigInt.one);
    });

    test('should keep async spans open and explicit traces independent', () async {
      final exporter = TestExporter();
      final chronicler = _chronicler(exporter, maxBatchRecords: 3);
      final base = Context().withChronicler(chronicler.recorder);
      final release = Completer<void>();
      late Context outerContext;

      final operation = base.span(
        'outer',
        run: (outer) async {
          outerContext = outer;
          await outer.trace('nested root', run: (_) async => release.future);
        },
      );
      await Future<void>.delayed(Duration.zero);
      expect(exporter.batches, isEmpty);
      release.complete();
      await operation;

      await outerContext.span('after end', run: (_) {});
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
      final chronicler = _chronicler(exporter, maxBatchRecords: 2);
      final markerKey = ContextKey<Object>('marker');
      final marker = Object();
      final base = Context()
          .withBinding(markerKey.bind(marker))
          .withChronicler(chronicler.recorder.withIdentity(userId: 'start'));

      await base.span(
        'identity',
        run: (span) async {
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
      final chronicler = _chronicler(exporter);
      final context = Context().withChronicler(chronicler.recorder);
      var calls = 0;

      await context.span(
        '',
        run: (invalid) async {
          calls++;
          await invalid.span('valid child', run: (_) {});
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

    test('should require a configured Chronicler before invoking a callback', () {
      var invoked = false;

      expect(
        () => Context().spanSync<void>('missing', run: (_) => invoked = true),
        throwsA(isA<MissingContextValue>()),
      );
      expect(invoked, isFalse);
    });

    test('should record nonnegative integer microsecond durations', () async {
      final exporter = TestExporter();
      final chronicler = _chronicler(exporter);

      await Context()
          .withChronicler(chronicler.recorder)
          .span(
            'duration',
            run: (_) => Future<void>.delayed(const Duration(milliseconds: 2)),
          );
      await Future<void>.delayed(Duration.zero);

      final span = exporter.batches.single.records.single as SpanRecord;
      expect(span.payload.durationMicros, isA<int>());
      expect(span.payload.durationMicros, isNonNegative);
      expect(span.envelope.timestamp.isUtc, isTrue);
    });

    test('should measure duration with a monotonic clock', () async {
      final exporter = TestExporter();
      final chronicler = _chronicler(exporter);
      var elapsed = Duration.zero;
      var wallClock = DateTime.utc(2026, 9, 12, 10);
      ChroniclerTracingFixture.overrideClocks(
        chronicler,
        now: () => wallClock,
        elapsed: () => elapsed,
      );

      await Context()
          .withChronicler(chronicler.recorder)
          .span(
            'clock',
            run: (_) {
              wallClock = DateTime.utc(2020);
              elapsed = const Duration(microseconds: 1234);
            },
          );
      await Future<void>.delayed(Duration.zero);

      final span = exporter.batches.single.records.single as SpanRecord;
      expect(span.envelope.timestamp, DateTime.utc(2026, 9, 12, 10));
      expect(span.payload.durationMicros, 1234);
    });

    test('should fail setup when secure randomness is unavailable', () {
      expect(
        () => ChroniclerTracingFixture.create(
          appId: 'app',
          release: 'release',
          source: ChroniclerSource.server,
          exporter: TestExporter(),
          secureRandom: () => throw UnsupportedError('unavailable'),
        ),
        throwsA(
          isA<ChroniclerConfigurationException>().having(
            (error) => error.setting,
            'setting',
            'secureRandom',
          ),
        ),
      );
    });

    test('should preserve application work when ID generation fails', () async {
      final exporter = TestExporter();
      final chronicler = _chronicler(exporter);
      ChroniclerTracingFixture.overrideSecureRandom(chronicler, _ThrowingRandom());
      final context = Context().withChronicler(chronicler.recorder);
      var calls = 0;

      final result = await context.span(
        'random failure',
        run: (_) {
          calls++;
          return 12;
        },
      );

      expect(result, 12);
      expect(calls, 1);
      expect(exporter.batches, isEmpty);
      expect(chronicler.diagnosticCounts[DiagnosticReason.invalidRecord], BigInt.one);
    });

    test('should update active attributes atomically and snapshot values', () async {
      final exporter = TestExporter();
      final chronicler = _chronicler(exporter);
      final nested = <Object?>[1];

      await Context()
          .withChronicler(chronicler.recorder)
          .span(
            'attributes',
            attributes: {'kept': true, 'replace': 1},
            run: (span) {
              span.tracing
                ..setAttribute('replace', 2)
                ..setAttributes({'nested': nested, 'api_token': 'secret'});
              nested.add(3);
              span.tracing.setAttributes({'valid': true, 'invalid': Object()});
            },
          );
      await Future<void>.delayed(Duration.zero);

      final attributes = (exporter.batches.single.records.single as SpanRecord).payload.attributes;
      expect(attributes, {
        'kept': true,
        'replace': 2,
        'nested': [1],
        'api_token': '[REDACTED]',
      });
      expect(chronicler.diagnosticCounts[DiagnosticReason.invalidSpanUpdate], BigInt.one);
    });

    test('should preserve explicit errors and let cancellation take precedence', () async {
      final exporter = TestExporter();
      final cancellation = StateError('cancelled');
      final chronicler = Chronicler(
        appId: 'app',
        release: 'release',
        source: ChroniclerSource.server,
        exporter: exporter,
        options: ChroniclerOptions(
          delivery: const DeliveryOptions(maxBatchRecords: 2),
          tracing: TracingOptions(isCancellation: (error) => identical(error, cancellation)),
        ),
      );
      final context = Context().withChronicler(chronicler.recorder);

      final value = await context.span(
        'handled',
        run: (span) {
          span.tracing
            ..setError()
            ..setError();
          return 9;
        },
      );
      expect(value, 9);
      await expectLater(
        context.span<void>(
          'cancelled',
          run: (span) {
            span.tracing.setError();
            throw cancellation;
          },
        ),
        throwsA(same(cancellation)),
      );
      await Future<void>.delayed(Duration.zero);

      final records = exporter.batches.single.records.cast<SpanRecord>().toList();
      expect(records.first.payload.status, SpanStatus.error);
      expect(records.last.payload.status, SpanStatus.cancelled);
    });

    test('should contain classifier failures and preserve the application error', () async {
      final exporter = TestExporter();
      final failure = StateError('application');
      final chronicler = Chronicler(
        appId: 'app',
        release: 'release',
        source: ChroniclerSource.server,
        exporter: exporter,
        options: ChroniclerOptions(
          delivery: const DeliveryOptions(maxBatchRecords: 1),
          tracing: TracingOptions(isCancellation: (_) => throw StateError('classifier')),
        ),
      );

      await expectLater(
        Context()
            .withChronicler(chronicler.recorder)
            .span<void>(
              'failure',
              run: (_) => throw failure,
            ),
        throwsA(same(failure)),
      );
      await Future<void>.delayed(Duration.zero);

      expect(
        (exporter.batches.single.records.single as SpanRecord).payload.status,
        SpanStatus.error,
      );
      expect(
        chronicler.diagnosticCounts[DiagnosticReason.cancellationClassifierFailed],
        BigInt.one,
      );
    });

    test('should diagnose updates without an active span or after completion', () async {
      final exporter = TestExporter();
      final chronicler = _chronicler(exporter);
      final base = Context().withChronicler(chronicler.recorder);
      late Context retained;

      base.tracing
        ..setError()
        ..setAttribute('ignored', true);
      await base.span('ended', run: (span) => retained = span);
      retained.tracing
        ..setError()
        ..setAttributes({'ignored': true});
      await Future<void>.delayed(Duration.zero);

      final span = exporter.batches.single.records.single as SpanRecord;
      expect(span.payload.status, SpanStatus.success);
      expect(span.payload.attributes, isEmpty);
      expect(chronicler.diagnosticCounts[DiagnosticReason.noActiveSpan], BigInt.two);
      expect(chronicler.diagnosticCounts[DiagnosticReason.invalidSpanUpdate], BigInt.two);
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
      expect(log.envelope.traceId, matches(RegExp(r'^[0-9a-f]{32}$')));
      expect(log.envelope.spanId, matches(RegExp(r'^[0-9a-f]{16}$')));
      expect(event.envelope.traceId, log.envelope.traceId);
      expect(event.envelope.spanId, log.envelope.spanId);
      expect(chronicler.diagnosticCounts[DiagnosticReason.sampledOut], BigInt.one);
    });

    test('should choose sampling once per root and inherit it in children', () async {
      final exporter = TestExporter();
      final chronicler = Chronicler(
        appId: 'app',
        release: 'release',
        source: ChroniclerSource.server,
        exporter: exporter,
        options: const ChroniclerOptions(
          delivery: DeliveryOptions(maxBatchRecords: 2),
          sampling: SamplingOptions(traces: 0.5),
        ),
      );
      final random = _SequenceRandom([0.25, 0.75]);
      ChroniclerTracingFixture.overrideSamplingRandom(chronicler, random);
      final context = Context().withChronicler(chronicler.recorder);

      await context.span('sampled root', run: (root) => root.span('sampled child', run: (_) {}));
      await context.trace('excluded root', run: (_) {});
      await Future<void>.delayed(Duration.zero);

      expect(random.nextDoubleCalls, 2);
      final spans = exporter.batches.single.records.cast<SpanRecord>().toList();
      expect(
        spans.map((span) => span.payload.name),
        containsAll(['sampled root', 'sampled child']),
      );
      expect(spans.map((span) => span.payload.name), isNot(contains('excluded root')));
      expect(chronicler.diagnosticCounts[DiagnosticReason.sampledOut], BigInt.one);
    });
  });
}

Chronicler _chronicler(TestExporter exporter, {int maxBatchRecords = 1}) => Chronicler(
  appId: 'app',
  release: 'release',
  source: ChroniclerSource.server,
  exporter: exporter,
  options: ChroniclerOptions(
    delivery: DeliveryOptions(maxBatchRecords: maxBatchRecords),
  ),
);

final class _ThrowingRandom implements Random {
  @override
  bool nextBool() => throw UnsupportedError('unavailable');

  @override
  double nextDouble() => throw UnsupportedError('unavailable');

  @override
  int nextInt(int max) => throw UnsupportedError('unavailable');
}

final class _SequenceRandom implements Random {
  _SequenceRandom(this._values);

  final List<double> _values;
  int nextDoubleCalls = 0;

  @override
  bool nextBool() => nextDouble() < 0.5;

  @override
  double nextDouble() => _values[nextDoubleCalls++];

  @override
  int nextInt(int max) => (nextDouble() * max).floor();
}
