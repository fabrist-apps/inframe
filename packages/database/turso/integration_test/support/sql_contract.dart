import 'dart:async';
import 'dart:typed_data';

import 'package:turso/turso.dart';

Future<void> verifyValues(TursoDatabase database) async {
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
  await _expectFailure<ArgumentError>(
    () => database.query('SELECT ?', parameters: const [true]),
  );
  await _expectFailure<ArgumentError>(
    () => database.query('SELECT ?', parameters: const [double.nan]),
  );
  await _expectFailure<ArgumentError>(
    () => database.query('SELECT ?', parameters: [BigInt.parse('9223372036854775808')]),
  );
  await _expectFailure<ArgumentError>(
    () => database.query(
      'SELECT :value',
      parameters: const [1],
      namedParameters: const {':value': 1},
    ),
  );
  final repeated = await database.query(
    'SELECT :value + :value AS total',
    namedParameters: const {':value': 2},
  );
  _expect(repeated.rows.single.getInt('total') == 4, 'Repeated binding failed.');
  final blobFirst = await database.query(
    'SELECT ? AS payload',
    parameters: [
      Uint8List.fromList([1, 2, 3]),
    ],
  );
  _expect(
    _listEquals(blobFirst.rows.single.getBlob('payload'), const [1, 2, 3]),
    'A first positional BLOB parameter changed.',
  );
}

Future<void> verifyTransactions(TursoDatabase database) async {
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

    await _expectFailure<_TransactionFailure>(
      () => database.transaction<void>((tx) async {
        await tx.execute('INSERT INTO transactions VALUES (?)', parameters: const ['rolled back']);
        throw const _TransactionFailure();
      }),
    );
    final rows = await database.query('SELECT value FROM transactions');
    _expect(rows.rows.length == 1, 'Failed transaction escaped its rollback.');

    await database.transaction((tx) async {
      unawaited(tx.execute('INSERT INTO transactions VALUES (?)', parameters: ['drained']));
    });
    _expect(
      (await database.query('SELECT count(*) AS count FROM transactions')).rows.single
              .getInt('count') ==
          2,
      'Unawaited accepted work was not drained before commit.',
    );
    await _expectFailure<TursoDatabaseException>(
      () => database.transaction<void>((tx) async {
        await tx.execute('INSERT INTO transactions VALUES (?)', parameters: ['must roll back']);
        unawaited(tx.execute('INSERT INTO missing_table VALUES (1)'));
      }),
    );
    for (final query in [false, true]) {
      await _expectFailure<ArgumentError>(
        () => database.transaction<void>((tx) async {
          await tx.execute('INSERT INTO transactions VALUES (?)', parameters: ['must roll back']);
          await _expectFailure<ArgumentError>(
            () => query
                ? tx.query('SELECT ?', parameters: [true])
                : tx.execute('SELECT ?', parameters: [true]),
          );
        }),
      );
    }
    _expect(
      (await database.query('SELECT count(*) AS count FROM transactions')).rows.single
              .getInt('count') ==
          2,
      'An ignored or caught operation failure escaped transaction rollback.',
    );

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

Future<void> _expectFailure<T extends Object>(Future<Object?> Function() action) async {
  try {
    await action();
  } on T {
    return;
  } on Object catch (error) {
    throw StateError('Expected $T, got ${error.runtimeType}: $error');
  }
  throw StateError('Expected $T, but the operation succeeded.');
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

final class _TransactionFailure implements Exception {
  const _TransactionFailure();
}
