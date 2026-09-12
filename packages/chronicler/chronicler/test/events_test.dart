import 'package:chronicler/chronicler.dart';
import 'package:chronicler/src/runtime.dart';
import 'package:context/context.dart';
import 'package:test/test.dart';

import 'support/events_support.dart';
import 'support/exporter.dart';

void main() {
  group('ChroniclerEvents tracking', () {
    test('should deduplicate before limits and validate every removal atomically', () async {
      final exporter = TestExporter();
      final chronicler = createEventChronicler(exporter);
      final events = Context().withChronicler(chronicler.recorder).events;
      final repeated = List<String>.filled(200, 'password');

      events.unsetUserProperties(userId: 'target', keys: repeated);
      repeated[0] = 'changed';
      events
        ..unsetUserProperties(
          userId: 'target',
          keys: List.generate(129, (index) => 'key$index'),
        )
        ..unsetUserProperties(userId: '', keys: const ['valid'])
        ..unsetUserProperties(userId: 'target', keys: const [''])
        ..unsetUserProperties(userId: 'target', keys: ['x' * 129])
        ..unsetUserProperties(
          userId: 'target',
          keys: [String.fromCharCode(0xd800)],
        );
      await Future<void>.delayed(Duration.zero);

      final record = exporter.batches.single.records.single as UserPropertiesUnsetRecord;
      expect(record.payload.keys, const ['password']);
      expect(chronicler.diagnosticCounts[DiagnosticReason.invalidRecord], BigInt.from(5));
    });

    test('should export a product event with derived identity', () async {
      final exporter = TestExporter();
      final chronicler = Chronicler(
        appId: 'app',
        release: 'release',
        buildId: 'build',
        source: ChroniclerSource.server,
        exporter: exporter,
        options: const ChroniclerOptions(
          delivery: DeliveryOptions(maxBatchRecords: 1),
        ),
      );
      final base = Context().withChronicler(chronicler.recorder);
      final request = base.withIdentity(
        userId: 'user',
        anonymousId: 'anonymous',
        sessionId: 'session',
      );

      request.events.track('purchase_completed', properties: {'total': 1200});

      await Future<void>.delayed(Duration.zero);
      final record = exporter.batches.single.records.single as ProductEventRecord;
      expect(record.envelope.appId, 'app');
      expect(record.envelope.buildId, 'build');
      expect(record.envelope.userId, 'user');
      expect(record.envelope.anonymousId, 'anonymous');
      expect(record.envelope.sessionId, 'session');
      expect(record.payload.name, 'purchase_completed');
      expect(record.payload.properties, {'total': 1200});
    });

    test('should validate and deeply snapshot event input atomically', () async {
      final exporter = TestExporter();
      final chronicler = createEventChronicler(exporter);
      final events = Context().withChronicler(chronicler.recorder).events;
      final properties = <String, Object?>{
        'items': <Object?>[
          {'value': 'before'},
        ],
      };
      final cyclic = <String, Object?>{};
      cyclic['self'] = cyclic;

      events
        ..track('valid', properties: properties)
        ..track('')
        ..track(String.fromCharCode(0xd800))
        ..track('x' * 257)
        ..track('invalid', properties: cyclic)
        ..track('invalid', properties: {'password': Object()});
      ((properties['items']! as List<Object?>).single! as Map<String, Object?>)['value'] = 'after';

      await Future<void>.delayed(Duration.zero);
      final record = exporter.batches.single.records.single as ProductEventRecord;
      expect(record.payload.properties, {
        'items': [
          {'value': 'before'},
        ],
      });
      expect(chronicler.diagnosticCounts[DiagnosticReason.invalidRecord], BigInt.from(5));
    });

    test('should sample ordinary events and obey collection controls', () async {
      final sampledExporter = TestExporter();
      final sampled = createEventChronicler(
        sampledExporter,
        sampling: const SamplingOptions(events: 0),
      );
      Context().withChronicler(sampled.recorder).events.track('sampled_out');

      final disabledExporter = TestExporter();
      final disabled = createEventChronicler(disabledExporter)
        ..setCollectionEnabled(ChroniclerSignal.events, false);
      Context().withChronicler(disabled.recorder).events.track('disabled');
      await Future<void>.delayed(Duration.zero);

      expect(sampledExporter.batches, isEmpty);
      expect(sampled.diagnosticCounts[DiagnosticReason.sampledOut], BigInt.one);
      expect(disabledExporter.batches, isEmpty);
      expect(disabled.diagnosticCounts[DiagnosticReason.collectionDisabled], BigInt.one);
    });

    test('should redact and hook an event once before retrying the snapshot', () async {
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
          redaction: RedactionOptions(
            beforeRecord: (record) {
              hookCalls++;
              final event = record as ProductEventRecord;
              return event.copyWith(
                payload: event.payload.copyWith(
                  properties: {...event.payload.properties, 'accessToken': 'secret'},
                ),
              );
            },
          ),
        ),
      );
      ChroniclerDeliveryFixture.selectRetryDelay(chronicler, (_, _) => Duration.zero);
      Context()
          .withChronicler(chronicler.recorder)
          .events
          .track('event', properties: {'password': 'secret'});
      await waitForEventAttempts(exporter, 1);
      final first = exporter.batches.single.records.single as ProductEventRecord;

      exporter.attempts.first.completer.complete(const ExportResult.retryable());
      await waitForEventAttempts(exporter, 2);
      final retried = exporter.batches.last.records.single as ProductEventRecord;

      expect(hookCalls, 1);
      expect(first.payload.properties, {
        'password': '[REDACTED]',
        'accessToken': '[REDACTED]',
      });
      expect(retried.envelope.eventId, first.envelope.eventId);
      expect(retried.envelope.timestamp, first.envelope.timestamp);
      expect(retried.payload.properties, first.payload.properties);
      exporter.attempts.last.completer.complete(const ExportResult.accepted());
    });

    test('should omit absent identity from the encoded event', () async {
      final exporter = TestExporter();
      final chronicler = createEventChronicler(exporter);
      Context().withChronicler(chronicler.recorder).events.track('system_event');

      await Future<void>.delayed(Duration.zero);
      final record = exporter.batches.single.records.single;
      final encoded = String.fromCharCodes(const ChroniclerCodec().encodeRecord(record));

      expect(encoded, isNot(contains('userId')));
      expect(encoded, isNot(contains('anonymousId')));
      expect(encoded, isNot(contains('sessionId')));
    });

    test('should throw MissingContextValue when event setup is absent', () {
      expect(() => Context().events, throwsA(isA<MissingContextValue>()));
      expect(() => Context().withIdentity(userId: 'user'), throwsA(isA<MissingContextValue>()));
    });
  });
}
