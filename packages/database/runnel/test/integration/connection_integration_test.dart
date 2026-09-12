@Tags(['integration'])
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:runnel/runnel.dart';
import 'package:test/test.dart';

void main() {
  final endpoints = <String, String?>{
    'Redis TCP': Platform.environment['RUNNEL_REDIS_URL'],
    'Redis TLS': Platform.environment['RUNNEL_REDIS_TLS_URL'],
    'Valkey TCP': Platform.environment['RUNNEL_VALKEY_URL'],
    'Valkey TLS': Platform.environment['RUNNEL_VALKEY_TLS_URL'],
  };

  group('Runnel integration', () {
    for (final MapEntry(key: name, value: endpoint) in endpoints.entries) {
      for (final protocol in RedisProtocol.values) {
        test(
          'should round-trip text and binary through $name using ${protocol.name}',
          () async {
            if (endpoint == null) {
              markTestSkipped('Set the Runnel integration endpoint environment variables.');
              return;
            }
            final securityContext = endpoint.startsWith('rediss://')
                ? (SecurityContext()..setTrustedCertificates(
                    Platform.environment['RUNNEL_TLS_CA'] ??
                        (throw StateError('RUNNEL_TLS_CA is required for TLS tests.')),
                  ))
                : null;
            final client = await Runnel.connect(
              endpoint,
              protocol: protocol,
              securityContext: securityContext,
            );
            addTearDown(client.close);
            final suffix = '${DateTime.now().microsecondsSinceEpoch}-${protocol.name}';
            final textKey = 'runnel:integration:text:$suffix';
            final bytesKey = 'runnel:integration:bytes:$suffix';

            expect(await client.ping(), isTrue);
            expect(await client.set(textKey, 'café'), isTrue);
            expect(await client.get(textKey), 'café');
            expect(await client.setBytes(bytesKey, Uint8List.fromList([0, 255, 13, 10])), isTrue);
            expect(await client.getBytes(bytesKey), [0, 255, 13, 10]);

            final conditionalKey = 'runnel:integration:conditional:$suffix';
            expect(
              await client.set(
                conditionalKey,
                'first',
                condition: SetCondition.ifAbsent,
                expiry: Expiry.after(const Duration(seconds: 5)),
              ),
              isTrue,
            );
            expect(
              await client.set(
                conditionalKey,
                'ignored',
                condition: SetCondition.ifAbsent,
              ),
              isFalse,
            );
            expect(
              await client.set(
                conditionalKey,
                'second',
                condition: SetCondition.ifPresent,
                expiry: const Expiry.keep(),
              ),
              isTrue,
            );
            expect(await client.pttl(conditionalKey), inInclusiveRange(1, 5000));
            expect(await client.set(conditionalKey, 'without-expiry'), isTrue);
            expect(await client.pttl(conditionalKey), -1);
            expect(
              await client.set(
                conditionalKey,
                'absolute-expiry',
                expiry: Expiry.at(
                  DateTime.fromMillisecondsSinceEpoch(
                    DateTime.now().millisecondsSinceEpoch + 10000,
                    isUtc: true,
                  ),
                ),
              ),
              isTrue,
            );
            expect(await client.pttl(conditionalKey), inInclusiveRange(1, 10000));
            expect(await client.persist(conditionalKey), isTrue);
            expect(await client.pttl(conditionalKey), -1);

            final first = 'runnel:integration:scalar:$suffix:first';
            final second = 'runnel:integration:scalar:$suffix:second';
            await client.mset({first: 'one', second: 'two'});
            expect(await client.mget([first, 'missing:$suffix', first]), ['one', null, 'one']);
            expect(await client.exists([first, first, second]), 3);
            expect(await client.type(first), 'string');
            expect(await client.expire(second, Duration.zero), isTrue);
            expect(await client.pttl(second), -2);
            final counter = 'runnel:integration:counter:$suffix';
            expect(await client.incr(counter), 1);
            expect(await client.incrby(counter, 4), 5);
            expect(await client.decr(counter), 4);
            expect(await client.decrby(counter, 2), 2);

            final scanned = await client
                .scan(
                  match: 'runnel:integration:scalar:$suffix:*',
                  count: 1,
                )
                .toSet();
            expect(scanned, contains(first));
            expect(await client.del([first]), 1);
            expect(await client.unlink([conditionalKey]), 1);

            expect(
              await client.execute(
                RedisCommand<String>(
                  [RedisArgument.text('ECHO'), RedisArgument.text('custom')],
                  respText,
                ),
              ),
              'custom',
            );
          },
        );
      }
    }
  });
}
