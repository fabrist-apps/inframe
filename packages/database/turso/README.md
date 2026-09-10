# Turso

Internal Dart and Flutter bindings for an embedded Turso database.

The package is under active implementation. The current native path runs on macOS ARM64. Later
FBR-25 slices add web, transactions, encryption, all requested native targets, and the complete
platform matrix.

## Native example

```dart
import 'package:turso/turso.dart';

Future<void> main() async {
  final database = await TursoDatabase.open(
    TursoLocation.file('/absolute/path/to/notes.db'),
  );
  try {
    await database.execute(
      'CREATE TABLE IF NOT EXISTS notes (id INTEGER PRIMARY KEY, title TEXT)',
    );
    await database.execute(
      'INSERT INTO notes (id, title) VALUES (?, ?)',
      parameters: [42, 'Hello'],
    );
    final result = await database.query(
      'SELECT id, title FROM notes WHERE id = ?',
      parameters: [42],
    );
    print(result.rows.single.getString('title'));
  } finally {
    await database.close();
  }
}
```

The caller owns the database path and creates its parent directory. Each database has one serialized
connection, and native engine work runs in a dedicated isolate. Queries buffer their complete result.

SQL accepts either positional parameters or named parameters using their full placeholder spelling,
such as `{':id': 42}`. Supported values are `null`, `String`, finite numbers, signed 64-bit `BigInt`
values, and `Uint8List`. SQL integers always return as `BigInt`; `getInt` accepts only values in the
portable safe-integer range.

## Upstream

The package pins unchanged Turso `v0.8.0-pre.10` at commit
`342dfbe267ebdb9141c434c499ce31e10bb46f27`. The generated FFI bindings and native library use the
matching `sdk-kit/turso.h`. See [native/README.md](native/README.md) for build provenance.
