import 'package:turso/turso.dart';
import 'package:voxel/voxel.dart';
import 'package:web/web.dart' as web;

import '../../test/generated_consumer.dart';

Future<void> main() async {
  try {
    await _verifyGeneratedTextStorage();
    await _verifyScalarStorage();
    web.document.body!.textContent = 'PASS\nVoxel browser codec fixture';
  } on Object catch (error, stackTrace) {
    web.document.body!.textContent = 'FAIL\n$error\n$stackTrace';
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
  } on Object {
    return;
  }
  throw StateError('Expected malformed stored text to fail.');
}
