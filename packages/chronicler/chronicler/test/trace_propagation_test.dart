import 'package:chronicler/chronicler.dart';
import 'package:context/context.dart';
import 'package:test/test.dart';

import 'support/exporter.dart';

void main() {
  group('TracePropagation', () {
    const traceId = '0af7651916cd43dd8448eb211c80319c';
    const parentId = 'b7ad6b7169203331';

    test('should extract valid version zero and ordered tracestate', () {
      final parent = TracePropagation.extract({
        'TraceParent': '00-$traceId-$parentId-01',
        'TraceState': 'rojo=00f067aa0ba902b7,congo=t61rcWkgMzE',
      });

      expect(parent, isNotNull);
      expect(parent!.traceId, traceId);
      expect(parent.parentSpanId, parentId);
      expect(parent.sampled, isTrue);
      expect(parent.tracestate, ['rojo=00f067aa0ba902b7', 'congo=t61rcWkgMzE']);
    });

    test('should reject malformed parents and retain parents with invalid state', () {
      final invalid = [
        '00-$traceId-$parentId-01-extra',
        'ff-$traceId-$parentId-01',
        '00-${'0' * 32}-$parentId-01',
        '00-$traceId-${'0' * 16}-01',
        '00-${traceId.toUpperCase()}-$parentId-01',
        '00-$traceId-$parentId-01,00-$traceId-$parentId-01',
      ];
      for (final value in invalid) {
        expect(TracePropagation.extract({'traceparent': value}), isNull, reason: value);
      }

      final parent = TracePropagation.extract({
        'traceparent': '01-$traceId-$parentId-03-vendor',
        'tracestate': 'duplicate=one,duplicate=two',
      });
      expect(parent, isNotNull);
      expect(parent!.sampled, isTrue);
      expect(parent.tracestate, isEmpty);
      expect(
        TracePropagation.extract({
          'TraceParent': '00-$traceId-$parentId-01',
          'traceparent': '00-$traceId-$parentId-01',
        }),
        isNull,
      );
      const future = '01-$traceId-$parentId-01-vendor';
      expect(TracePropagation.extract({'traceparent': '$future,$future'}), isNull);
    });

    test('should ignore empty tracestate list members', () {
      final parent = TracePropagation.extract({
        'traceparent': '00-$traceId-$parentId-01',
        'tracestate': 'rojo=abc, ,congo=xyz',
      });

      expect(parent!.tracestate, ['rojo=abc', 'congo=xyz']);
    });

    test('should enforce input caps and truncate outbound state by whole entries', () async {
      expect(TracePropagation.extract({'traceparent': 'x' * 1025}), isNull);
      final parent = TracePropagation.extract({
        'traceparent': '00-$traceId-$parentId-01',
        'tracestate': [for (var index = 0; index < 20; index++) 'v$index=${'x' * 24}'].join(','),
      });
      final exporter = TestExporter();
      final chronicler = Chronicler(
        appId: 'app',
        release: 'release',
        source: ChroniclerSource.server,
        exporter: exporter,
      );
      final context = Context().withChronicler(chronicler.recorder);
      late Map<String, String> injected;

      await context.trace(
        'server',
        parent: parent,
        run: (server) {
          final source = {'TraceParent': 'stale', 'TRACESTATE': 'stale', 'other': 'kept'};
          injected = server.tracing.inject(source);
          expect(source['TraceParent'], 'stale');
        },
      );

      expect(injected['other'], 'kept');
      expect(injected.keys, containsAll(['traceparent', 'tracestate']));
      expect(injected['tracestate']!.length, lessThanOrEqualTo(512));
      expect(injected.keys.where((key) => key.toLowerCase() == 'traceparent'), hasLength(1));
    });

    test('should remove oversized state entries before trimming from the end', () {
      final parent = TracePropagation.extract({
        'traceparent': '00-$traceId-$parentId-01',
        'tracestate': [
          'large=${'x' * 200}',
          for (var index = 0; index < 15; index++) 'v$index=${'y' * 20}',
        ].join(','),
      });

      expect(parent, isNotNull);
      expect(parent!.tracestate, isNot(contains(startsWith('large='))));
      expect(parent.tracestate, contains('v14=${'y' * 20}'));
    });

    test('should continue incoming server and outgoing client spans', () async {
      final remote = TracePropagation.extract({
        'traceparent': '00-$traceId-$parentId-01',
        'tracestate': 'vendor=value',
      });
      final exporter = TestExporter();
      final chronicler = Chronicler(
        appId: 'app',
        release: 'release',
        source: ChroniclerSource.server,
        exporter: exporter,
        options: const ChroniclerOptions(
          delivery: DeliveryOptions(maxBatchRecords: 2),
        ),
      );
      final context = Context().withChronicler(chronicler.recorder);
      late Map<String, String> outgoing;

      await context.trace(
        'POST /orders',
        parent: remote,
        kind: SpanKind.server,
        run: (server) {
          return server.span(
            'payments.create',
            kind: SpanKind.client,
            run: (client) {
              outgoing = client.tracing.inject({'content-type': 'application/json'});
            },
          );
        },
      );
      await Future<void>.delayed(Duration.zero);

      final spans = exporter.batches.single.records.cast<SpanRecord>().toList();
      final server = spans.singleWhere((span) => span.payload.spanKind == SpanKind.server);
      final client = spans.singleWhere((span) => span.payload.spanKind == SpanKind.client);
      expect(server.envelope.traceId, traceId);
      expect(server.envelope.parentSpanId, parentId);
      expect(client.envelope.parentSpanId, server.envelope.spanId);
      expect(outgoing['traceparent'], '00-$traceId-${client.envelope.spanId}-01');
      expect(outgoing['tracestate'], 'vendor=value');
    });

    test('should let a remote parent override the caller trace and sampling trust', () async {
      final remote = TracePropagation.extract({
        'traceparent': '00-$traceId-$parentId-00',
      });
      final trustedExporter = TestExporter();
      final trusted = Chronicler(
        appId: 'app',
        release: 'release',
        source: ChroniclerSource.server,
        exporter: trustedExporter,
      );
      await Context()
          .withChronicler(trusted.recorder)
          .trace(
            'trusted',
            parent: remote,
            run: (_) {},
          );
      expect(trustedExporter.batches, isEmpty);
      expect(trusted.diagnosticCounts[DiagnosticReason.sampledOut], BigInt.one);

      final localExporter = TestExporter();
      final local = Chronicler(
        appId: 'app',
        release: 'release',
        source: ChroniclerSource.server,
        exporter: localExporter,
        options: const ChroniclerOptions(
          delivery: DeliveryOptions(maxBatchRecords: 2),
          tracing: TracingOptions(honorRemoteSampling: false),
        ),
      );
      final base = Context().withChronicler(local.recorder);
      await base.trace(
        'caller',
        run: (caller) async {
          caller.traceSync('remote', parent: remote, run: (_) {});
        },
      );
      await Future<void>.delayed(Duration.zero);

      final spans = localExporter.batches.single.records.cast<SpanRecord>().toList();
      final caller = spans.singleWhere((span) => span.payload.name == 'caller');
      final continued = spans.singleWhere((span) => span.payload.name == 'remote');
      expect(continued.envelope.traceId, traceId);
      expect(continued.envelope.parentSpanId, parentId);
      expect(continued.envelope.traceId, isNot(caller.envelope.traceId));
    });

    test('should clean headers when no active span or after it ends', () async {
      final chronicler = Chronicler(
        appId: 'app',
        release: 'release',
        source: ChroniclerSource.server,
        exporter: TestExporter(),
      );
      final base = Context().withChronicler(chronicler.recorder);
      late Context retained;

      expect(base.tracing.inject({'TraceParent': 'stale', 'other': 'kept'}), {'other': 'kept'});
      await base.span('ended', run: (span) => retained = span);
      expect(retained.tracing.inject({'tracestate': 'stale'}), isEmpty);
    });

    test('should suppress a live lineage without rewriting its outbound flag', () async {
      final exporter = TestExporter();
      final chronicler = Chronicler(
        appId: 'app',
        release: 'release',
        source: ChroniclerSource.server,
        exporter: exporter,
        options: const ChroniclerOptions(
          delivery: DeliveryOptions(maxBatchRecords: 2),
        ),
      );
      final base = Context().withChronicler(chronicler.recorder);
      late String activeHeader;
      late String suppressedChildHeader;

      await base.span(
        'active',
        run: (active) async {
          final before = active.tracing.inject({})['traceparent']!;
          chronicler.setCollectionEnabled(ChroniclerSignal.traces, false);
          active.tracing
            ..setAttribute('discarded', true)
            ..setError();
          activeHeader = active.tracing.inject({})['traceparent']!;
          expect(activeHeader, before);
          chronicler.setCollectionEnabled(ChroniclerSignal.traces, true);
          await active.span(
            'suppressed child',
            run: (child) {
              suppressedChildHeader = child.tracing.inject({})['traceparent']!;
              child.logs.info('correlated without spans');
            },
          );
        },
      );
      await base.trace('fresh boundary', run: (_) {});
      await Future<void>.delayed(Duration.zero);

      expect(activeHeader, endsWith('-01'));
      expect(suppressedChildHeader, endsWith('-00'));
      final records = exporter.batches.single.records;
      expect(records.whereType<SpanRecord>().single.payload.name, 'fresh boundary');
      expect(records.whereType<LogRecord>().single.envelope.traceId, isNotNull);
      expect(chronicler.diagnosticCounts[DiagnosticReason.noActiveSpan], isNull);
      expect(chronicler.diagnosticCounts[DiagnosticReason.invalidSpanUpdate], isNull);
    });

    test('should toggle propagation independently and ignore parents while disabled', () async {
      final remote = TracePropagation.extract({
        'traceparent': '00-$traceId-$parentId-01',
      });
      final exporter = TestExporter();
      final chronicler = Chronicler(
        appId: 'app',
        release: 'release',
        source: ChroniclerSource.server,
        exporter: exporter,
        options: const ChroniclerOptions(
          delivery: DeliveryOptions(maxBatchRecords: 1),
        ),
      );
      final base = Context().withChronicler(chronicler.recorder);
      late String localTraceId;
      late String activeHeader;

      chronicler.setPropagationEnabled(false);
      await base.trace(
        'local',
        parent: remote,
        run: (local) {
          expect(local.tracing.inject({'traceparent': 'stale'}), isEmpty);
          local.logs.info('local correlation');
          chronicler.setPropagationEnabled(true);
          activeHeader = local.tracing.inject({})['traceparent']!;
          chronicler.setPropagationEnabled(false);
        },
      );
      chronicler.setPropagationEnabled(true);
      await Future<void>.delayed(Duration.zero);
      localTraceId = (exporter.batches.single.records.single as LogRecord).envelope.traceId!;

      expect(localTraceId, isNot(traceId));
      expect(activeHeader, contains(localTraceId));
      expect(chronicler.isCollectionEnabled(ChroniclerSignal.traces), isTrue);
    });

    test('should let local collection disablement override a sampled remote parent', () async {
      final remote = TracePropagation.extract({
        'traceparent': '00-$traceId-$parentId-01',
      });
      final exporter = TestExporter();
      final chronicler = Chronicler(
        appId: 'app',
        release: 'release',
        source: ChroniclerSource.server,
        exporter: exporter,
        options: const ChroniclerOptions(
          delivery: DeliveryOptions(maxBatchRecords: 1),
        ),
      )..setCollectionEnabled(ChroniclerSignal.traces, false);
      late String header;

      await Context()
          .withChronicler(chronicler.recorder)
          .trace(
            'server',
            parent: remote,
            run: (server) {
              header = server.tracing.inject({})['traceparent']!;
              server.logs.info('remote correlation');
            },
          );
      await Future<void>.delayed(Duration.zero);

      expect(header, startsWith('00-$traceId-'));
      expect(header, endsWith('-00'));
      expect(exporter.batches.single.records, everyElement(isA<LogRecord>()));
      expect(exporter.batches.single.records.single.envelope.traceId, traceId);
    });
  });
}
