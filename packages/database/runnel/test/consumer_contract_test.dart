import 'package:runnel/runnel.dart';
import 'package:test/test.dart';

import 'fixtures/herald_consumer_fixture.dart';

void main() {
  group('HistoryHandoverFixture', () {
    test(
      'should subscribe before reading history and merge a concurrent publication once',
      () async {
        final calls = <String>[];
        late void Function(HeraldEvent) publishLive;
        final result = await HistoryHandoverFixture().recover(
          expectedEpoch: 'epoch-a',
          lastSeenPosition: 0,
          subscribe: (listener) async {
            calls.add('subscribe');
            publishLive = listener;
          },
          readHistory: () async {
            calls.add('history');
            publishLive(const HeraldEvent(epoch: 'epoch-a', position: 2, payload: 'two'));
            publishLive(const HeraldEvent(epoch: 'epoch-a', position: 3, payload: 'three'));
            return HeraldHistoryPage(
              epoch: 'epoch-a',
              events: const [
                HeraldEvent(epoch: 'epoch-a', position: 1, payload: 'one'),
                HeraldEvent(epoch: 'epoch-a', position: 2, payload: 'two'),
              ],
            );
          },
        );

        expect(calls, ['subscribe', 'history']);
        expect(result.reloadRequired, isFalse);
        expect(result.events.map((event) => event.position), [1, 2, 3]);
        expect(result.events.map((event) => event.payload), ['one', 'two', 'three']);
      },
    );

    test('should request authoritative recovery when a position is missing', () async {
      late void Function(HeraldEvent) publishLive;
      final result = await HistoryHandoverFixture().recover(
        expectedEpoch: 'epoch-a',
        lastSeenPosition: 0,
        subscribe: (listener) async => publishLive = listener,
        readHistory: () async {
          publishLive(const HeraldEvent(epoch: 'epoch-a', position: 3, payload: 'three'));
          return HeraldHistoryPage(
            epoch: 'epoch-a',
            events: const [HeraldEvent(epoch: 'epoch-a', position: 1, payload: 'one')],
          );
        },
      );

      expect(result.reloadRequired, isTrue);
      expect(result.events, isEmpty);
    });

    test('should request authoritative recovery when the stream epoch changes', () async {
      final result = await HistoryHandoverFixture().recover(
        expectedEpoch: 'old',
        lastSeenPosition: 4,
        subscribe: (_) async {},
        readHistory: () async => HeraldHistoryPage(epoch: 'new', events: const []),
      );

      expect(result.reloadRequired, isTrue);
    });
  });

  group('LatestStateFixture', () {
    test(
      'should ignore a stale delta and apply a matching delta buffered during snapshot read',
      () async {
        late void Function(VersionedDelta) publishDelta;
        final result = await LatestStateFixture().recover(
          subscribe: (listener) async => publishDelta = listener,
          readSnapshot: () async {
            publishDelta(
              const VersionedDelta(epoch: 'epoch-a', baseVersion: 4, version: 5, state: 'stale'),
            );
            publishDelta(
              const VersionedDelta(epoch: 'epoch-a', baseVersion: 5, version: 6, state: 'current'),
            );
            return const VersionedSnapshot(epoch: 'epoch-a', version: 5, state: 'snapshot');
          },
        );

        expect(result.reloadRequired, isFalse);
        expect(result.version, 6);
        expect(result.state, 'current');
      },
    );

    test('should reject a delta whose base does not match the complete snapshot', () async {
      late void Function(VersionedDelta) publishDelta;
      final result = await LatestStateFixture().recover(
        subscribe: (listener) async => publishDelta = listener,
        readSnapshot: () async {
          publishDelta(
            const VersionedDelta(epoch: 'epoch-a', baseVersion: 7, version: 8, state: 'gap'),
          );
          return const VersionedSnapshot(epoch: 'epoch-a', version: 5, state: 'snapshot');
        },
      );

      expect(result.reloadRequired, isTrue);
      expect(result.version, 5);
      expect(result.state, 'snapshot');
    });
  });

  group('Herald consumer primitives', () {
    test('should preserve exact app-scoped names and explicit script key order', () {
      final names = HeraldFixtureNames(appId: '42', channel: 'orders');

      expect(names.channelName, 'app:42:herald:orders');
      expect(names.publicationScriptKeys, [
        'app:42:herald:orders:history',
        'app:42:herald:orders:metadata',
        'app:42:herald:orders:snapshot',
        'app:42:herald:orders:receipts',
      ]);
      expect(names.presenceScriptKeys, [
        'app:42:herald:orders:presence:connections',
        'app:42:herald:orders:presence:leases',
      ]);
    });

    test('should keep several connections per user while counting distinct users', () {
      final connections = {
        'connection-a': 'user-1',
        'connection-b': 'user-1',
        'connection-c': 'user-2',
      };

      expect(connections, hasLength(3));
      expect(distinctPresenceUsers(connections), 2);
    });

    test(
      'should decode coordinated publication and presence script results with declared types',
      () {
        final publication = coordinatedPublicationScript.decode(
          RespArray([
            const RespInteger(7),
            const RespInteger(2),
            RespBlobString('1000-0'.codeUnits),
            const RespInteger(0),
          ]),
        );

        expect(publication.position, 7);
        expect(publication.subscriberCount, 2);
        expect(publication.streamId, '1000-0');
        expect(publication.duplicate, isFalse);
        expect(upsertPresenceLeaseScript.decode(const RespInteger(2)), 2);
        expect(removeExpiredPresenceLeasesScript.decode(const RespInteger(1)), 1);
      },
    );
  });

  group('DeliveryPathProbe', () {
    test(
      'should request reconnect when normal publication is not observed despite ready health',
      () async {
        final publications = <String>[];
        final reconnects = <Duration>[];
        final probe = DeliveryPathProbe(
          publish: (channel, payload) async {
            publications.add('$channel:$payload');
            return 1;
          },
          health: () => PubSubState.ready,
          reconnect: (timeout) async => reconnects.add(timeout),
        );

        final result = await probe.check(
          channel: 'app:42:herald:probe',
          token: 'probe-1',
          awaitDelivery: (_, _) async => false,
          deliveryTimeout: const Duration(milliseconds: 50),
          reconnectTimeout: const Duration(seconds: 1),
        );

        expect(publications, ['app:42:herald:probe:probe-1']);
        expect(result.delivered, isFalse);
        expect(result.healthBeforeRecovery, PubSubState.ready);
        expect(result.reconnectRequested, isTrue);
        expect(reconnects, [const Duration(seconds: 1)]);
      },
    );

    test('should not reconnect when the probe traverses the delivery path', () async {
      var reconnects = 0;
      final probe = DeliveryPathProbe(
        publish: (_, _) async => 1,
        health: () => PubSubState.ready,
        reconnect: (_) async => reconnects++,
      );

      final result = await probe.check(
        channel: 'app:42:herald:probe',
        token: 'probe-2',
        awaitDelivery: (token, _) async => token == 'probe-2',
        deliveryTimeout: const Duration(milliseconds: 50),
        reconnectTimeout: const Duration(seconds: 1),
      );

      expect(result.delivered, isTrue);
      expect(result.reconnectRequested, isFalse);
      expect(reconnects, 0);
    });
  });
}
