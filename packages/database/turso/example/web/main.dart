import 'dart:async';
import 'dart:typed_data';

import 'package:turso/turso.dart';
import 'package:web/web.dart' as web;

const _phaseKey = 'turso-dart-web-verification-phase';
const _databaseName = 'turso-dart-web-verification.db';
const _attachedDatabaseName = 'turso-dart-web-attached.db';
const _memoryMainAttachmentName = 'turso-dart-web-memory-main-attached.db';
final _bridge = TursoWebOptions(moduleUri: Uri.parse('turso/turso_bridge.js'));

Future<void> main() async {
  try {
    if (web.window.localStorage.getItem(_phaseKey) == null) {
      await _writePersistentData();
      await _writePersistentAttachment();
      await _writeEncryptedData();
      web.window.localStorage.setItem(_phaseKey, 'reload');
      web.window.location.reload();
      return;
    }

    await _verifyReloadedData();
    await _verifyPersistentAttachment();
    await _verifyPersistentAttachmentFromMemoryMainIsRejected();
    await _verifyEncryptedData();
    await _verifyTransactions();
    await _verifyWorkerDeath();
    await _verifyCloseFailure();
    await _verifyLockRelease();
    await _verifyMemoryDatabase();
    await _verifyMemoryAttachments();
    await _verifyRepresentativeWorkload();
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

Future<void> _writeEncryptedData() async {
  for (final cipher in TursoCipher.values) {
    final database = await TursoDatabase.open(
      TursoLocation.browser(_encryptedDatabaseName(cipher)),
      encryption: TursoEncryption(cipher: cipher, key: _encryptionKey()),
      web: _bridge,
    );
    try {
      await database.execute('CREATE TABLE IF NOT EXISTS secrets (value TEXT)');
      await database.execute('DELETE FROM secrets');
      await database.execute(
        'INSERT INTO secrets VALUES (?)',
        parameters: ['encrypted with ${cipher.name}'],
      );
    } finally {
      await database.close();
    }
  }
}

Future<void> _verifyEncryptedData() async {
  for (final cipher in TursoCipher.values) {
    final location = TursoLocation.browser(_encryptedDatabaseName(cipher));
    final wrongKey = _encryptionKey()..[0] ^= 0xff;
    await _expectFailure<TursoPlatformException>(
      () => TursoDatabase.open(
        location,
        encryption: TursoEncryption(cipher: cipher, key: wrongKey),
        web: _bridge,
      ),
    );
    await _expectFailure<TursoPlatformException>(
      () => TursoDatabase.open(location, web: _bridge),
    );

    final database = await TursoDatabase.open(
      location,
      encryption: TursoEncryption(cipher: cipher, key: _encryptionKey()),
      web: _bridge,
    );
    try {
      final value = (await database.query('SELECT value FROM secrets')).rows.single.getString(
        'value',
      );
      _expect(value == 'encrypted with ${cipher.name}', '${cipher.name} data did not persist.');
      await database.execute("ATTACH DATABASE ':memory:' AS auxiliary");
      await database.execute('CREATE TABLE auxiliary.items (id INTEGER PRIMARY KEY)');
      await database.execute('INSERT INTO auxiliary.items VALUES (1)');
      _expect(
        (await database.query('SELECT id FROM auxiliary.items')).rows.single.getInt('id') == 1,
        '${cipher.name} memory attachment failed.',
      );
      await database.execute('DETACH DATABASE auxiliary');
    } finally {
      await database.close();
    }
  }
}

String _encryptedDatabaseName(TursoCipher cipher) => 'turso-dart-web-${cipher.name}-encryption.db';

Uint8List _encryptionKey() => Uint8List.fromList(List<int>.generate(32, (index) => index + 1));

Future<void> _verifyVectorFunctions(TursoDatabase database) async {
  final result = await database.query(
    "SELECT vector_extract(vector32('[1, 2]')) AS value, "
    "vector_distance_l2(vector32('[0, 0]'), vector32('[3, 4]')) AS distance",
  );
  _expect(result.rows.single.getString('value') == '[1,2]', 'Vector conversion failed.');
  _expect(result.rows.single.getDouble('distance') == 5.0, 'Vector distance failed.');
}

Future<void> _writePersistentData() async {
  final database = await TursoDatabase.open(
    TursoLocation.browser(_databaseName),
    web: _bridge,
  );
  try {
    _expect(!database.capabilities.fts, 'Web FTS must remain unavailable.');
    _expect(
      database.capabilities.vectorFunctions,
      'Verified vector functions were not advertised.',
    );
    _expect(!database.capabilities.vectorIndexes, 'Unverified vector indexes were advertised.');
    await _verifyVectorFunctions(database);
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
  } finally {
    await database.close();
  }
}

Future<void> _writePersistentAttachment() async {
  final database = await TursoDatabase.open(
    TursoLocation.browser(_databaseName),
    web: _bridge,
  );
  try {
    await database.query("ATTACH DATABASE '$_attachedDatabaseName' AS auxiliary");
    await database.execute(
      'CREATE TABLE IF NOT EXISTS auxiliary.items (id INTEGER PRIMARY KEY)',
    );
    await database.execute('DELETE FROM auxiliary.items');
    await database.execute('INSERT INTO auxiliary.items VALUES (1)');
    _expect(
      (await database.query('SELECT id FROM auxiliary.items')).rows.single.getInt('id') == 1,
      'Persistent browser attachment could not be read.',
    );
    await database.execute('DETACH DATABASE auxiliary');

    await database.transaction((tx) async {
      await tx.execute("ATTACH DATABASE '$_attachedDatabaseName' AS transaction_auxiliary");
      _expect(
        (await tx.query('SELECT id FROM transaction_auxiliary.items')).rows.single.getInt('id') ==
            1,
        'Transaction routes could not read a persistent browser attachment.',
      );
    });
    await database.query('DETACH DATABASE transaction_auxiliary');

    await _expectFailure<TursoUnsupportedException>(
      () => database.execute("ATTACH DATABASE upper('computed.db') AS computed"),
    );
    await _expectFailure<TursoUnsupportedException>(
      () => database.execute("ATTACH DATABASE 'invalid/path.db' AS invalid_path"),
    );
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
    final copiedBlob = row.getBlob('payload')..[0] = 99;
    _expect(copiedBlob[0] == 99, 'The returned blob was not mutable.');
    _expect(row.getBlob('payload')[0] == 1, 'Blob access mutated the buffered row.');
    await _expectFailure<RangeError>(() async => row.getInt('maximum'));
    await _expectFailure<UnsupportedError>(() async => result.rows.clear());
    _expect(row.valueAt(4) == BigInt.parse('-9223372036854775808'), 'First duplicate changed.');
    _expect(row.valueAt(5) == BigInt.parse('9223372036854775807'), 'Second duplicate changed.');
    await _expectFailure<StateError>(() async => row.value('duplicate'));
  } finally {
    await database.close();
  }
}

Future<void> _verifyPersistentAttachment() async {
  final database = await TursoDatabase.open(
    TursoLocation.browser(_databaseName),
    web: _bridge,
  );
  try {
    await database.execute("ATTACH DATABASE '$_attachedDatabaseName' AS auxiliary");
    _expect(
      (await database.query('SELECT id FROM auxiliary.items')).rows.single.getInt('id') == 1,
      'Persistent browser attachment did not survive reload.',
    );
    await database.query('DETACH DATABASE auxiliary');
  } finally {
    await database.close();
  }

  final released = await TursoDatabase.open(
    TursoLocation.browser(_attachedDatabaseName),
    web: _bridge,
  );
  try {
    _expect(
      (await released.query('SELECT id FROM items')).rows.single.getInt('id') == 1,
      'DETACH did not release the persistent browser attachment.',
    );
  } finally {
    await released.close();
  }
}

Future<void> _verifyPersistentAttachmentFromMemoryMainIsRejected() async {
  final memory = await TursoDatabase.open(TursoLocation.memory(), web: _bridge);
  try {
    await _expectFailure<TursoUnsupportedException>(
      () => memory.execute(
        "ATTACH DATABASE '$_memoryMainAttachmentName' AS persistent",
      ),
    );
  } finally {
    await memory.close();
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

Future<void> _verifyMemoryAttachments() async {
  final persistent = await TursoDatabase.open(
    TursoLocation.browser(_databaseName),
    web: _bridge,
  );
  try {
    _expect(
      (await persistent.query('PRAGMA foreign_keys')).rows.single.getInt('foreign_keys') == 0,
      'Browser open changed the upstream foreign-key default.',
    );
    await persistent.query("ATTACH DATABASE ':memory:' AS auxiliary");
    await persistent.execute('CREATE TABLE auxiliary.items (id INTEGER PRIMARY KEY)');
    await persistent.execute('INSERT INTO auxiliary.items VALUES (1)');
    _expect(
      (await persistent.query('SELECT id FROM auxiliary.items')).rows.single.getInt('id') == 1,
      'Persistent browser main could not read its memory attachment.',
    );
    await persistent.execute('DETACH DATABASE auxiliary');
    await _expectFailure<TursoDatabaseException>(
      () => persistent.query('SELECT * FROM auxiliary.items'),
    );
  } finally {
    await persistent.close();
  }

  final memory = await TursoDatabase.open(TursoLocation.memory(), web: _bridge);
  try {
    await memory.transaction((tx) async {
      await tx.execute("ATTACH DATABASE ':memory:' AS auxiliary");
      await tx.execute('CREATE TABLE auxiliary.parents (id INTEGER PRIMARY KEY)');
      await tx.execute(
        'CREATE TABLE auxiliary.children ( '
        'id INTEGER PRIMARY KEY, '
        'parent_id INTEGER REFERENCES parents(id) DEFERRABLE INITIALLY DEFERRED)',
      );
      _expect(
        (await tx.query('SELECT count(*) AS count FROM auxiliary.parents')).rows.single.getInt(
              'count',
            ) ==
            0,
        'Transaction query did not reach the attached memory schema.',
      );
    });
    await memory.execute('PRAGMA foreign_keys=ON');
    await memory.execute('INSERT INTO auxiliary.parents VALUES (1)');
    await memory.execute('INSERT INTO auxiliary.children VALUES (1, 1)');
    await _expectFailure<TursoDatabaseException>(
      () => memory.transaction<void>((tx) async {
        await tx.execute('INSERT INTO auxiliary.children VALUES (2, 99)');
      }),
    );
    _expect(
      (await memory.query('SELECT count(*) AS count FROM auxiliary.children')).rows.single
              .getInt('count') ==
          1,
      'Deferred attached-schema violation escaped rollback.',
    );
    await memory.execute('PRAGMA foreign_keys=OFF');
    await memory.execute('INSERT INTO auxiliary.children VALUES (3, 99)');
    await memory.execute('DETACH DATABASE auxiliary');
  } finally {
    await memory.close();
  }

  final reopened = await TursoDatabase.open(TursoLocation.memory(), web: _bridge);
  try {
    await _expectFailure<TursoDatabaseException>(
      () => reopened.query('SELECT * FROM auxiliary.children'),
    );
  } finally {
    await reopened.close();
  }
}

Future<void> _verifyRepresentativeWorkload() async {
  final database = await TursoDatabase.open(TursoLocation.memory(), web: _bridge);
  try {
    await database.execute('CREATE TABLE documents (id INTEGER PRIMARY KEY, body TEXT)');
    await database.execute(
      'WITH RECURSIVE sequence(value) AS ( '
      'SELECT 1 UNION ALL SELECT value + 1 FROM sequence WHERE value < 2000) '
      "INSERT INTO documents SELECT value, 'bounded browser row ' || value FROM sequence",
    );
    final rows = await database.query(
      'SELECT id, body FROM documents ORDER BY id DESC LIMIT 25',
    );
    _expect(rows.rows.length == 25, 'The representative bounded query returned the wrong size.');
  } finally {
    await database.close();
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
