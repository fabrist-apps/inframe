import 'dart:io';

import 'package:postgres/postgres.dart' as pg;
import 'package:rivet/rivet.dart';
import 'package:test/test.dart';

import 'generated_consumer.dart';

void main() {
  group('Rivet TLS integration', () {
    final enabled = Platform.environment['RIVET_TEST_TLS'] == '1';
    final image = Platform.environment['RIVET_POSTGRES_IMAGE'] ?? 'inframe/postgres:latest';

    test(
      'should enforce verify-full, require, disable, and custom trust',
      () async {
        final certificates = await Directory.systemTemp.createTemp('rivet-tls-');
        final container = 'inframe-rivet-tls-$pid';
        addTearDown(() async {
          await Process.run('docker', ['stop', container]);
          await certificates.delete(recursive: true);
        });

        await _run('openssl', [
          'req',
          '-x509',
          '-newkey',
          'rsa:2048',
          '-nodes',
          '-keyout',
          '${certificates.path}/ca.key',
          '-out',
          '${certificates.path}/ca.crt',
          '-days',
          '1',
          '-subj',
          '/CN=Rivet Test CA',
          '-addext',
          'basicConstraints=critical,CA:TRUE',
          '-addext',
          'keyUsage=critical,keyCertSign,cRLSign',
        ]);
        await _run('openssl', [
          'req',
          '-newkey',
          'rsa:2048',
          '-nodes',
          '-keyout',
          '${certificates.path}/server.key',
          '-out',
          '${certificates.path}/server.csr',
          '-subj',
          '/CN=localhost',
          '-addext',
          'subjectAltName=DNS:localhost',
          '-addext',
          'extendedKeyUsage=serverAuth',
        ]);
        await _run('openssl', [
          'x509',
          '-req',
          '-in',
          '${certificates.path}/server.csr',
          '-CA',
          '${certificates.path}/ca.crt',
          '-CAkey',
          '${certificates.path}/ca.key',
          '-CAcreateserial',
          '-out',
          '${certificates.path}/server.crt',
          '-days',
          '1',
          '-copy_extensions',
          'copy',
        ]);

        const startPostgres =
            'cp /certs/server.crt /certs/server.key /var/lib/postgresql/; '
            'chown postgres:postgres /var/lib/postgresql/server.crt /var/lib/postgresql/server.key; '
            'chmod 600 /var/lib/postgresql/server.key; '
            'exec docker-entrypoint.sh postgres -c ssl=on '
            '-c ssl_cert_file=/var/lib/postgresql/server.crt '
            '-c ssl_key_file=/var/lib/postgresql/server.key';
        await _run('docker', [
          'run',
          '--detach',
          '--rm',
          '--name',
          container,
          '--publish',
          '127.0.0.1::5432',
          '--env',
          'POSTGRES_PASSWORD=test-password',
          '--env',
          'POSTGRES_DB=inframe_test',
          '--volume',
          '${certificates.path}:/certs:ro',
          '--user',
          'root',
          image,
          'bash',
          '-ceu',
          startPostgres,
        ]);
        await _waitForPostgres(container);
        final port = await _publishedPort(container);

        late pg.Connection fixture;
        try {
          fixture = await pg.Connection.open(
            pg.Endpoint(
              host: 'localhost',
              port: port,
              database: 'inframe_test',
              username: 'postgres',
              password: 'test-password',
            ),
            settings: const pg.ConnectionSettings(sslMode: pg.SslMode.require),
          );
        } on Object {
          final logs = await Process.run('docker', ['logs', container]);
          fail('TLS fixture connection failed:\n${logs.stdout}\n${logs.stderr}');
        }
        await fixture.execute('CREATE SCHEMA fbr116');
        await fixture.execute('CREATE TABLE fbr116."userProfiles" ("displayName" text NOT NULL)');
        await fixture.execute("INSERT INTO fbr116.\"userProfiles\" VALUES ('TLS')");
        await fixture.close();

        final trusted = SecurityContext()..setTrustedCertificates('${certificates.path}/ca.crt');
        try {
          expect(
            await _read(
              RivetConnection.url(
                'postgresql://postgres:test-password@localhost:$port/inframe_test',
                securityContext: trusted,
              ),
            ),
            'TLS',
          );
        } on RivetDatabaseException catch (error) {
          fail('Trusted TLS connection failed: ${error.cause}');
        }
        await expectLater(
          _read(
            RivetConnection.url(
              'postgresql://postgres:test-password@127.0.0.1:$port/inframe_test',
              securityContext: trusted,
            ),
          ),
          throwsA(isA<RivetDatabaseException>()),
        );
        await expectLater(
          _read(
            RivetConnection.url(
              'postgresql://postgres:test-password@localhost:$port/inframe_test',
            ),
          ),
          throwsA(isA<RivetDatabaseException>()),
        );
        expect(
          await _read(
            RivetConnection.url(
              'postgresql://postgres:test-password@127.0.0.1:$port/inframe_test',
              sslMode: RivetSslMode.require,
            ),
          ),
          'TLS',
        );
        expect(
          await _read(
            RivetConnection.url(
              'postgresql://postgres:test-password@127.0.0.1:$port/inframe_test',
              sslMode: RivetSslMode.disable,
            ),
          ),
          'TLS',
        );
      },
      timeout: const Timeout(Duration(minutes: 2)),
      skip: enabled ? false : 'RIVET_TEST_TLS is not enabled.',
    );
  });
}

Future<int> _publishedPort(String container) async {
  final result = await Process.run('docker', ['port', container, '5432/tcp']);
  if (result.exitCode != 0) {
    throw ProcessException(
      'docker',
      ['port', container, '5432/tcp'],
      '${result.stdout}\n${result.stderr}',
      result.exitCode,
    );
  }
  final output = (result.stdout as String).trim();
  return int.parse(output.substring(output.lastIndexOf(':') + 1));
}

Future<String> _read(RivetConnection connection) async {
  final database = await RivetTestDatabase().open(
    connection: connection,
    pool: const RivetPoolOptions(maxConnections: 1),
  );
  try {
    return (await UserProfiles.db.find().getSingle(database)).displayName;
  } finally {
    await database.close();
  }
}

Future<void> _waitForPostgres(String container) async {
  for (var attempt = 0; attempt < 60; attempt++) {
    final result = await Process.run('docker', [
      'exec',
      container,
      'psql',
      '--username',
      'postgres',
      '--dbname',
      'inframe_test',
      '--tuples-only',
      '--command',
      'SELECT 1',
    ]);
    if (result.exitCode == 0) return;
    await Future<void>.delayed(const Duration(seconds: 1));
  }
  throw StateError('TLS PostgreSQL did not become ready.');
}

Future<void> _run(String executable, List<String> arguments) async {
  final result = await Process.run(executable, arguments);
  if (result.exitCode != 0) {
    throw ProcessException(
      executable,
      arguments,
      '${result.stdout}\n${result.stderr}',
      result.exitCode,
    );
  }
}
