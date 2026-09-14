import 'dart:convert';
import 'dart:typed_data';

import 'package:turso/turso.dart';
import 'package:voxel/voxel.dart';
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
    web.document.body!.textContent = 'PASS\nVoxel browser codec fixture';
  } on Object catch (error, stackTrace) {
    web.document.body!.textContent = 'FAIL\n$error\n$stackTrace';
  }
}

Future<void> _verifyMigrationBundle() async {
  const bundle = FixtureAppDatabaseVoxelMigrations.bundle;
  final database = await TursoDatabase.open(
    TursoLocation.memory(),
    web: TursoWebOptions(moduleUri: Uri.parse('turso/turso_bridge.js')),
  );
  try {
    await database.execute("ATTACH DATABASE ':memory:' AS content");
    for (final (index, migration) in bundle.migrations.indexed) {
      await _executeMigration(database, migration);
      if (index == 0) {
        await database.execute("INSERT INTO content.authors VALUES ('author-1', 'Ada')");
        await database.execute(
          "INSERT INTO content.articles VALUES ('post-1', 'author-1', 'published')",
        );
      }
    }
    final row = (await database.query('SELECT authorID, status FROM content.posts')).rows.single;
    _expect(
      row.getString('authorID') == 'author-1' && row.getString('status') == 'live',
      'bundled migration row mismatch',
    );
  } finally {
    await database.close();
  }
}

Future<void> _executeMigration(
  TursoDatabase database,
  VoxelBundledMigration migration,
) async {
  final bytes = utf8.encode(migration.sql);
  for (final rawPhase in migration.metadata['phases']! as List<Object?>) {
    final phase = rawPhase! as Map<String, Object?>;
    final rebuild = phase['rebuild'] as Map<String, Object?>?;
    if (rebuild != null) await database.execute('PRAGMA foreign_keys=OFF');
    try {
      await database.transaction<void>((transaction) async {
        for (final rawRange in phase['statements']! as List<Object?>) {
          final range = rawRange! as Map<String, Object?>;
          await transaction.execute(
            utf8.decode(
              bytes.sublist(range['startByte']! as int, range['endByte']! as int),
            ),
          );
        }
        if (rebuild != null) {
          for (final rawValidation in rebuild['validations']! as List<Object?>) {
            final validation = rawValidation! as Map<String, Object?>;
            final row = (await transaction.query(validation['sql']! as String)).rows.single;
            if (row.getInt('valid') != 1) {
              throw StateError('Bundled migration validation failed.');
            }
          }
        }
      });
    } finally {
      if (rebuild != null) await database.execute('PRAGMA foreign_keys=ON');
    }
  }
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
