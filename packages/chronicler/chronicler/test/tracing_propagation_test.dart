import 'package:chronicler/chronicler.dart';
import 'package:context/context.dart';
import 'package:test/test.dart';

import 'support/exporter.dart';

const traceId = 'trc_0123456789ABCDEFGHIJKLMN';
const parentId = 'spn_0123456789ABCDEFGHIJKLMN';

void main() {
  group('Chronicler tracing propagation', () {
    test('should replace stale correlation headers without changing the source', () async {
      final parent = TracePropagation.extract({
        'chronicler-trace-id': traceId,
        'chronicler-span-id': parentId,
        'chronicler-sampled': '1',
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
          final source = {
            'Chronicler-Trace-Id': 'stale',
            'CHRONICLER-SPAN-ID': 'stale',
            'Chronicler-Sampled': 'stale',
            'other': 'kept',
          };
          injected = server.tracing.inject(source);
          expect(source['Chronicler-Trace-Id'], 'stale');
        },
      );

      expect(injected['other'], 'kept');
      expect(
        injected.keys,
        unorderedEquals([
          'other',
          'chronicler-trace-id',
          'chronicler-span-id',
          'chronicler-sampled',
        ]),
      );
      final extracted = TracePropagation.extract(injected)!;
      expect(extracted.traceId, traceId);
      expect(extracted.parentSpanId, isNot(parentId));
    });

    test('should continue incoming server and outgoing client spans', () async {
      final remote = TracePropagation.extract({
        'chronicler-trace-id': traceId,
        'chronicler-span-id': parentId,
        'chronicler-sampled': '1',
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
      expect(outgoing, {
        'content-type': 'application/json',
        'chronicler-trace-id': traceId,
        'chronicler-span-id': client.envelope.spanId,
        'chronicler-sampled': '1',
      });
      final nextParent = TracePropagation.extract(outgoing)!;
      expect(nextParent.traceId, traceId);
      expect(nextParent.parentSpanId, client.envelope.spanId);

      final receiverExporter = TestExporter();
      final receiver = Chronicler(
        appId: 'app',
        release: 'release',
        source: ChroniclerSource.server,
        exporter: receiverExporter,
        options: const ChroniclerOptions(delivery: DeliveryOptions(maxBatchRecords: 1)),
      );
      await receiver.recorder.trace(
        'payments.receive',
        parent: nextParent,
        kind: SpanKind.server,
        run: (_) {},
      );
      await Future<void>.delayed(Duration.zero);
      final received = receiverExporter.batches.single.records.single as SpanRecord;
      expect(received.envelope.traceId, traceId);
      expect(received.envelope.parentSpanId, client.envelope.spanId);
      expect(received.envelope.spanId, isNot(client.envelope.spanId));
    });

    test('should let a remote parent override the caller trace and sampling trust', () async {
      final remote = TracePropagation.extract({
        'chronicler-trace-id': traceId,
        'chronicler-span-id': parentId,
        'chronicler-sampled': '0',
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

      expect(base.tracing.inject({'Chronicler-Trace-Id': 'stale', 'other': 'kept'}), {
        'other': 'kept',
      });
      await base.span('ended', run: (span) => retained = span);
      expect(retained.tracing.inject({'chronicler-span-id': 'stale'}), isEmpty);
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
          final before = active.tracing.inject({})['chronicler-sampled']!;
          chronicler.setCollectionEnabled(ChroniclerSignal.traces, false);
          active.tracing
            ..setAttribute('discarded', true)
            ..setError();
          activeHeader = active.tracing.inject({})['chronicler-sampled']!;
          expect(activeHeader, before);
          chronicler.setCollectionEnabled(ChroniclerSignal.traces, true);
          await active.span(
            'suppressed child',
            run: (child) {
              suppressedChildHeader = child.tracing.inject({})['chronicler-sampled']!;
              child.logs.info('correlated without spans');
            },
          );
        },
      );
      await base.trace('fresh boundary', run: (_) {});
      await Future<void>.delayed(Duration.zero);

      expect(activeHeader, '1');
      expect(suppressedChildHeader, '0');
      final records = exporter.batches.single.records;
      expect(records.whereType<SpanRecord>().single.payload.name, 'fresh boundary');
      expect(records.whereType<LogRecord>().single.envelope.traceId, isNotNull);
      expect(chronicler.diagnosticCounts[DiagnosticReason.noActiveSpan], isNull);
      expect(chronicler.diagnosticCounts[DiagnosticReason.invalidSpanUpdate], isNull);
    });

    test('should toggle propagation independently and ignore parents while disabled', () async {
      final remote = TracePropagation.extract({
        'chronicler-trace-id': traceId,
        'chronicler-span-id': parentId,
        'chronicler-sampled': '1',
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
          expect(local.tracing.inject({'chronicler-sampled': 'stale'}), isEmpty);
          local.logs.info('local correlation');
          chronicler.setPropagationEnabled(true);
          activeHeader = local.tracing.inject({})['chronicler-trace-id']!;
          chronicler.setPropagationEnabled(false);
        },
      );
      chronicler.setPropagationEnabled(true);
      await Future<void>.delayed(Duration.zero);
      localTraceId = (exporter.batches.single.records.single as LogRecord).envelope.traceId!;

      expect(localTraceId, isNot(traceId));
      expect(activeHeader, localTraceId);
      expect(chronicler.isCollectionEnabled(ChroniclerSignal.traces), isTrue);
    });

    test('should let local collection disablement override a sampled remote parent', () async {
      final remote = TracePropagation.extract({
        'chronicler-trace-id': traceId,
        'chronicler-span-id': parentId,
        'chronicler-sampled': '1',
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
      late Map<String, String> headers;

      await Context()
          .withChronicler(chronicler.recorder)
          .trace(
            'server',
            parent: remote,
            run: (server) {
              headers = server.tracing.inject({});
              server.logs.info('remote correlation');
            },
          );
      await Future<void>.delayed(Duration.zero);

      expect(headers['chronicler-trace-id'], traceId);
      expect(headers['chronicler-sampled'], '0');
      expect(exporter.batches.single.records, everyElement(isA<LogRecord>()));
      expect(exporter.batches.single.records.single.envelope.traceId, traceId);
    });
  });
}
