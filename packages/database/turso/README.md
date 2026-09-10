# Turso

Internal Dart and Flutter bindings for an embedded Turso database.

The package is under active implementation. SQL, transactions, persistent storage, and encryption
currently run on macOS ARM64 and desktop Chrome. The remaining native targets and complete browser
matrix are still being verified.

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

Use `transaction` for an isolated callback transaction:

```dart
final note = await database.transaction((tx) async {
  await tx.execute(
    'INSERT INTO notes (id, title) VALUES (?, ?)',
    parameters: [42, 'Hello'],
  );
  return (await tx.query('SELECT id, title FROM notes WHERE id = ?', parameters: [42]))
      .rows
      .single;
});
```

Await every transaction operation. The transaction drains work submitted before the callback
finishes, but an operation failure rolls back the transaction even if its returned future is not
awaited. Use only the callback's `TursoTransaction` handle while the callback is active; calls on the
parent database fail immediately and the handle expires when the callback returns. Raw `BEGIN`,
`COMMIT`, `ROLLBACK`, and savepoint statements bypass this managed boundary and are unsupported.

`close` rejects new root operations immediately, waits for accepted operations and transactions,
then releases the connection and worker. Repeated calls share the same shutdown future. A worker
failure or failed rollback retires the connection; later operations fail and diagnostics treat an
interrupted write as having an uncertain outcome.

## Encryption

Pass `TursoEncryption` with either `TursoCipher.aegis256` or `TursoCipher.aes256gcm` and exactly 32
key bytes. Both ciphers have been verified with persistent reopen on macOS ARM64 and desktop Chrome.
Wrong keys and missing encryption settings fail open; the package never retries as plaintext.

The application owns key generation and secure storage. The package copies key bytes at its public
boundary and redacts them from its diagnostics, but it does not promise managed-runtime memory
zeroization.

Encryption uses unchanged upstream Turso `v0.8.0-pre.10` behavior. Native temporary query files can
bypass page encryption under upstream's default file-based temporary-storage policy; this is based
on source inspection rather than a forced-spill reproduction. `VACUUM INTO` produced a plaintext
copy in a local reproduction. Applications should not assume that every byte written by every SQL
command is encrypted. The package does not force `temp_store`, rewrite SQL, or restrict exports.

## Browser setup

Install the pinned browser bridge beside the application's other hosted files:

```sh
dart run packages/database/turso/tool/install_web.dart path/to/app/web/turso
```

Pass its hosted URI when opening either an OPFS database or a web memory database:

```dart
final database = await TursoDatabase.open(
  TursoLocation.browser('notes.db'),
  web: TursoWebOptions(moduleUri: Uri.parse('turso/turso_bridge.js')),
);
```

The page must use a secure context and send `Cross-Origin-Opener-Policy: same-origin` and
`Cross-Origin-Embedder-Policy: require-corp`. Browser queries run in a dedicated module worker;
upstream Turso creates a nested worker for OPFS. The upstream loader reserves 250 MiB of logical
shared WASM memory. Queries still buffer their complete result, so applications should issue bounded
queries.

The hosted verification example can be built and served from this package directory:

```sh
dart run tool/install_web.dart example/web/turso
dart compile js example/web/main.dart -O1 -o example/web/main.dart.js
dart run tool/serve_web_example.dart
```

The OPFS persistence, reload, lock-release, memory, and shared SQL contract checks were run against
desktop Chrome `152.0.7977.65` on macOS. The same browser check covers callback transaction commit,
rollback, isolation, and handle expiry.

## SQL features

`capabilities` reports features verified for the selected packaged artifact:

| Backend | FTS | Vector functions | Vector indexes |
| --- | --- | --- | --- |
| Native | Yes | Yes | No |
| Web | No | Yes | No |

Native FTS uses upstream's raw SQL surface:

```sql
CREATE INDEX documents_fts ON documents USING fts (title, body);
SELECT id FROM documents WHERE fts_match(title, body, 'database');
```

Both backends support verified vector conversion and scalar distance functions, for example
`vector_distance_l2(vector32('[0, 0]'), vector32('[3, 4]'))`. General approximate nearest-neighbor
indexing is not advertised. These checks execute against unchanged Turso `v0.8.0-pre.10`; web FTS is
unavailable in v1.

## Upstream

The package pins unchanged Turso `v0.8.0-pre.10` at commit
`342dfbe267ebdb9141c434c499ce31e10bb46f27`. The generated FFI bindings and native library use the
matching `sdk-kit/turso.h`. See [native/README.md](native/README.md) for build provenance.
