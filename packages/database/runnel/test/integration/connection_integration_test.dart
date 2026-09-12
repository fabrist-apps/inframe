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
          },
        );
      }
    }
  });
}
