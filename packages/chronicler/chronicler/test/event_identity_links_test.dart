import 'package:chronicler/chronicler.dart';
import 'package:chronicler/src/runtime.dart';
import 'package:context/context.dart';
import 'package:test/test.dart';

import 'support/events_support.dart';
import 'support/exporter.dart';

void main() {
  group('ChroniclerEvents identity links', () {
    test('should emit an explicit identity link without changing Context identity', () async {
      final exporter = TestExporter();
      final chronicler = createEventChronicler(exporter, maxBatchRecords: 2);
      final context = Context()
          .withChronicler(chronicler.recorder)
          .withIdentity(userId: 'caller', anonymousId: 'caller-anonymous');

      context.events.identify(anonymousId: 'linked-anonymous', userId: 'linked-user');
      context.events.track('after_link');

      await Future<void>.delayed(Duration.zero);
      final link = exporter.batches.single.records.first as IdentityLinkRecord;
      final event = exporter.batches.single.records.last as ProductEventRecord;
      expect(link.envelope.appId, 'app');
      expect(link.envelope.userId, 'caller');
      expect(link.envelope.anonymousId, 'caller-anonymous');
      expect(link.payload.anonymousId, 'linked-anonymous');
      expect(link.payload.userId, 'linked-user');
      expect(event.envelope.userId, 'caller');
      expect(event.envelope.anonymousId, 'caller-anonymous');
    });

    test('should validate both identity-link targets atomically', () async {
      final exporter = TestExporter();
      final chronicler = createEventChronicler(exporter);
      Context().withChronicler(chronicler.recorder).events
        ..identify(anonymousId: '', userId: 'user')
        ..identify(anonymousId: 'anonymous', userId: '😀' * 65)
        ..identify(
          anonymousId: String.fromCharCode(0xd800),
          userId: 'user',
        );
      await Future<void>.delayed(Duration.zero);

      expect(exporter.batches, isEmpty);
      expect(chronicler.diagnosticCounts[DiagnosticReason.invalidRecord], BigInt.from(3));
    });

    test('should bypass sampling and retry one finalized identity link', () async {
      final exporter = TestExporter();
      var hookCalls = 0;
      final chronicler = Chronicler(
        appId: 'app',
        release: 'release',
        source: ChroniclerSource.server,
        exporter: exporter,
        options: ChroniclerOptions(
          delivery: const DeliveryOptions(
            maxBatchRecords: 1,
            initialRetryDelay: Duration(microseconds: 1),
            maxRetryDelay: Duration(microseconds: 1),
          ),
          sampling: const SamplingOptions(events: 0),
          redaction: RedactionOptions(
            beforeRecord: (record) {
              hookCalls++;
              return record;
            },
          ),
        ),
      );
      ChroniclerDeliveryFixture.selectRetryDelay(chronicler, (_, _) => Duration.zero);
      Context().withChronicler(chronicler.recorder).events
        ..track('sampled_out')
        ..identify(anonymousId: 'access_token', userId: 'password');
      await waitForEventAttempts(exporter, 1);
      final first = exporter.batches.single.records.single as IdentityLinkRecord;
      exporter.attempts.first.completer.complete(const ExportResult.retryable());
      await waitForEventAttempts(exporter, 2);
      final retried = exporter.batches.last.records.single as IdentityLinkRecord;

      expect(hookCalls, 1);
      expect(first.payload.anonymousId, 'access_token');
      expect(first.payload.userId, 'password');
      expect(retried.envelope.eventId, first.envelope.eventId);
      expect(retried.envelope.timestamp, first.envelope.timestamp);
      expect(retried.payload, first.payload);
      expect(chronicler.diagnosticCounts[DiagnosticReason.sampledOut], BigInt.one);
      exporter.attempts.last.completer.complete(const ExportResult.accepted());
    });

    test('should apply collection controls and record-hook suppression to links', () async {
      final disabledExporter = TestExporter();
      final disabled = createEventChronicler(disabledExporter)
        ..setCollectionEnabled(ChroniclerSignal.events, false);
      Context()
          .withChronicler(disabled.recorder)
          .events
          .identify(anonymousId: 'anonymous', userId: 'user');

      final hookedExporter = TestExporter();
      final hooked = Chronicler(
        appId: 'app',
        release: 'release',
        source: ChroniclerSource.server,
        exporter: hookedExporter,
        options: const ChroniclerOptions(
          delivery: DeliveryOptions(maxBatchRecords: 1),
          redaction: RedactionOptions(beforeRecord: dropEventRecord),
        ),
      );
      Context()
          .withChronicler(hooked.recorder)
          .events
          .identify(anonymousId: 'anonymous', userId: 'user');
      await Future<void>.delayed(Duration.zero);

      expect(disabledExporter.batches, isEmpty);
      expect(disabled.diagnosticCounts[DiagnosticReason.collectionDisabled], BigInt.one);
      expect(hookedExporter.batches, isEmpty);
      expect(hooked.diagnosticCounts[DiagnosticReason.hookDropped], BigInt.one);
    });
  });
}
