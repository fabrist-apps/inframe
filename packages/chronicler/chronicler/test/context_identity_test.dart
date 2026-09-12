import 'package:chronicler/chronicler.dart';
import 'package:chronicler/src/runtime.dart';
import 'package:context/context.dart';
import 'package:test/test.dart';

import 'support/events_support.dart';
import 'support/exporter.dart';

void main() {
  group('Chronicler Context identity', () {
    test('should replace complete identity while preserving other context state', () async {
      final exporter = TestExporter();
      final chronicler = createEventChronicler(exporter, maxBatchRecords: 5);
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
      final chronicler = createEventChronicler(exporter, maxBatchRecords: 4);
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
      final chronicler = createEventChronicler(exporter, maxBatchRecords: 2);
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
      final chronicler = createEventChronicler(exporter, maxBatchRecords: 2);
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
  });
}
