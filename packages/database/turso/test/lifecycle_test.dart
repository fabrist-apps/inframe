@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';

import 'package:test/test.dart';
import 'package:turso/turso.dart';

void main() {
  group('TursoDatabase lifecycle', () {
    test('close drains an accepted transaction and rejects new root work', () async {
      final database = await TursoDatabase.open(TursoLocation.memory());
      final entered = Completer<void>();
      final continueTransaction = Completer<void>();

      final transaction = database.transaction((tx) async {
        entered.complete();
        await continueTransaction.future;
        await tx.execute('CREATE TABLE after_close_started (value INTEGER)');
        return 42;
      });
      await entered.future;

      final firstClose = database.close();
      final secondClose = database.close();
      expect(identical(firstClose, secondClose), isTrue);
      await expectLater(database.query('SELECT 1'), throwsStateError);

      continueTransaction.complete();
      expect(await transaction, 42);
      await firstClose;
      await secondClose;
      await expectLater(database.execute('SELECT 1'), throwsStateError);
    });

    test('ordinary SQL errors leave the connection usable', () async {
      final database = await TursoDatabase.open(TursoLocation.memory());
      addTearDown(database.close);

      await expectLater(
        database.query('SELECT * FROM missing_table'),
        throwsA(isA<TursoDatabaseException>()),
      );
      final result = await database.query('SELECT 42 AS value');
      expect(result.rows.single.getInt('value'), 42);
    });

    test('failed open releases resources acquired during initialization', () async {
      final temporaryDirectory = await Directory.systemTemp.createTemp('turso-open-failure-');
      addTearDown(() => temporaryDirectory.delete(recursive: true));
      final parent = Directory('${temporaryDirectory.path}/parent');
      final path = '${parent.path}/database.db';

      await expectLater(
        TursoDatabase.open(TursoLocation.file(path)),
        throwsA(isA<TursoDatabaseException>()),
      );

      await parent.create();
      final database = await TursoDatabase.open(TursoLocation.file(path));
      await database.close();
    });

    test('failed rollback preserves both failures and retires the connection', () async {
      final database = await TursoDatabase.open(TursoLocation.memory());
      addTearDown(database.close);
      final callbackEntered = Completer<void>();
      final failCallback = Completer<void>();
      const primaryFailure = _LifecycleFailure();

      final transaction = database.transaction<void>((tx) async {
        await tx.execute('ROLLBACK');
        callbackEntered.complete();
        await failCallback.future;
        await _throwLifecycleFailure(primaryFailure);
      });
      await callbackEntered.future;
      final queued = database.query('SELECT 1');
      failCallback.complete();

      final failure = await _captureTransactionFailure(transaction);
      expect(failure.primaryError, same(primaryFailure));
      expect(failure.primaryStackTrace.toString(), contains('_throwLifecycleFailure'));
      expect(failure.rollbackError, isA<TursoDatabaseException>());
      expect(failure.rollbackStackTrace, isNot(StackTrace.empty));
      await expectLater(queued, throwsA(isA<TursoPlatformException>()));
      await expectLater(database.query('SELECT 1'), throwsA(isA<TursoPlatformException>()));
    });

    test('failed commit never returns success or replays the callback', () async {
      final database = await TursoDatabase.open(TursoLocation.memory());
      addTearDown(database.close);
      var callbacks = 0;

      final transaction = database.transaction((tx) async {
        callbacks += 1;
        await tx.execute('ROLLBACK');
        return 42;
      });

      final failure = await _captureTransactionFailure(transaction);
      expect(failure.primaryError, isA<TursoDatabaseException>());
      expect(failure.rollbackError, isA<TursoDatabaseException>());
      expect(callbacks, 1);
    });

    test('failed rollback releases native database files', () async {
      final temporaryDirectory = await Directory.systemTemp.createTemp('turso-retirement-');
      final path = '${temporaryDirectory.path}/database.db';
      final database = await TursoDatabase.open(TursoLocation.file(path));
      await database.execute('CREATE TABLE values_table (value INTEGER PRIMARY KEY)');

      await expectLater(
        database.transaction((tx) async {
          await tx.execute('INSERT INTO values_table VALUES (1)');
          await tx.execute('INSERT OR ROLLBACK INTO values_table VALUES (1)');
        }),
        throwsA(isA<TursoTransactionException>()),
      );
      await database.close();

      expect(await _openNativeFiles(path), isEmpty);
      await temporaryDirectory.delete(recursive: true);
    });
  });
}

Future<TursoTransactionException> _captureTransactionFailure(Future<Object?> operation) async {
  try {
    await operation;
  } on TursoTransactionException catch (error) {
    return error;
  }
  fail('Expected a TursoTransactionException.');
}

Future<Never> _throwLifecycleFailure(Exception failure) async {
  throw failure;
}

final class _LifecycleFailure implements Exception {
  const _LifecycleFailure();
}

Future<List<String>> _openNativeFiles(String path) async {
  final canonicalPath = File(path).resolveSymbolicLinksSync();
  if (Platform.isLinux) {
    return [
      for (final descriptor in Directory('/proc/self/fd').listSync())
        if (_resolvedPath(descriptor)?.startsWith(canonicalPath) ?? false)
          _resolvedPath(descriptor)!,
    ];
  }
  if (Platform.isMacOS) {
    final result = await Process.run('lsof', ['-p', '$pid', '-Fn']);
    return result.stdout
        .toString()
        .split('\n')
        .where((line) => line.startsWith('n$canonicalPath'))
        .map((line) => line.substring(1))
        .toList();
  }
  return const [];
}

String? _resolvedPath(FileSystemEntity descriptor) {
  try {
    return descriptor.resolveSymbolicLinksSync();
  } on FileSystemException {
    return null;
  }
}
