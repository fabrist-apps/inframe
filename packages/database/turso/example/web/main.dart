import 'dart:async';
import 'dart:typed_data';

import 'package:turso/turso.dart';
import 'package:web/web.dart' as web;

const _phaseKey = 'turso-dart-web-verification-phase';
const _databaseName = 'turso-dart-web-verification.db';
final _bridge = TursoWebOptions(moduleUri: Uri.parse('turso/turso_bridge.js'));

Future<void> main() async {
  try {
    if (web.window.localStorage.getItem(_phaseKey) == null) {
      await _writePersistentData();
      web.window.localStorage.setItem(_phaseKey, 'reload');
      web.window.location.reload();
      return;
    }

    await _verifyReloadedData();
    await _verifyTransactions();
    await _verifyWorkerDeath();
    await _verifyCloseFailure();
    await _verifyLockRelease();
    await _verifyMemoryDatabase();
    await _verifyPlatformFailures();
    web.window.localStorage.removeItem(_phaseKey);
    web.document.body!.textContent = 'PASS\n${web.window.navigator.userAgent}';
  } on Object catch (error, stackTrace) {
    web.document.body!.textContent = 'FAIL\n$error\n$stackTrace';
  }
}

Future<void> _verifyCloseFailure() async {
  final database = await TursoDatabase.open(
    TursoLocation.memory(),
    web: TursoWebOptions(moduleUri: Uri.parse('failing_close_bridge.js')),
  );
  final firstClose = database.close();
  final secondClose = database.close();
  _expect(identical(firstClose, secondClose), 'Failed closes did not share their shutdown.');
  await _expectFailure<TursoPlatformException>(() => firstClose);
  await _expectFailure<StateError>(() => database.query('SELECT 1'));
}

Future<void> _verifyWorkerDeath() async {
  var stage = 'open';
  try {
    final database = await TursoDatabase.open(
      TursoLocation.memory(),
      web: TursoWebOptions(moduleUri: Uri.parse('crashing_bridge.js')),
    );
    stage = 'pending requests';
    final interrupted = _expectFailure<TursoPlatformException>(() => database.query('SELECT 1'));
    final queued = _expectFailure<TursoPlatformException>(() => database.query('SELECT 2'));
    await Future.wait([interrupted, queued]);
    stage = 'future request';
    await _expectFailure<TursoPlatformException>(() => database.query('SELECT 3'));
    stage = 'close';
    await database.close();
  } on Object catch (error, stackTrace) {
    Error.throwWithStackTrace(
      StateError('Worker death verification failed at $stage: $error'),
      stackTrace,
    );
  }
}

Future<void> _verifyTransactions() async {
  final database = await TursoDatabase.open(TursoLocation.memory(), web: _bridge);
  try {
    await database.execute('CREATE TABLE transactions (value TEXT)');
    final entered = Completer<void>();
    final continueTransaction = Completer<void>();
    late TursoTransaction expired;
    final transaction = database.transaction((tx) async {
      expired = tx;
      await tx.execute('INSERT INTO transactions VALUES (?)', parameters: const ['committed']);
      await _expectFailure<StateError>(() => database.query('SELECT 1'));
      entered.complete();
      await continueTransaction.future;
      return (await tx.query('SELECT value FROM transactions')).rows.single.getString('value');
    });
    await entered.future;
    var rootCompleted = false;
    final root = database.query('SELECT count(*) AS count FROM transactions').whenComplete(() {
      rootCompleted = true;
    });
    await Future<void>.delayed(Duration.zero);
    _expect(!rootCompleted, 'Root work entered an active transaction.');
    continueTransaction.complete();
    final result = await transaction;
    await root;
    _expect(result == 'committed', 'Transaction did not read its write.');
    await _expectFailure<StateError>(() => expired.query('SELECT 1'));

    await _expectFailure<_BrowserTransactionFailure>(
      () => database.transaction((tx) async {
        await tx.execute('INSERT INTO transactions VALUES (?)', parameters: const ['rolled back']);
        throw const _BrowserTransactionFailure();
      }),
    );
    final rows = await database.query('SELECT value FROM transactions');
    _expect(rows.rows.length == 1, 'Failed transaction escaped its rollback.');

    final closeEntered = Completer<void>();
    final finishClosingTransaction = Completer<void>();
    final accepted = database.transaction((tx) async {
      closeEntered.complete();
      await finishClosingTransaction.future;
      await tx.query('SELECT 1');
    });
    await closeEntered.future;
    final firstClose = database.close();
    final secondClose = database.close();
    _expect(identical(firstClose, secondClose), 'Repeated close did not share its shutdown.');
    await _expectFailure<StateError>(() => database.query('SELECT 1'));
    finishClosingTransaction.complete();
    await accepted;
    await firstClose;
  } finally {
    await database.close();
  }
}

Future<void> _writePersistentData() async {
  final database = await TursoDatabase.open(
    TursoLocation.browser(_databaseName),
    web: _bridge,
  );
  try {
    _expect(!database.capabilities.fts, 'Web FTS must remain unavailable.');
    _expect(!database.capabilities.vectorFunctions, 'Unverified vector functions were advertised.');
    _expect(!database.capabilities.vectorIndexes, 'Unverified vector indexes were advertised.');
    await database.execute(
      'CREATE TABLE IF NOT EXISTS values_table ( '
      'minimum INTEGER, maximum INTEGER, title TEXT, payload BLOB)',
    );
    await database.execute('DELETE FROM values_table');

    final blob = Uint8List.fromList([1, 2, 3]);
    final inserted = database.query(
      'INSERT INTO values_table VALUES (:minimum, :maximum, :title, :payload) '
      'RETURNING minimum, maximum',
      namedParameters: {
        ':minimum': BigInt.parse('-9223372036854775808'),
        ':maximum': BigInt.parse('9223372036854775807'),
        ':title': 'before',
        ':payload': blob,
      },
    );
    blob[0] = 99;
    final row = (await inserted).rows.single;
    _expect(row.getBigInt('minimum') == BigInt.parse('-9223372036854775808'), 'Minimum changed.');
    _expect(row.getBigInt('maximum') == BigInt.parse('9223372036854775807'), 'Maximum changed.');

    final update = await database.execute(
      'UPDATE values_table SET title = :title WHERE maximum = :maximum RETURNING title',
      namedParameters: {
        ':title': 'persisted',
        ':maximum': BigInt.parse('9223372036854775807'),
      },
    );
    _expect(update.rowsAffected == BigInt.one, 'execute returned the wrong affected-row count.');

    await _expectFailure<ArgumentError>(() => database.query('SELECT 1; SELECT 2'));
    await _expectFailure<ArgumentError>(() => database.query('SELECT ?'));
    await _expectFailure<ArgumentError>(
      () => database.query('SELECT :id', namedParameters: const {':other': 1}),
    );
    final repeated = await database.query(
      'SELECT :value + :value AS total',
      namedParameters: const {':value': 2},
    );
    _expect(repeated.rows.single.getInt('total') == 4, 'Repeated binding failed.');
  } finally {
    await database.close();
  }
}

Future<void> _verifyReloadedData() async {
  final database = await TursoDatabase.open(
    TursoLocation.browser(_databaseName),
    web: _bridge,
  );
  try {
    final result = await database.query(
      'SELECT minimum, maximum, title, payload, minimum AS duplicate, maximum AS duplicate '
      'FROM values_table',
    );
    final row = result.rows.single;
    _expect(
      row.getBigInt('minimum') == BigInt.parse('-9223372036854775808'),
      'Minimum did not persist.',
    );
    _expect(
      row.getBigInt('maximum') == BigInt.parse('9223372036854775807'),
      'Maximum did not persist.',
    );
    _expect(row.getString('title') == 'persisted', 'Text did not persist.');
    _expect(_listEquals(row.getBlob('payload'), [1, 2, 3]), 'Blob snapshot did not persist.');
    _expect(row.valueAt(4) == BigInt.parse('-9223372036854775808'), 'First duplicate changed.');
    _expect(row.valueAt(5) == BigInt.parse('9223372036854775807'), 'Second duplicate changed.');
    await _expectFailure<StateError>(() async => row.value('duplicate'));
  } finally {
    await database.close();
  }
}

Future<void> _verifyLockRelease() async {
  final owner = await TursoDatabase.open(TursoLocation.browser(_databaseName), web: _bridge);
  await _expectFailure<TursoPlatformException>(
    () => TursoDatabase.open(TursoLocation.browser(_databaseName), web: _bridge),
  );
  await owner.close();

  final reopened = await TursoDatabase.open(TursoLocation.browser(_databaseName), web: _bridge);
  await reopened.close();
}

Future<void> _verifyMemoryDatabase() async {
  final first = await TursoDatabase.open(TursoLocation.memory(), web: _bridge);
  await first.execute('CREATE TABLE local_only (value INTEGER)');
  await first.close();

  final second = await TursoDatabase.open(TursoLocation.memory(), web: _bridge);
  try {
    await _expectFailure<TursoDatabaseException>(() => second.query('SELECT * FROM local_only'));
  } finally {
    await second.close();
  }
}

Future<void> _verifyPlatformFailures() async {
  await _expectFailure<ArgumentError>(() => TursoDatabase.open(TursoLocation.memory()));
  await _expectFailure<TursoUnsupportedException>(
    () => TursoDatabase.open(
      TursoLocation.file('/tmp/database'),
      web: _bridge,
    ),
  );
  await _expectFailure<TursoPlatformException>(
    () => TursoDatabase.open(
      TursoLocation.memory(),
      web: TursoWebOptions(moduleUri: Uri.parse('missing/turso_bridge.js')),
    ),
  );
}

Future<void> _expectFailure<T extends Object>(Future<Object?> Function() action) async {
  try {
    await action();
  } on T {
    return;
  }
  throw StateError('Expected $T.');
}

void _expect(bool condition, String message) {
  if (!condition) throw StateError(message);
}

bool _listEquals(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

final class _BrowserTransactionFailure implements Exception {
  const _BrowserTransactionFailure();
}
