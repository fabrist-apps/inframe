@TestOn('vm')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:turso/turso.dart';

void main() {
  group('TursoDatabase native', () {
    late Directory temporaryDirectory;

    setUp(() {
      temporaryDirectory = Directory.systemTemp.createTempSync('turso-dart-test-');
    });

    tearDown(() {
      temporaryDirectory.deleteSync(recursive: true);
    });

    test('should persist parameterized SQL across close and reopen', () async {
      final path = '${temporaryDirectory.path}/database.turso';
      final database = await TursoDatabase.open(TursoLocation.file(path));
      await database.execute(
        'CREATE TABLE notes (id INTEGER PRIMARY KEY, title TEXT, score REAL, payload BLOB)',
      );
      final payload = Uint8List.fromList([1, 2, 3]);
      final insert = database.query(
        'INSERT INTO notes (id, title, score, payload) VALUES (?, ?, ?, ?) RETURNING id',
        parameters: [BigInt.parse('9223372036854775807'), 'Hello', 2.5, payload],
      );
      payload[0] = 99;

      expect((await insert).rows.single.getBigInt('id'), BigInt.parse('9223372036854775807'));
      final update = await database.execute(
        'UPDATE notes SET title = ? WHERE id = ?',
        parameters: ['Updated', BigInt.parse('9223372036854775807')],
      );
      expect(update.rowsAffected, BigInt.one);
      await database.close();

      final reopened = await TursoDatabase.open(TursoLocation.file(path));
      final result = await reopened.query(
        'SELECT id, title, score, payload FROM notes WHERE id = :id',
        namedParameters: {':id': BigInt.parse('9223372036854775807')},
      );
      expect(result.columns.map((column) => column.name), ['id', 'title', 'score', 'payload']);
      expect(result.rows.single.getBigInt('id'), BigInt.parse('9223372036854775807'));
      expect(result.rows.single.getString('title'), 'Updated');
      expect(result.rows.single.getDouble('score'), 2.5);
      expect(result.rows.single.getBlob('payload'), [1, 2, 3]);
      await reopened.close();
    });

    for (final cipher in TursoCipher.values) {
      test('should persist ${cipher.name} encryption without plaintext fallback', () async {
        final path = '${temporaryDirectory.path}/${cipher.name}.turso';
        final key = Uint8List.fromList(List<int>.generate(32, (index) => index + 1));
        final encryption = TursoEncryption(cipher: cipher, key: key);
        final database = await TursoDatabase.open(
          TursoLocation.file(path),
          encryption: encryption,
        );
        await database.execute('CREATE TABLE secrets (value TEXT)');
        await database.execute(
          'INSERT INTO secrets VALUES (?)',
          parameters: const ['encrypted'],
        );
        await database.close();

        final wrongKey = Uint8List.fromList(key)..[0] ^= 0xff;
        final wrongHex = wrongKey.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
        await expectLater(
          TursoDatabase.open(
            TursoLocation.file(path),
            encryption: TursoEncryption(cipher: cipher, key: wrongKey),
          ),
          throwsA(
            isA<TursoDatabaseException>().having(
              (error) => error.message,
              'diagnostic',
              isNot(contains(wrongHex)),
            ),
          ),
        );
        await expectLater(
          TursoDatabase.open(TursoLocation.file(path)),
          throwsA(isA<TursoDatabaseException>()),
        );

        final reopened = await TursoDatabase.open(
          TursoLocation.file(path),
          encryption: encryption,
        );
        final result = await reopened.query('SELECT value FROM secrets');
        expect(result.rows.single.getString('value'), 'encrypted');
        await reopened.close();
      });
    }

    test('should preserve duplicate columns by index', () async {
      final database = await TursoDatabase.open(TursoLocation.memory());
      addTearDown(database.close);

      final result = await database.query('SELECT 1 AS value, 2 AS value');

      expect(result.rows.single.valueAt(0), BigInt.one);
      expect(result.rows.single.valueAt(1), BigInt.two);
      expect(() => result.rows.single.value('value'), throwsStateError);
    });

    test('should reject invalid bindings and trailing statements', () async {
      final database = await TursoDatabase.open(TursoLocation.memory());
      addTearDown(database.close);

      await expectLater(database.query('SELECT ?'), throwsArgumentError);
      await expectLater(
        database.query('SELECT :id', namedParameters: const {':other': 1}),
        throwsArgumentError,
      );
      await expectLater(database.query('SELECT 1; SELECT 2'), throwsArgumentError);
      await expectLater(
        database.query('SELECT 1 AS value\u0000; SELECT 2 AS value'),
        throwsArgumentError,
      );
      final repeated = await database.query(
        'SELECT :value + :value AS total',
        namedParameters: const {':value': 2},
      );
      expect(repeated.rows.single.getInt('total'), 4);
      await expectLater(database.query('SELECT ?', parameters: [double.nan]), throwsArgumentError);
      await expectLater(database.query('SELECT ?', parameters: [true]), throwsArgumentError);
      await expectLater(
        database.query('SELECT ?', parameters: const [1], namedParameters: const {':value': 1}),
        throwsArgumentError,
      );
      await expectLater(
        database.query('SELECT ?', parameters: [BigInt.parse('9223372036854775808')]),
        throwsArgumentError,
      );
      await expectLater(
        database.query('SELECT ?', parameters: [9007199254740992]),
        throwsArgumentError,
      );
    });

    test('should preserve exact SQL value types and execute semantics', () async {
      final database = await TursoDatabase.open(TursoLocation.memory());
      addTearDown(database.close);

      final result = await database.query(
        'SELECT ? AS minimum, ? AS maximum, ? AS null_value, '
        '? AS integral_number, ? AS real_number, CAST(? AS REAL) AS forced_real',
        parameters: [
          BigInt.parse('-9223372036854775808'),
          BigInt.parse('9223372036854775807'),
          null,
          7.0,
          7.5,
          7,
        ],
      );
      final row = result.rows.single;
      expect(row.getBigInt('minimum'), BigInt.parse('-9223372036854775808'));
      expect(row.getBigInt('maximum'), BigInt.parse('9223372036854775807'));
      expect(row.value('null_value'), isNull);
      expect(row.getBigInt('integral_number'), BigInt.from(7));
      expect(row.getDouble('real_number'), 7.5);
      expect(row.getDouble('forced_real'), 7.0);

      await database.execute('CREATE TABLE changed (value INTEGER)');
      final inserted = await database.execute(
        'INSERT INTO changed VALUES (1), (2) RETURNING value',
      );
      expect(inserted.rowsAffected, BigInt.two);
      expect(
        (await database.query('SELECT count(*) AS count FROM changed')).rows.single.getInt('count'),
        2,
      );
    });

    test('should snapshot named parameters before queued execution', () async {
      final database = await TursoDatabase.open(TursoLocation.memory());
      addTearDown(database.close);
      await database.execute('CREATE TABLE snapshots (value TEXT)');

      final named = <String, Object?>{':value': 'before'};
      final pending = database.execute(
        'INSERT INTO snapshots VALUES (:value)',
        namedParameters: named,
      );
      named[':value'] = 'after';
      await pending;

      final result = await database.query('SELECT value FROM snapshots');
      expect(result.rows.single.getString('value'), 'before');
    });

    test('should make memory opening nonpersistent and close idempotently', () async {
      final first = await TursoDatabase.open(TursoLocation.memory());
      await first.execute('CREATE TABLE local_only (value INTEGER)');
      await first.close();
      await first.close();
      await expectLater(first.query('SELECT 1'), throwsStateError);

      final second = await TursoDatabase.open(TursoLocation.memory());
      addTearDown(second.close);
      await expectLater(
        second.query('SELECT * FROM local_only'),
        throwsA(isA<TursoDatabaseException>()),
      );
      expect((await second.query('SELECT 1 AS value')).rows.single.getInt('value'), 1);
    });

    test('should reject browser locations and web options on native platforms', () async {
      await expectLater(
        TursoDatabase.open(TursoLocation.browser('database')),
        throwsA(isA<TursoUnsupportedException>()),
      );
      await expectLater(
        TursoDatabase.open(
          TursoLocation.memory(),
          web: TursoWebOptions(moduleUri: Uri.parse('bridge.js')),
        ),
        throwsArgumentError,
      );
    });
  });
}
