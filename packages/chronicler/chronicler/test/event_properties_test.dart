import 'package:chronicler/chronicler.dart';
import 'package:context/context.dart';
import 'package:test/test.dart';

import 'support/events_support.dart';
import 'support/exporter.dart';

void main() {
  group('ChroniclerEvents user properties', () {
    test('should emit distinct property removals without changing Context identity', () async {
      final exporter = TestExporter();
      final chronicler = createEventChronicler(exporter, maxBatchRecords: 2);
      final context = Context().withChronicler(chronicler.recorder).withIdentity(userId: 'caller');

      context.events.unsetUserProperties(
        userId: 'target',
        keys: ['plan', 'companySize', 'plan'],
      );
      context.events.track('after_unset');

      await Future<void>.delayed(Duration.zero);
      final update = exporter.batches.single.records.first as UserPropertiesUnsetRecord;
      final event = exporter.batches.single.records.last as ProductEventRecord;
      expect(update.envelope.userId, 'caller');
      expect(update.payload.userId, 'target');
      expect(update.payload.keys, ['plan', 'companySize']);
      expect(event.envelope.userId, 'caller');
    });

    test('should make empty property removals no-ops before target and capture checks', () async {
      final exporter = TestExporter();
      final chronicler = createEventChronicler(exporter);

      Context()
          .withChronicler(chronicler.recorder)
          .events
          .unsetUserProperties(userId: '', keys: const []);
      chronicler.setCollectionEnabled(ChroniclerSignal.events, enabled: false);
      Context()
          .withChronicler(chronicler.recorder)
          .events
          .unsetUserProperties(userId: '', keys: const []);
      await chronicler.close();
      Context()
          .withChronicler(chronicler.recorder)
          .events
          .unsetUserProperties(userId: '', keys: const []);
      await Future<void>.delayed(Duration.zero);

      expect(exporter.batches, isEmpty);
      expect(chronicler.diagnosticCounts, isEmpty);
    });

    test('should bypass sampling and retry one finalized property removal', () async {
      final exporter = TestExporter();
      var hookCalls = 0;
      final keys = ['password', 'access_token'];
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

      Context()
          .withChronicler(chronicler.recorder)
          .events
          .unsetUserProperties(userId: 'password', keys: keys);
      keys.add('later');
      await waitForEventAttempts(exporter, 1);
      final first = exporter.batches.single.records.single as UserPropertiesUnsetRecord;
      exporter.attempts.first.completer.complete(const ExportResult.retryable());
      await waitForEventAttempts(exporter, 2);
      final retried = exporter.batches.last.records.single as UserPropertiesUnsetRecord;

      expect(hookCalls, 1);
      expect(first.payload.userId, 'password');
      expect(first.payload.keys, ['password', 'access_token']);
      expect(retried.envelope.eventId, first.envelope.eventId);
      expect(retried.envelope.timestamp, first.envelope.timestamp);
      expect(retried.payload, first.payload);
      expect(chronicler.diagnosticCounts[DiagnosticReason.sampledOut], isNull);
      exporter.attempts.last.completer.complete(const ExportResult.accepted());
    });

    test('should prevent property removals when event collection is disabled', () async {
      final exporter = TestExporter();
      final chronicler = createEventChronicler(exporter)
        ..setCollectionEnabled(ChroniclerSignal.events, enabled: false);

      Context()
          .withChronicler(chronicler.recorder)
          .events
          .unsetUserProperties(userId: 'user', keys: const ['plan']);
      await Future<void>.delayed(Duration.zero);

      expect(exporter.batches, isEmpty);
      expect(chronicler.diagnosticCounts[DiagnosticReason.collectionDisabled], BigInt.one);
    });

    test('should reject a property removal expanded beyond limits by a hook', () async {
      final exporter = TestExporter();
      final chronicler = Chronicler(
        appId: 'app',
        release: 'release',
        source: ChroniclerSource.server,
        exporter: exporter,
        options: ChroniclerOptions(
          delivery: const DeliveryOptions(maxBatchRecords: 1),
          redaction: RedactionOptions(
            beforeRecord: (record) {
              final update = record as UserPropertiesUnsetRecord;
              return update.copyWith(
                payload: update.payload.copyWith(
                  keys: List.generate(100, (index) => '$index${'x' * 1024}'),
                ),
              );
            },
          ),
        ),
      );

      Context()
          .withChronicler(chronicler.recorder)
          .events
          .unsetUserProperties(userId: 'user', keys: const ['plan']);
      await Future<void>.delayed(Duration.zero);

      expect(exporter.batches, isEmpty);
      expect(chronicler.diagnosticCounts[DiagnosticReason.recordTooLarge], BigInt.one);
    });

    test('should emit explicit user properties without changing Context identity', () async {
      final exporter = TestExporter();
      final chronicler = createEventChronicler(exporter, maxBatchRecords: 2);
      final context = Context().withChronicler(chronicler.recorder).withIdentity(userId: 'caller');

      context.events.setUserProperties(
        userId: 'target',
        properties: {'plan': 'pro', 'nullable': null},
      );
      context.events.track('after_set');

      await Future<void>.delayed(Duration.zero);
      final update = exporter.batches.single.records.first as UserPropertiesSetRecord;
      final event = exporter.batches.single.records.last as ProductEventRecord;
      expect(update.envelope.userId, 'caller');
      expect(update.payload.userId, 'target');
      expect(update.payload.properties, {'plan': 'pro', 'nullable': null});
      expect(event.envelope.userId, 'caller');
    });

    test('should make empty property sets no-ops before target and capture checks', () async {
      final exporter = TestExporter();
      final chronicler = createEventChronicler(exporter);
      Context()
          .withChronicler(chronicler.recorder)
          .events
          .setUserProperties(userId: '', properties: const {});
      chronicler.setCollectionEnabled(ChroniclerSignal.events, enabled: false);
      Context()
          .withChronicler(chronicler.recorder)
          .events
          .setUserProperties(userId: '', properties: const {});
      await Future<void>.delayed(Duration.zero);

      expect(exporter.batches, isEmpty);
      expect(chronicler.diagnosticCounts, isEmpty);
    });

    test('should reject an invalid set target or property atomically', () async {
      final exporter = TestExporter();
      final chronicler = createEventChronicler(exporter);
      final events = Context().withChronicler(chronicler.recorder).events;
      final cyclic = <String, Object?>{};
      cyclic['self'] = cyclic;

      events
        ..setUserProperties(userId: '', properties: const {'valid': true})
        ..setUserProperties(userId: 'target', properties: cyclic);
      await Future<void>.delayed(Duration.zero);

      expect(exporter.batches, isEmpty);
      expect(chronicler.diagnosticCounts[DiagnosticReason.invalidRecord], BigInt.two);
    });

    test('should snapshot, redact, and retry one unsampled property set', () async {
      final exporter = TestExporter();
      var hookCalls = 0;
      final properties = <String, Object?>{
        'password': 'secret',
        'nested': <String, Object?>{'value': 'before'},
        'nullable': null,
      };
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
              final update = record as UserPropertiesSetRecord;
              return update.copyWith(
                payload: update.payload.copyWith(
                  properties: {...update.payload.properties, 'authCode': 'secret'},
                ),
              );
            },
          ),
        ),
      );
      Context()
          .withChronicler(chronicler.recorder)
          .withIdentity(userId: 'caller')
          .events
          .setUserProperties(userId: 'password', properties: properties);
      (properties['nested']! as Map<String, Object?>)['value'] = 'after';
      await waitForEventAttempts(exporter, 1);
      final first = exporter.batches.single.records.single as UserPropertiesSetRecord;
      exporter.attempts.first.completer.complete(const ExportResult.retryable());
      await waitForEventAttempts(exporter, 2);
      final retried = exporter.batches.last.records.single as UserPropertiesSetRecord;

      expect(hookCalls, 1);
      expect(first.envelope.userId, 'caller');
      expect(first.payload.userId, 'password');
      expect(first.payload.properties, {
        'password': '[REDACTED]',
        'nested': {'value': 'before'},
        'nullable': null,
        'authCode': '[REDACTED]',
      });
      expect(retried.envelope.eventId, first.envelope.eventId);
      expect(retried.envelope.timestamp, first.envelope.timestamp);
      expect(retried.payload, first.payload);
      expect(chronicler.diagnosticCounts[DiagnosticReason.sampledOut], isNull);
      exporter.attempts.last.completer.complete(const ExportResult.accepted());
    });

    test('should prevent nonempty property sets when event collection is disabled', () async {
      final exporter = TestExporter();
      final chronicler = createEventChronicler(exporter)
        ..setCollectionEnabled(ChroniclerSignal.events, enabled: false);

      Context()
          .withChronicler(chronicler.recorder)
          .events
          .setUserProperties(userId: 'user', properties: const {'plan': 'pro'});
      await Future<void>.delayed(Duration.zero);

      expect(exporter.batches, isEmpty);
      expect(chronicler.diagnosticCounts[DiagnosticReason.collectionDisabled], BigInt.one);
    });
  });
}
