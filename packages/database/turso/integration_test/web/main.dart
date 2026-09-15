import 'dart:async';
import 'dart:typed_data';

import 'package:turso/turso.dart';
import 'package:web/web.dart' as web;

import '../support/sql_contract.dart';

const _phaseKey = 'turso-dart-web-verification-phase';
const _databaseName = 'turso-dart-web-verification.db';
const _attachedDatabaseName = 'turso-dart-web-attached.db';
const _boundAttachmentName = 'turso-dart-web-bound-attached.db';
const _encryptedAttachmentName = 'turso-dart-web-encrypted-attached.db';
const _memoryMainAttachmentName = 'turso-dart-web-memory-main-attached.db';
const _uriAttachmentName = 'turso-dart-web-uri attached.db';
const _ownershipMainName = 'turso-dart-web-ownership-main.db';
const _sharedAttachmentName = 'turso-dart-web-shared-attached.db';
const _failedAttachmentName = 'turso-dart-web-failed-attached.db';
const _contentionMainName = 'turso-dart-web-contention-main.db';
const _uncertainMainName = 'turso-dart-web-uncertain-main.db';
const _uncertainAttachmentName = 'turso-dart-web-uncertain-attached.db';
const _nestedMainName = 'turso-dart/nested/main.db';
const _nestedAttachmentName = 'turso-dart/nested/attached.db';
final _bridge = TursoWebOptions(moduleUri: Uri.parse('turso/turso_bridge.js'));

Future<void> main() async {
  var stage = 'initial persistence';
  try {
    if (web.window.localStorage.getItem(_phaseKey) == null) {
      stage = 'write persistent data';
      await _writePersistentData();
      stage = 'write persistent attachment';
      await _writePersistentAttachment();
      stage = 'write encrypted data';
      await _writeEncryptedData();
      web.window.localStorage.setItem(_phaseKey, 'reload');
      web.window.location.reload();
      return;
    }

    for (final verification in <(String, Future<void> Function())>[
      ('reloaded data', _verifyReloadedData),
      ('persistent attachment', _verifyPersistentAttachment),
      ('nested OPFS paths', _verifyNestedOpfsPaths),
      ('bound attachments', _verifyBoundPersistentAttachments),
      ('encrypted attachment', _verifyEncryptedPersistentAttachment),
      ('attachment ownership failures', _verifyAttachmentOwnershipFailures),
      ('attachment contention', _verifyAttachmentContention),
      ('attachment boundary failures', _verifyAttachmentBoundaryFailures),
      ('memory-main rejection', _verifyPersistentAttachmentFromMemoryMainIsRejected),
      ('encrypted main', _verifyEncryptedData),
      (
        'transactions',
        () async =>
            verifyTransactions(await TursoDatabase.open(TursoLocation.memory(), web: _bridge)),
      ),
      ('worker death', _verifyWorkerDeath),
      ('close failure', _verifyCloseFailure),
      ('lock release', _verifyLockRelease),
      ('memory database', _verifyMemoryDatabase),
      ('memory attachments', _verifyMemoryAttachments),
      ('representative workload', _verifyRepresentativeWorkload),
      ('platform failures', _verifyPlatformFailures),
    ]) {
      stage = verification.$1;
      web.document.body!.textContent = 'RUN\n$stage';
      await verification.$2();
    }
    web.window.localStorage.removeItem(_phaseKey);
    web.document.body!.textContent = 'PASS\n${web.window.navigator.userAgent}';
  } on Object catch (error, stackTrace) {
    web.document.body!.textContent = 'FAIL\n$stage\n$error\n$stackTrace';
  }
}

Future<void> _verifyNestedOpfsPaths() async {
  final mainLocation = TursoLocation.browser(_nestedMainName) as TursoBrowserLocation;
  final attachmentLocation = TursoLocation.browser(_nestedAttachmentName) as TursoBrowserLocation;
  final database = await TursoDatabase.open(mainLocation, web: _bridge);
  try {
    await database.execute('CREATE TABLE IF NOT EXISTS values_table (value TEXT)');
    await database.execute('DELETE FROM values_table');
    await database.execute("INSERT INTO values_table VALUES ('nested main')");
    await database.execute(
      'ATTACH DATABASE ? AS nested_attachment',
      parameters: [attachmentLocation.path],
    );
    await database.execute(
      'CREATE TABLE IF NOT EXISTS nested_attachment.values_table (value TEXT)',
    );
    await database.execute('DELETE FROM nested_attachment.values_table');
    await database.execute(
      "INSERT INTO nested_attachment.values_table VALUES ('nested attachment')",
    );
  } finally {
    await database.close();
  }

  _expect(
    await TursoDatabase.browserFileExists(mainLocation, web: _bridge),
    'Nested main file was not found after close.',
  );
  _expect(
    await TursoDatabase.browserFileExists(attachmentLocation, web: _bridge),
    'Nested attachment file was not found after close.',
  );

  final reopened = await TursoDatabase.open(mainLocation, web: _bridge);
  try {
    await reopened.execute(
      'ATTACH DATABASE ? AS nested_attachment',
      parameters: [attachmentLocation.path],
    );
    _expect(
      (await reopened.query('SELECT value FROM values_table')).rows.single.getString('value') ==
          'nested main',
      'Nested main data did not persist.',
    );
    _expect(
      (await reopened.query('SELECT value FROM nested_attachment.values_table')).rows.single
              .getString('value') ==
          'nested attachment',
      'Nested attachment data did not persist.',
    );
  } finally {
    await reopened.close();
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
    await verifyValues(database);
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

    await database.execute('PRAGMA foreign_keys=ON');
    await database.execute(
      'CREATE TABLE IF NOT EXISTS auxiliary.parents (id INTEGER PRIMARY KEY)',
    );
    await database.execute(
      'CREATE TABLE IF NOT EXISTS auxiliary.children ( '
      'id INTEGER PRIMARY KEY, '
      'parent_id INTEGER REFERENCES parents(id) DEFERRABLE INITIALLY DEFERRED)',
    );
    await database.execute('DELETE FROM auxiliary.children');
    await database.execute('DELETE FROM auxiliary.parents');
    await database.execute('INSERT INTO auxiliary.parents VALUES (1)');
    await database.execute('INSERT INTO auxiliary.children VALUES (1, 1)');
    await _expectFailure<TursoDatabaseException>(
      () => database.transaction<void>((tx) async {
        await tx.execute('INSERT INTO auxiliary.children VALUES (2, 99)');
      }),
    );
    _expect(
      (await database.query('SELECT count(*) AS count FROM auxiliary.children')).rows.single
              .getInt('count') ==
          1,
      'Persistent attachment deferred violation escaped rollback.',
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
      () => database.execute("ATTACH DATABASE '../invalid.db' AS invalid_path"),
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

Future<void> _verifyBoundPersistentAttachments() async {
  final database = await TursoDatabase.open(
    TursoLocation.browser(_databaseName),
    web: _bridge,
  );
  try {
    final positional = <Object?>[_boundAttachmentName, 'positional_auxiliary'];
    final attach = database.execute('ATTACH DATABASE ? AS ?', parameters: positional);
    positional
      ..[0] = 'mutated.db'
      ..[1] = 'mutated';
    await attach;
    await database.execute(
      'CREATE TABLE IF NOT EXISTS positional_auxiliary.items (id INTEGER PRIMARY KEY)',
    );
    await database.execute('DELETE FROM positional_auxiliary.items');
    await database.execute('INSERT INTO positional_auxiliary.items VALUES (3)');
    await database.query('DETACH DATABASE ?', parameters: const ['positional_auxiliary']);

    final named = <String, Object?>{
      ':file': _boundAttachmentName,
      ':alias': 'named_auxiliary',
    };
    final namedAttach = database.query(
      'ATTACH DATABASE :file AS :alias KEY :alias',
      namedParameters: named,
    );
    named
      ..[':file'] = 'mutated.db'
      ..[':alias'] = 'mutated';
    await namedAttach;
    _expect(
      (await database.query('SELECT id FROM named_auxiliary.items')).rows.single.getInt('id') == 3,
      'Named attachment arguments or their submission snapshot changed.',
    );
    await database.execute(
      'DETACH DATABASE :alias',
      namedParameters: const {':alias': 'named_auxiliary'},
    );

    await database.execute(
      'ATTACH DATABASE ? AS ?',
      parameters: const [_boundAttachmentName, 'MiXeD_Auxiliary'],
    );
    await database.execute(
      'DETACH DATABASE ?',
      parameters: const ['MiXeD_Auxiliary'],
    );
    await database.execute(
      'ATTACH DATABASE ? AS mixed_reopened',
      parameters: const [_boundAttachmentName],
    );
    _expect(
      (await database.query('SELECT id FROM mixed_reopened.items')).rows.single.getInt('id') == 3,
      'A bound mixed-case alias did not detach with its supplied spelling.',
    );
    await database.execute('DETACH DATABASE mixed_reopened');

    await database.transaction((tx) async {
      await tx.execute(
        'ATTACH DATABASE ?2 AS ?3 KEY ?1',
        parameters: const ['unused', _boundAttachmentName, 'slot_auxiliary'],
      );
      _expect(
        (await tx.query('SELECT id FROM slot_auxiliary.items')).rows.single.getInt('id') == 3,
        'Numbered attachment slots did not retain parser ordering.',
      );
    });
    await database.execute('DETACH DATABASE slot_auxiliary');

    await _expectFailure<ArgumentError>(
      () => database.execute(
        'ATTACH DATABASE :file AS :alias',
        namedParameters: const {':file': 'missing-alias.db'},
      ),
    );
    await _expectFailure<ArgumentError>(
      () => database.execute(
        'ATTACH DATABASE ? AS ?',
        parameters: const [1, 'non_string'],
      ),
    );
  } finally {
    await database.close();
  }
}

Future<void> _verifyEncryptedPersistentAttachment() async {
  final database = await TursoDatabase.open(
    TursoLocation.browser(_databaseName),
    web: _bridge,
  );
  final hexkey = _hexKey(_encryptionKey());
  final uri = 'file:$_encryptedAttachmentName?mode=rwc&cipher=aegis256&hexkey=$hexkey';
  try {
    await database.execute(
      'ATTACH DATABASE ? AS ?',
      parameters: [uri, 'encrypted_auxiliary'],
    );
    await database.execute(
      'CREATE TABLE IF NOT EXISTS encrypted_auxiliary.secrets (value TEXT)',
    );
    await database.execute('DELETE FROM encrypted_auxiliary.secrets');
    await database.execute("INSERT INTO encrypted_auxiliary.secrets VALUES ('attached secret')");
    await database.execute('DETACH DATABASE encrypted_auxiliary');

    final wrongHexkey = '${hexkey.substring(0, 62)}ff';
    final wrongUri = 'file:$_encryptedAttachmentName?cipher=aegis256&hexkey=$wrongHexkey&mode=rwc';
    final wrongKeyFailure = await _captureFailure(
      () => database.execute('ATTACH DATABASE ? AS wrong_key', parameters: [wrongUri]),
    );
    _expect(wrongKeyFailure is TursoDatabaseException, 'Wrong attachment key had the wrong error.');
    _expect(
      !wrongKeyFailure.toString().contains(wrongHexkey) &&
          !wrongKeyFailure.toString().contains(wrongUri),
      'Attachment diagnostics exposed a key-bearing URI.',
    );
    await _expectFailure<TursoDatabaseException>(
      () => database.execute(
        "ATTACH DATABASE '$_encryptedAttachmentName' AS missing_key",
      ),
    );

    await database.query("ATTACH DATABASE '$uri' AS encrypted_auxiliary");
    _expect(
      (await database.query('SELECT value FROM encrypted_auxiliary.secrets')).rows.single
              .getString('value') ==
          'attached secret',
      'Encrypted browser attachment could not be reopened with its key.',
    );
    await database.execute('DETACH DATABASE encrypted_auxiliary');

    await database.execute(
      "ATTACH DATABASE 'file:${Uri.encodeComponent(_uriAttachmentName)}?mode=rwc' "
      'AS uri_auxiliary',
    );
    await database.execute('CREATE TABLE IF NOT EXISTS uri_auxiliary.items (id INTEGER)');
    await database.execute('DELETE FROM uri_auxiliary.items');
    await database.execute('INSERT INTO uri_auxiliary.items VALUES (4)');
    await database.execute('DETACH DATABASE uri_auxiliary');

    await _expectFailure<TursoUnsupportedException>(
      () => database.execute("ATTACH DATABASE 'file:readonly.db?mode=ro' AS readonly"),
    );
    await _expectFailure<TursoUnsupportedException>(
      () => database.execute("ATTACH DATABASE 'file:..%2Fpath.db' AS escaping"),
    );
    await _expectFailure<TursoUnsupportedException>(
      () => database.execute("ATTACH DATABASE 'file://localhost/absolute.db' AS absolute"),
    );
    await _expectFailure<ArgumentError>(
      () => database.execute(
        "ATTACH DATABASE 'file:unpaired.db?cipher=aegis256' AS unpaired",
      ),
    );
  } finally {
    await database.close();
  }

  final decoded = await TursoDatabase.open(
    TursoLocation.browser(_uriAttachmentName),
    web: _bridge,
  );
  try {
    _expect(
      (await decoded.query('SELECT id FROM items')).rows.single.getInt('id') == 4,
      'File URI registration did not use the decoded OPFS filename.',
    );
  } finally {
    await decoded.close();
  }
}

String _hexKey(Uint8List key) => key.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

Future<void> _verifyAttachmentOwnershipFailures() async {
  final database = await TursoDatabase.open(
    TursoLocation.browser(_ownershipMainName),
    web: _bridge,
  );
  try {
    await database.execute('CREATE TABLE IF NOT EXISTS main_items (value INTEGER)');
    await database.execute('DELETE FROM main_items');
    await database.execute('INSERT INTO main_items VALUES (5)');
    await database.execute("ATTACH DATABASE '$_sharedAttachmentName' AS first_owner");
    await database.execute('CREATE TABLE IF NOT EXISTS first_owner.items (value INTEGER)');
    await database.execute('DELETE FROM first_owner.items');
    await database.execute('INSERT INTO first_owner.items VALUES (7)');
    await database.execute("ATTACH DATABASE '$_sharedAttachmentName' AS second_owner");

    for (final filename in ['$_ownershipMainName-wal', '$_sharedAttachmentName-wal']) {
      await _expectFailure<TursoDatabaseException>(
        () => database.execute('ATTACH DATABASE ? AS wal_collision', parameters: [filename]),
      );
    }
    await database.execute('INSERT INTO main_items VALUES (6)');
    await database.execute('DELETE FROM main_items WHERE value = 6');
    await database.execute('INSERT INTO first_owner.items VALUES (8)');
    await database.execute('DELETE FROM first_owner.items WHERE value = 8');

    final duplicateAlias = await _captureFailure(
      () => database.execute("ATTACH DATABASE '$_failedAttachmentName' AS first_owner"),
      label: 'duplicate alias',
    );
    _expect(
      duplicateAlias is TursoDatabaseException,
      'Duplicate alias returned ${duplicateAlias.runtimeType}: $duplicateAlias',
    );
    final reservedAlias = await _captureFailure(
      () => database.execute("ATTACH DATABASE 'reserved-main.db' AS main"),
      label: 'reserved alias',
    );
    _expect(
      reservedAlias is TursoDatabaseException,
      'Reserved alias returned ${reservedAlias.runtimeType}: $reservedAlias',
    );
    await database.execute("ATTACH DATABASE '$_ownershipMainName' AS main_copy");
    _expect(
      (await database.query('SELECT value FROM main_copy.main_items')).rows.single
              .getInt('value') ==
          5,
      'Attaching the main filename registered or redirected another file.',
    );
    await database.execute('DETACH DATABASE main_copy');

    final failedDetach = await _captureFailure(
      () => database.execute('DETACH DATABASE missing_owner'),
      label: 'missing-schema DETACH',
    );
    _expect(
      failedDetach is TursoDatabaseException,
      'Failed DETACH returned ${failedDetach.runtimeType}: $failedDetach',
    );
    _expect(
      (await database.query('SELECT value FROM first_owner.items')).rows.single.getInt('value') ==
          7,
      'A failed DETACH lost the attached schema.',
    );

    await database.execute('DETACH DATABASE first_owner');
    _expect(
      (await database.query('SELECT value FROM second_owner.items')).rows.single.getInt('value') ==
          7,
      'DETACH released a file still owned by another alias.',
    );
    await database.execute('DETACH DATABASE second_owner');
  } finally {
    await database.close();
  }

  final failed = await TursoDatabase.open(
    TursoLocation.browser(_failedAttachmentName),
    web: _bridge,
  );
  try {
    await failed.execute('CREATE TABLE IF NOT EXISTS preserved (value INTEGER)');
  } finally {
    await failed.close();
  }

  final shared = await TursoDatabase.open(
    TursoLocation.browser(_sharedAttachmentName),
    web: _bridge,
  );
  try {
    _expect(
      (await shared.query('SELECT value FROM items')).rows.single.getInt('value') == 7,
      'The last DETACH did not preserve or release the shared attachment.',
    );
  } finally {
    await shared.close();
  }

  final draining = await TursoDatabase.open(
    TursoLocation.browser(_ownershipMainName),
    web: _bridge,
  );
  try {
    await draining.execute("ATTACH DATABASE '$_sharedAttachmentName' AS close_owner");
    final accepted = draining.execute('INSERT INTO close_owner.items VALUES (9)');
    final closed = draining.close();
    await accepted;
    await closed;
  } finally {
    await draining.close();
  }

  final afterClose = await TursoDatabase.open(
    TursoLocation.browser(_sharedAttachmentName),
    web: _bridge,
  );
  try {
    _expect(
      (await afterClose.query('SELECT max(value) AS value FROM items')).rows.single
              .getInt('value') ==
          9,
      'Close did not drain accepted attachment work before releasing files.',
    );
  } finally {
    await afterClose.close();
  }
}

Future<void> _verifyAttachmentContention() async {
  final owner = await TursoDatabase.open(
    TursoLocation.browser(_sharedAttachmentName),
    web: _bridge,
  );
  final contender = await TursoDatabase.open(
    TursoLocation.browser(_contentionMainName),
    web: _bridge,
  );
  try {
    await _expectFailure<TursoDatabaseException>(
      () => contender.execute("ATTACH DATABASE '$_sharedAttachmentName' AS locked"),
    );
    await owner.execute('INSERT INTO items VALUES (10)');
    _expect(
      (await owner.query('SELECT max(value) AS value FROM items')).rows.single.getInt('value') ==
          10,
      'A competing worker disturbed the original OPFS owner.',
    );
  } finally {
    await contender.close();
    await owner.close();
  }

  final reopened = await TursoDatabase.open(
    TursoLocation.browser(_contentionMainName),
    web: _bridge,
  );
  try {
    await reopened.execute("ATTACH DATABASE '$_sharedAttachmentName' AS released");
    await reopened.execute('DETACH DATABASE released');
  } finally {
    await reopened.close();
  }
}

Future<void> _verifyAttachmentBoundaryFailures() async {
  final preserved = await TursoDatabase.open(
    TursoLocation.browser(_failedAttachmentName),
    web: _bridge,
  );
  try {
    await preserved.execute('DELETE FROM preserved');
    await preserved.execute('INSERT INTO preserved VALUES (11)');
  } finally {
    await preserved.close();
  }

  final registrationFailure = await TursoDatabase.open(
    TursoLocation.browser(_contentionMainName),
    web: _faultBridge('attachment-wal-registration'),
  );
  try {
    await _expectFailure<TursoDatabaseException>(
      () => registrationFailure.execute("ATTACH DATABASE '$_failedAttachmentName' AS failed"),
    );
  } finally {
    await registrationFailure.close();
  }

  final afterFailure = await TursoDatabase.open(
    TursoLocation.browser(_failedAttachmentName),
    web: _bridge,
  );
  try {
    _expect(
      (await afterFailure.query('SELECT value FROM preserved')).rows.single.getInt('value') == 11,
      'Registration failure deleted or changed the existing attachment file.',
    );
  } finally {
    await afterFailure.close();
  }

  final uncertain = await TursoDatabase.open(
    TursoLocation.browser(_uncertainMainName),
    web: _faultBridge('attach-finalization'),
  );
  try {
    final interrupted = _expectFailure<TursoPlatformException>(
      () => uncertain.execute("ATTACH DATABASE '$_uncertainAttachmentName' AS uncertain"),
    );
    final queued = _expectFailure<TursoPlatformException>(() => uncertain.query('SELECT 1'));
    await Future.wait([interrupted, queued]);
    await _expectFailure<TursoPlatformException>(() => uncertain.query('SELECT 2'));
  } finally {
    await uncertain.close();
  }

  final recovered = await TursoDatabase.open(
    TursoLocation.browser(_uncertainMainName),
    web: _bridge,
  );
  try {
    await recovered.execute("ATTACH DATABASE '$_uncertainAttachmentName' AS recovered");
    await recovered.execute('CREATE TABLE IF NOT EXISTS recovered.items (value INTEGER)');
    await recovered.execute('DETACH DATABASE recovered');
  } finally {
    await recovered.close();
  }

  final rollbackFailure = await TursoDatabase.open(
    TursoLocation.browser(_uncertainMainName),
    web: _bridge,
  );
  try {
    await rollbackFailure.execute(
      "ATTACH DATABASE '$_uncertainAttachmentName' AS rollback_owner",
    );
    final transactionFailure = await _captureFailure(
      () => rollbackFailure.transaction(
        (tx) => tx.execute('DETACH DATABASE missing_rollback_owner'),
      ),
      label: 'transaction rollback failure',
    );
    _expect(
      transactionFailure is TursoTransactionException &&
          transactionFailure.primaryError is TursoDatabaseException &&
          transactionFailure.rollbackError is TursoDatabaseException,
      'Rollback failure did not preserve both database errors: $transactionFailure',
    );
    await _expectFailure<TursoPlatformException>(() => rollbackFailure.query('SELECT 1'));
  } finally {
    await rollbackFailure.close();
  }
}

TursoWebOptions _faultBridge(String fault) => TursoWebOptions(
  moduleUri: Uri.parse('fault_bridge.js?__turso_test_fault=$fault'),
);

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
  } on Object catch (error) {
    throw StateError('Expected $T, got ${error.runtimeType}: $error');
  }
  throw StateError('Expected $T, but the operation succeeded.');
}

Future<Object> _captureFailure(
  Future<Object?> Function() action, {
  String label = 'operation',
}) async {
  try {
    await action();
  } on Object catch (error) {
    return error;
  }
  throw StateError('Expected $label to fail.');
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
