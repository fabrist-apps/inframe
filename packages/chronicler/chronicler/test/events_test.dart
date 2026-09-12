import 'package:chronicler/chronicler.dart';
import 'package:chronicler/src/runtime.dart';
import 'package:context/context.dart';
import 'package:test/test.dart';

import 'support/exporter.dart';

void main() {
  group('ChroniclerEvents', () {
    test('should emit explicit user properties without changing Context identity', () async {
      final exporter = TestExporter();
      final chronicler = _chronicler(exporter, maxBatchRecords: 2);
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
      final chronicler = _chronicler(exporter);
      Context()
          .withChronicler(chronicler.recorder)
          .events
          .setUserProperties(userId: '', properties: const {});
      chronicler.setCollectionEnabled(ChroniclerSignal.events, false);
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
      final chronicler = _chronicler(exporter);
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
      ChroniclerDeliveryFixture.selectRetryDelay(chronicler, (_, _) => Duration.zero);
      Context()
          .withChronicler(chronicler.recorder)
          .withIdentity(userId: 'caller')
          .events
          .setUserProperties(userId: 'password', properties: properties);
      (properties['nested']! as Map<String, Object?>)['value'] = 'after';
      await _waitForAttempts(exporter, 1);
      final first = exporter.batches.single.records.single as UserPropertiesSetRecord;
      exporter.attempts.first.completer.complete(const ExportResult.retryable());
      await _waitForAttempts(exporter, 2);
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
      final chronicler = _chronicler(exporter)
        ..setCollectionEnabled(ChroniclerSignal.events, false);

      Context()
          .withChronicler(chronicler.recorder)
          .events
          .setUserProperties(userId: 'user', properties: const {'plan': 'pro'});
      await Future<void>.delayed(Duration.zero);

      expect(exporter.batches, isEmpty);
      expect(chronicler.diagnosticCounts[DiagnosticReason.collectionDisabled], BigInt.one);
    });

    test('should emit an explicit identity link without changing Context identity', () async {
      final exporter = TestExporter();
      final chronicler = _chronicler(exporter, maxBatchRecords: 2);
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
      final chronicler = _chronicler(exporter);
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
      await _waitForAttempts(exporter, 1);
      final first = exporter.batches.single.records.single as IdentityLinkRecord;
      exporter.attempts.first.completer.complete(const ExportResult.retryable());
      await _waitForAttempts(exporter, 2);
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
      final disabled = _chronicler(disabledExporter)
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
          redaction: RedactionOptions(beforeRecord: _dropRecord),
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

    test('should replace complete identity while preserving other context state', () async {
      final exporter = TestExporter();
      final chronicler = _chronicler(exporter, maxBatchRecords: 5);
      final authKey = ContextKey<Object>('auth');
      final auth = Object();
      final correlated = ChroniclerCaptureFixture.withCorrelation(
        chronicler.recorder,
        traceId: '1' * 32,
        spanId: '2' * 16,
      );
      final base = Context()
          .withBinding(authKey.bind(auth))
          .withChronicler(correlated)
          .withIdentity(
            userId: 'alice',
            anonymousId: 'anonymous',
            sessionId: 'session',
          );
      final userOnly = base.withIdentity(userId: 'bob');
      final anonymousOnly = base.withIdentity(anonymousId: 'next-anonymous');
      final sessionOnly = base.withIdentity(sessionId: 'next-session');
      final cleared = base.withIdentity();

      base.events.track('base');
      userOnly.events.track('user_only');
      anonymousOnly.events.track('anonymous_only');
      sessionOnly.events.track('session_only');
      cleared.events.track('cleared');

      await Future<void>.delayed(Duration.zero);
      final records = exporter.batches.single.records.cast<ProductEventRecord>().toList();
      expect(
        records.map(
          (record) => (
            record.envelope.userId,
            record.envelope.anonymousId,
            record.envelope.sessionId,
          ),
        ),
        [
          ('alice', 'anonymous', 'session'),
          ('bob', null, null),
          (null, 'next-anonymous', null),
          (null, null, 'next-session'),
          (null, null, null),
        ],
      );
      for (final record in records) {
        expect(record.envelope.traceId, '1' * 32);
        expect(record.envelope.spanId, '2' * 16);
      }
      expect(base.require(authKey), same(auth));
      expect(userOnly.require(authKey), same(auth));
      expect(cleared.require(authKey), same(auth));
    });

    test('should isolate sibling identities and snapshot queued attribution', () async {
      final exporter = TestExporter();
      final chronicler = _chronicler(exporter, maxBatchRecords: 4);
      final base = Context().withChronicler(chronicler.recorder);
      final alice = base.withIdentity(userId: 'alice', sessionId: 'alice-session');
      final bob = base.withIdentity(userId: 'bob', sessionId: 'bob-session');

      alice.events.track('alice_before');
      final changedAlice = alice.withIdentity(userId: 'alice-2');
      bob.events.track('bob');
      changedAlice.events.track('alice_after');
      base.events.track('system');

      await Future<void>.delayed(Duration.zero);
      final records = exporter.batches.single.records.cast<ProductEventRecord>().toList();
      expect(records.map((record) => record.envelope.userId), [
        'alice',
        'bob',
        'alice-2',
        null,
      ]);
      expect(records.first.envelope.sessionId, 'alice-session');
      expect(records[2].envelope.sessionId, isNull);
    });

    test('should apply derived identity to logs and events', () async {
      final exporter = TestExporter();
      final chronicler = _chronicler(exporter, maxBatchRecords: 2);
      final request = Context()
          .withChronicler(chronicler.recorder)
          .withIdentity(userId: 'user', sessionId: 'session');

      request.logs.info('log');
      request.events.track('event');

      await Future<void>.delayed(Duration.zero);
      for (final record in exporter.batches.single.records) {
        expect(record.envelope.userId, 'user');
        expect(record.envelope.sessionId, 'session');
      }
    });

    test('should reject invalid identity without changing the source context', () async {
      final exporter = TestExporter();
      final chronicler = _chronicler(exporter, maxBatchRecords: 2);
      final source = Context().withChronicler(chronicler.recorder).withIdentity(userId: 'base');

      expect(
        () => source.withIdentity(userId: ''),
        throwsA(isA<ChroniclerConfigurationException>()),
      );
      expect(
        () => source.withIdentity(userId: '😀' * 65),
        throwsA(isA<ChroniclerConfigurationException>()),
      );
      expect(
        () => source.withIdentity(userId: String.fromCharCode(0xd800)),
        throwsA(isA<ChroniclerConfigurationException>()),
      );
      final boundary = source.withIdentity(userId: '😀' * 64);
      source.events.track('still_base');
      boundary.events.track('boundary');

      await Future<void>.delayed(Duration.zero);
      final records = exporter.batches.expand((batch) => batch.records).toList();
      expect(records.map((record) => record.envelope.userId), ['base', '😀' * 64]);
    });

    test('should validate and deeply snapshot event input atomically', () async {
      final exporter = TestExporter();
      final chronicler = _chronicler(exporter);
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
      final sampled = _chronicler(
        sampledExporter,
        sampling: const SamplingOptions(events: 0),
      );
      Context().withChronicler(sampled.recorder).events.track('sampled_out');

      final disabledExporter = TestExporter();
      final disabled = _chronicler(disabledExporter)
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
      await _waitForAttempts(exporter, 1);
      final first = exporter.batches.single.records.single as ProductEventRecord;

      exporter.attempts.first.completer.complete(const ExportResult.retryable());
      await _waitForAttempts(exporter, 2);
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
      final chronicler = _chronicler(exporter);
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

Chronicler _chronicler(
  TestExporter exporter, {
  int maxBatchRecords = 1,
  ChroniclerLimits limits = const ChroniclerLimits(),
  SamplingOptions sampling = const SamplingOptions(),
}) => Chronicler(
  appId: 'app',
  release: 'release',
  source: ChroniclerSource.server,
  exporter: exporter,
  options: ChroniclerOptions(
    delivery: DeliveryOptions(maxBatchRecords: maxBatchRecords),
    limits: limits,
    sampling: sampling,
  ),
);

Future<void> _waitForAttempts(TestExporter exporter, int count) async {
  while (exporter.attempts.length < count) {
    await Future<void>.delayed(Duration.zero);
  }
}

ChroniclerRecord? _dropRecord(ChroniclerRecord record) => null;
