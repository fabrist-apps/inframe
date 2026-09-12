import 'dart:async';
import 'dart:collection';
import 'dart:math';

import 'package:chronicler/chronicler.dart';
import 'package:chronicler/src/runtime.dart' show ChroniclerTracingFixture;
import 'package:context/context.dart';
import 'package:test/test.dart';

import 'support/exporter.dart';
import 'support/tracing_support.dart';

void main() {
  group('Chronicler tracing sampling', () {
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
      final chronicler = createTracingChronicler(exporter);
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

    test('should stop retrying an all-zero secure random source', () async {
      final exporter = TestExporter();
      final chronicler = createTracingChronicler(exporter);
      ChroniclerTracingFixture.overrideSecureRandom(chronicler, _ZeroRandom());
      var calls = 0;

      final result = await chronicler.recorder.span(
        'zero IDs',
        run: (_) {
          calls++;
          return 8;
        },
      );

      expect(result, 8);
      expect(calls, 1);
      expect(exporter.batches, isEmpty);
      expect(chronicler.diagnosticCounts[DiagnosticReason.invalidRecord], BigInt.one);
    });

    test('should preserve application work when sampling fails', () async {
      final exporter = TestExporter();
      final chronicler = Chronicler(
        appId: 'app',
        release: 'release',
        source: ChroniclerSource.server,
        exporter: exporter,
        options: const ChroniclerOptions(
          sampling: SamplingOptions(traces: 0.5),
        ),
      );
      ChroniclerTracingFixture.overrideSamplingRandom(
        chronicler,
        _ThrowingRandom(),
      );
      var calls = 0;

      final result = await chronicler.recorder.span(
        'sampling failure',
        run: (_) {
          calls++;
          return 11;
        },
      );

      expect(result, 11);
      expect(calls, 1);
      expect(exporter.batches, isEmpty);
      expect(chronicler.diagnosticCounts[DiagnosticReason.invalidRecord], BigInt.one);
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

    test('should skip and release attributes for non-recording spans', () async {
      final exporter = TestExporter();
      final chronicler = Chronicler(
        appId: 'app',
        release: 'release',
        source: ChroniclerSource.server,
        exporter: exporter,
        options: const ChroniclerOptions(
          sampling: SamplingOptions(traces: 0),
        ),
      );
      final recorder = chronicler.recorder;
      final unreadable = _UnreadableAttributes();

      await recorder.span(
        'unsampled',
        attributes: unreadable,
        run: (_) {},
      );
      expect(unreadable.reads, 0);

      final recording = Chronicler(
        appId: 'app',
        release: 'release',
        source: ChroniclerSource.server,
        exporter: TestExporter(),
      );
      await recording.recorder.span(
        'disabled while active',
        attributes: {'secret': 'retained'},
        run: (active) {
          expect(ChroniclerTracingFixture.retainedAttributeCount(active), 1);
          recording.setCollectionEnabled(ChroniclerSignal.traces, false);
          expect(ChroniclerTracingFixture.retainedAttributeCount(active), 0);
        },
      );
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

final class _ZeroRandom implements Random {
  @override
  bool nextBool() => false;

  @override
  double nextDouble() => 0;

  @override
  int nextInt(int max) => 0;
}

final class _UnreadableAttributes extends MapBase<String, Object?> {
  int reads = 0;

  @override
  Iterable<String> get keys {
    reads++;
    throw StateError('attributes were read');
  }

  @override
  Object? operator [](Object? key) {
    reads++;
    throw StateError('attributes were read');
  }

  @override
  void operator []=(String key, Object? value) => throw UnsupportedError('read only');

  @override
  void clear() => throw UnsupportedError('read only');

  @override
  Object? remove(Object? key) => throw UnsupportedError('read only');
}
