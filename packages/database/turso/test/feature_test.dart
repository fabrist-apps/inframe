@TestOn('vm')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:turso/turso.dart';

void main() {
  group('Turso native features', () {
    test('advertises and executes vector functions without vector indexes', () async {
      final database = await TursoDatabase.open(TursoLocation.memory());
      addTearDown(database.close);

      expect(database.capabilities.vectorFunctions, isTrue);
      expect(database.capabilities.vectorIndexes, isFalse);
      final result = await database.query(
        "SELECT vector_extract(vector32('[1, 2]')) AS value, "
        "vector_distance_l2(vector32('[0, 0]'), vector32('[3, 4]')) AS distance",
      );
      expect(result.rows.single.getString('value'), '[1,2]');
      expect(result.rows.single.getDouble('distance'), 5.0);
    });

    test('searches committed data and tracks transaction outcomes across reopen', () async {
      final temporaryDirectory = await Directory.systemTemp.createTemp('turso-fts-');
      addTearDown(() => temporaryDirectory.delete(recursive: true));
      final location = TursoLocation.file('${temporaryDirectory.path}/search.db');
      final database = await TursoDatabase.open(location);
      expect(database.capabilities.fts, isTrue);
      await database.execute('CREATE TABLE documents (id INTEGER PRIMARY KEY, body TEXT)');
      await database.execute('CREATE INDEX documents_fts ON documents USING fts (body)');
      await database.execute(
        'INSERT INTO documents VALUES (?, ?), (?, ?)',
        parameters: const [1, 'persistent needle', 2, 'unrelated words'],
      );

      await database.transaction((tx) async {
        await tx.execute(
          'INSERT INTO documents VALUES (?, ?)',
          parameters: const [3, 'transaction needle'],
        );
        final visible = await tx.query(
          "SELECT id FROM documents WHERE fts_match(body, 'needle') ORDER BY id",
        );
        expect(visible.rows.map((row) => row.getInt('id')), [1, 3]);
      });
      await expectLater(
        database.transaction((tx) async {
          await tx.execute(
            'INSERT INTO documents VALUES (?, ?)',
            parameters: const [4, 'rolled back needle'],
          );
          throw const _ExpectedRollback();
        }),
        throwsA(isA<_ExpectedRollback>()),
      );
      await database.close();

      final reopened = await TursoDatabase.open(location);
      final matches = await reopened.query(
        "SELECT id FROM documents WHERE fts_match(body, 'needle') ORDER BY id",
      );
      expect(matches.rows.map((row) => row.getInt('id')), [1, 3]);
      await reopened.close();
    });

    for (final cipher in TursoCipher.values) {
      test('composes ${cipher.name} encryption with FTS', () async {
        final temporaryDirectory = await Directory.systemTemp.createTemp('turso-encrypted-fts-');
        addTearDown(() => temporaryDirectory.delete(recursive: true));
        final location = TursoLocation.file('${temporaryDirectory.path}/search.db');
        final encryption = TursoEncryption(cipher: cipher, key: _encryptionKey());
        final database = await TursoDatabase.open(location, encryption: encryption);
        await database.execute('CREATE TABLE documents (id INTEGER PRIMARY KEY, body TEXT)');
        await database.execute('CREATE INDEX documents_fts ON documents USING fts (body)');
        await database.execute(
          'INSERT INTO documents VALUES (?, ?)',
          parameters: const [1, 'encrypted needle'],
        );
        await expectLater(
          database.transaction((tx) async {
            await tx.execute(
              'INSERT INTO documents VALUES (?, ?)',
              parameters: const [2, 'rolled back needle'],
            );
            throw const _ExpectedRollback();
          }),
          throwsA(isA<_ExpectedRollback>()),
        );
        await database.close();

        final reopened = await TursoDatabase.open(location, encryption: encryption);
        final matches = await reopened.query(
          "SELECT id FROM documents WHERE fts_match(body, 'needle') ORDER BY id",
        );
        expect(matches.rows.map((row) => row.getInt('id')), [1]);
        await reopened.close();
      });
    }
  });
}

Uint8List _encryptionKey() => Uint8List.fromList(List<int>.generate(32, (index) => index + 1));

final class _ExpectedRollback implements Exception {
  const _ExpectedRollback();
}
