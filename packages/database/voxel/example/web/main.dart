import 'dart:typed_data';

import 'package:turso/turso.dart';
import 'package:voxel/src/connection.dart' show VoxelTesting;
import 'package:voxel/src/migration.dart';
import 'package:voxel/src/platform_web.dart' show openVoxelPersistentDatabase;
import 'package:voxel/voxel.dart';
import 'package:voxel_fixture_app/app_database.dart';
import 'package:voxel_fixture_app/fixture_app.voxel_migrations.dart';
import 'package:voxel_fixture_app/posts.dart';
import 'package:voxel_fixture_schema/authors.dart';
import 'package:web/web.dart' as web;

import '../../test/generated_consumer.dart';

Future<void> main() async {
  try {
    await _verifyGeneratedTextStorage();
    await _verifyScalarStorage();
    await _verifyEnumStorage();
    await _verifyVectorStorage();
    await _verifyArrayStorage();
    await _verifyMigrationBundle();
    await _verifyPersistentOpfs();
    web.document.body!.textContent = 'PASS\nVoxel browser OPFS fixture';
  } on Object catch (error, stackTrace) {
    web.document.body!.textContent = 'FAIL\n$error\n$stackTrace';
  }
}

Future<void> _verifyPersistentOpfs() async {
  final defaultDatabase = await FixtureAppDatabase().open();
  await defaultDatabase.close();
  final reopenedDefault = await FixtureAppDatabase().open();
  await reopenedDefault.close();

  const storage = VoxelStorage.opfs(directory: 'voxel-fixtures/fbr-205/runtime-v1');
  var database = await FixtureAppDatabase().open(storage: storage);
  await VoxelTesting.execute(
    database,
    "INSERT OR IGNORE INTO content.authors VALUES ('browser-author', 'Browser Ada')",
  );
  _expect(
    await VoxelTesting.scalarInt(
          database,
          'SELECT COUNT(*) AS value FROM content._voxel_phases',
        ) ==
        3,
    'browser attachment migration receipts missing',
  );

  var competingOpenFailed = false;
  try {
    final competing = await FixtureAppDatabase().open(
      storage: storage,
      migrations: const VoxelMigrationOptions(lockTimeout: Duration.zero),
    );
    await competing.close();
  } on Object {
    competingOpenFailed = true;
  }
  _expect(competingOpenFailed, 'competing OPFS owner unexpectedly opened the database');
  await database.close();

  database = await FixtureAppDatabase().open(storage: storage);
  _expect(
    await VoxelTesting.scalarInt(
          database,
          "SELECT COUNT(*) AS value FROM content.authors WHERE id = 'browser-author'",
        ) ==
        1,
    'browser attachment data did not survive reopen',
  );
  _expect(
    await VoxelTesting.scalarText(
          database,
          "SELECT state AS value FROM main._voxel_files WHERE schema_id != 'main'",
        ) ==
        'initialized',
    'browser attachment registry was not initialized',
  );
  await database.close();

  await _verifyEncryptedOpfs();
  await _verifyInterruptedOpfsMigrations();
}

Future<void> _verifyInterruptedOpfsMigrations() async {
  final plan = VoxelMigrationPlan.validate(
    schema: FixtureAppDatabaseVoxelSchema.build(),
    bundle: FixtureAppDatabaseVoxelMigrations.bundle,
  );
  for (final point in [
    VoxelMigrationInterruptionPoint.afterCreationPrepared,
    VoxelMigrationInterruptionPoint.afterFileBootstrap,
    VoxelMigrationInterruptionPoint.afterRegistryInitialized,
    VoxelMigrationInterruptionPoint.afterPhaseCommit,
    VoxelMigrationInterruptionPoint.beforeMainSummary,
    VoxelMigrationInterruptionPoint.afterMainSummary,
  ]) {
    var interrupted = false;
    final directory = 'voxel-fixtures/fbr-205/interrupt-${point.name}-v1';
    try {
      final unexpectedlyOpened = await _openPersistentPlan(
        plan,
        directory,
        interrupt: (event) async {
          if (!interrupted && event.point == point) {
            interrupted = true;
            throw _SimulatedReload(point);
          }
        },
      );
      await unexpectedlyOpened.close();
      throw StateError('migration did not stop at ${point.name}');
    } on _SimulatedReload catch (error) {
      _expect(
        error.point == point,
        'unexpected interruption failure at ${point.name}: $error',
      );
    }

    final recovered = await _openPersistentPlan(plan, directory);
    _expect(
      (await recovered.query(
            'SELECT COUNT(*) AS value FROM content._voxel_phases',
          )).rows.single.getInt('value') ==
          3,
      'browser migration did not recover after ${point.name}',
    );
    await recovered.close();
  }
}

Future<TursoDatabase> _openPersistentPlan(
  VoxelMigrationPlan plan,
  String directory, {
  Future<void> Function(VoxelMigrationInterruption interruption)? interrupt,
}) => openVoxelPersistentDatabase(
  databaseName: 'fixture_app',
  directory: directory,
  migrations: plan,
  lockTimeout: const Duration(seconds: 30),
  encryptionCipher: null,
  encryptionKey: null,
  schemaDirectories: const {},
  schemaEncryptionCiphers: const {},
  schemaEncryptionKeys: const {},
  interrupt: interrupt,
);

Future<void> _verifyEncryptedOpfs() async {
  const storage = VoxelStorage.opfs(directory: 'voxel-fixtures/fbr-205/encrypted-v1');
  final mainKey = Uint8List.fromList(List<int>.generate(32, (index) => index + 1));
  final contentKey = Uint8List.fromList(List<int>.generate(32, (index) => index + 33));
  final encryption = VoxelEncryption(cipher: VoxelCipher.aes256gcm, key: mainKey);
  final contentEncryption = VoxelEncryption(
    cipher: VoxelCipher.aegis256,
    key: contentKey,
  );
  var database = await FixtureAppDatabase().open(
    storage: storage,
    encryption: encryption,
    schemaEncryption: {'content': contentEncryption},
  );
  await database.close();

  final wrongKey = Uint8List.fromList(contentKey)..[0] ^= 0xff;
  var wrongKeyFailure = '';
  try {
    final incorrectlyOpened = await FixtureAppDatabase().open(
      storage: storage,
      encryption: encryption,
      schemaEncryption: {
        'content': VoxelEncryption(cipher: VoxelCipher.aegis256, key: wrongKey),
      },
    );
    await incorrectlyOpened.close();
  } on Object catch (error) {
    wrongKeyFailure = error.toString();
  }
  _expect(wrongKeyFailure.isNotEmpty, 'wrong attachment encryption key was accepted');
  _expect(
    !wrongKeyFailure.contains(_hex(wrongKey)),
    'attachment encryption key leaked in an error',
  );

  database = await FixtureAppDatabase().open(
    storage: storage,
    encryption: encryption,
    schemaEncryption: {'content': contentEncryption},
  );
  await database.close();
}

String _hex(Uint8List bytes) => bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

final class _SimulatedReload implements Exception {
  const _SimulatedReload(this.point);

  final VoxelMigrationInterruptionPoint point;

  @override
  String toString() => 'simulated ${point.name} reload';
}

Future<void> _verifyMigrationBundle() async {
  final database = await FixtureAppDatabase().open(
    storage: const VoxelStorage.memory(),
  );
  await database.close();
}

Future<void> _verifyArrayStorage() async {
  final schema = ArrayValues.db.buildSchema();
  final table = schema.definition;
  final database = await TursoDatabase.open(
    TursoLocation.memory(),
    web: TursoWebOptions(moduleUri: Uri.parse('turso/turso_bridge.js')),
  );
  try {
    await database.execute(
      'CREATE TABLE arrayValues (${schema.columns.map((column) => '"${column.physicalName}" TEXT').join(', ')})',
    );
    final parameters = <Object?>[
      table.texts.codec.encode([]),
      table.chronoIDs.codec.encode(['arr_000000000000000000000000']),
      table.nullableElements.codec.encode([null, 'value']),
      table.nullableArray.codec.encode(['present']),
      table.nullableElementsAndArray.codec.encode(null),
      table.integers.codec.encode([-2147483648, 2147483647]),
      table.reals.codec.encode([1.5]),
      table.booleans.codec.encode([true, false]),
      table.timestamps.codec.encode([DateTime.fromMicrosecondsSinceEpoch(-1)]),
      table.jsonValues.codec.encode([
        const JsonNull(),
        JsonValue.from(const [1, null]),
      ]),
      table.nullableJsonValues.codec.encode([null, const JsonNull()]),
      table.statuses.codec.encode([PostStatus.draft, PostStatus.published]),
      table.vectors.codec.encode([
        Float32List.fromList([0.5, -2, 3.25]),
      ]),
      table.codes.codec.encode([const UserCode('ada')]),
      table.nullableCodes.codec.encode([null, const UserCode('grace')]),
      table.counts.codec.encode([const CountValue(7)]),
      table.preferencesList.codec.encode([const Preferences(darkMode: true)]),
    ];
    await database.execute(
      'INSERT INTO arrayValues VALUES (${List.filled(parameters.length, '?').join(', ')})',
      parameters: parameters,
    );
    final stored = (await database.query('SELECT * FROM arrayValues')).rows.single;
    final values = [for (final column in schema.columns) stored.value(column.physicalName)];
    final row = schema.decode(values, [for (final value in values) value == null]);
    _expect(
      row.texts.isEmpty &&
          row.chronoIDs.single == 'arr_000000000000000000000000' &&
          row.nullableElements[0] == null &&
          row.nullableArray!.single == 'present' &&
          row.nullableElementsAndArray == null &&
          row.integers.last == 2147483647 &&
          row.booleans.first &&
          row.timestamps.single.microsecondsSinceEpoch == -1000 &&
          row.jsonValues.first == const JsonNull() &&
          row.nullableJsonValues[1] == const JsonNull() &&
          row.statuses.last == PostStatus.published &&
          _listEquals(row.vectors.single, Float32List.fromList([0.5, -2, 3.25])) &&
          row.codes.single.value == 'ada' &&
          row.nullableCodes.first == null &&
          row.counts.single.value == 7 &&
          row.preferencesList.single.darkMode,
      'array row mismatch',
    );
    for (final column in schema.columns) {
      _expectFailure(() => column.decodeValue('{}', isSqlNull: false));
    }
    _expectFailure(() => table.chronoIDs.decodeValue('["invalid"]', isSqlNull: false));
    _expectFailure(() => table.integers.decodeValue('[2147483648]', isSqlNull: false));
    _expectFailure(() => table.reals.decodeValue('["invalid"]', isSqlNull: false));
    _expectFailure(() => table.booleans.decodeValue('[2]', isSqlNull: false));
    _expectFailure(() => table.timestamps.decodeValue('["invalid"]', isSqlNull: false));
    _expectFailure(() => table.jsonValues.decodeValue('[null]', isSqlNull: false));
    _expectFailure(() => table.statuses.decodeValue('["unknown"]', isSqlNull: false));
    _expectFailure(() => table.vectors.decodeValue('[[1,2]]', isSqlNull: false));
    _expectFailure(() => table.codes.decodeValue('["secret"]', isSqlNull: false));
    _expectFailure(() => table.preferencesList.decodeValue('[[{}]]', isSqlNull: false));
  } finally {
    await database.close();
  }
}

Future<void> _verifyVectorStorage() async {
  final schema = VectorValues.db.buildSchema();
  final table = schema.definition;
  final database = await TursoDatabase.open(
    TursoLocation.memory(),
    web: TursoWebOptions(moduleUri: Uri.parse('turso/turso_bridge.js')),
  );
  try {
    _expect(database.capabilities.vectorFunctions, 'vector functions unavailable');
    await database.execute(
      'CREATE TABLE vectorValues (embedding F32_BLOB(3), optionalEmbedding F32_BLOB(3))',
    );
    final value = Float32List.fromList([0.1, -2.5, 3.25]);
    await database.execute(
      'INSERT INTO vectorValues VALUES (vector32(?), NULL)',
      parameters: [table.embedding.codec.encode(value)],
    );
    final stored = (await database.query(
      'SELECT ${table.embedding.selectionSql} AS embedding, '
      '${table.optionalEmbedding.selectionSql} AS optionalEmbedding FROM vectorValues',
    )).rows.single;
    final row = schema.decode(
      [stored.value('embedding'), stored.value('optionalEmbedding')],
      [false, true],
    );
    _expect(
      _listEquals(row.embedding, value) && row.optionalEmbedding == null,
      'vector row mismatch',
    );
    _expectFailure(() => table.embedding.codec.encode(Float32List(2)));
    _expectFailure(
      () => table.embedding.codec.encode(Float32List.fromList([1, double.nan, 3])),
    );
    _expectFailure(() => table.embedding.decodeValue('[1,2]', isSqlNull: false));
    _expectFailure(() => table.embedding.decodeValue('[1,NaN,3]', isSqlNull: false));
  } finally {
    await database.close();
  }
}

bool _listEquals<T>(List<T> left, List<T> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

Future<void> _verifyEnumStorage() async {
  final status = Posts.db.buildSchema().definition.status;
  final database = await TursoDatabase.open(
    TursoLocation.memory(),
    web: TursoWebOptions(moduleUri: Uri.parse('turso/turso_bridge.js')),
  );
  try {
    await database.execute('CREATE TABLE enumValues (status TEXT)');
    await database.execute(
      'INSERT INTO enumValues VALUES (?), (?)',
      parameters: [
        status.codec.encode(PostStatus.draft),
        status.codec.encode(PostStatus.published),
      ],
    );
    final rows = (await database.query('SELECT status FROM enumValues ORDER BY rowid')).rows;
    _expect(
      status.codec.decode(rows[0].value('status'), isSqlNull: false) == PostStatus.draft &&
          status.codec.decode(rows[1].value('status'), isSqlNull: false) == PostStatus.published,
      'enum row mismatch',
    );
    _expectFailure(() => status.codec.decode('unknown', isSqlNull: false));
  } finally {
    await database.close();
  }
}

Future<void> _verifyScalarStorage() async {
  final schema = ScalarValues.db.buildSchema();
  final table = schema.definition;
  final database = await TursoDatabase.open(
    TursoLocation.memory(),
    web: TursoWebOptions(moduleUri: Uri.parse('turso/turso_bridge.js')),
  );
  try {
    await database.execute(
      'CREATE TABLE scalarValues (count INTEGER, score REAL, active INTEGER, '
      'createdAt INTEGER, payload TEXT, optionalPayload TEXT, code TEXT, '
      'optionalCode TEXT, preferences TEXT)',
    );
    await database.execute(
      'INSERT INTO scalarValues VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
      parameters: [
        table.count.codec.encode(2147483647),
        table.score.codec.encode(2.5),
        table.active.codec.encode(true),
        table.createdAt.codec.encode(DateTime.fromMicrosecondsSinceEpoch(-1)),
        table.payload.codec.encode(const JsonNull()),
        table.optionalPayload.codec.encode(
          JsonValue.from(const {
            'items': [true, 1, null],
          }),
        ),
        table.code.codec.encode(const UserCode('ada')),
        null,
        table.preferences.codec.encode(const Preferences(darkMode: true)),
      ],
    );
    final stored = (await database.query('SELECT * FROM scalarValues')).rows.single;
    final values = [for (final column in schema.columns) stored.value(column.physicalName)];
    final row = schema.decode(values, [for (final value in values) value == null]);
    _expect(
      row.count == 2147483647 &&
          row.score == 2.5 &&
          row.active &&
          row.createdAt.microsecondsSinceEpoch == -1000 &&
          row.payload == const JsonNull() &&
          row.optionalCode == null &&
          row.preferences.darkMode,
      'scalar row mismatch',
    );
    _expectFailure(() => table.count.codec.encode(2147483648));
    _expectFailure(() => table.active.codec.decode(BigInt.two, isSqlNull: false));
    _expectFailure(() => table.payload.codec.decode('{', isSqlNull: false));
  } finally {
    await database.close();
  }
}

Future<void> _verifyGeneratedTextStorage() async {
  final schema = Users.db.buildSchema();
  final table = schema.definition;
  final database = await TursoDatabase.open(
    TursoLocation.memory(),
    web: TursoWebOptions(moduleUri: Uri.parse('turso/turso_bridge.js')),
  );
  try {
    await database.execute(
      'CREATE TABLE users (id TEXT NOT NULL, displayName TEXT NOT NULL, nickname TEXT)',
    );
    final id = table.id.defaultFn!()! as String;
    await database.execute(
      'INSERT INTO users VALUES (?, ?, ?)',
      parameters: [table.id.codec.encode(id), table.displayName.codec.encode('Ada'), null],
    );
    final stored = (await database.query(
      'SELECT id, displayName, nickname FROM users',
    )).rows.single;
    final row = schema.decode(
      [stored.value('id'), stored.value('displayName'), stored.value('nickname')],
      [false, false, true],
    );
    _expect(row.id == id && row.displayName == 'Ada' && row.nickname == null, 'row mismatch');
    _expectFailure(
      () => schema.decode([stored.value('id'), BigInt.one, null], [false, false, true]),
    );
  } finally {
    await database.close();
  }
}

void _expect(bool condition, String message) {
  if (!condition) throw StateError(message);
}

void _expectFailure(void Function() operation) {
  try {
    operation();
  } on Object catch (error) {
    if (error is FormatException || error is RangeError || error is VoxelConversionException) {
      return;
    }
    rethrow;
  }
  throw StateError('Expected malformed stored text to fail.');
}
