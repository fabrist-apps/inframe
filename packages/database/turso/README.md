# Turso

Internal Dart and Flutter bindings for an embedded Turso database.

SQL, transactions, persistent storage, and encryption run through packaged native libraries and the
browser bridge. The supported runtime matrix is exercised in CI; see
[VERIFICATION.md](VERIFICATION.md) for the recorded environments and contract trace.

## Native example

```dart
import 'dart:typed_data';

import 'package:turso/turso.dart';

Future<(int, String)> writeAndRead(
  String databasePath,
  Uint8List encryptionKey,
) async {
  final database = await TursoDatabase.open(
    TursoLocation.file(databasePath),
    encryption: TursoEncryption(
      cipher: TursoCipher.aegis256,
      key: encryptionKey,
    ),
  );
  try {
    await database.execute(
      'CREATE TABLE IF NOT EXISTS notes (id INTEGER PRIMARY KEY, title TEXT)',
    );
    await database.transaction((tx) async {
      await tx.execute(
        'INSERT INTO notes (id, title) VALUES (?, ?)',
        parameters: [42, 'Hello'],
      );
    });
    final result = await database.query(
      'SELECT id, title FROM notes WHERE id = ?',
      parameters: [42],
    );
    final row = result.rows.single;
    return (row.getInt('id'), row.getString('title'));
  } finally {
    await database.close();
  }
}
```

The caller owns the database path, parent directory, schema, key generation, and key storage. Each
database has one serialized connection, and native engine work runs in a dedicated isolate. Queries
buffer their complete result.

Packaged native targets are:

| Platform | Minimum | Architectures |
| --- | --- | --- |
| Android | API 24 | ARM64, x64 |
| iOS | 15 | ARM64 device; ARM64 and x64 simulators |
| macOS | 11 | ARM64 |
| Linux | glibc 2.35 | x64 |
| Windows | 10 | x64 |

The Android libraries retain 16 KiB load-segment alignment. Applications receive these versioned
artifacts through the Dart native-assets build hook and do not need Rust or an Android NDK. Build
provenance and integrity hashes are recorded in [native/README.md](native/README.md).

SQL accepts either positional parameters or named parameters using their full placeholder spelling,
such as `{':id': 42}`. One call cannot use both. Supported values are `null`, `String`, finite
numbers, signed 64-bit `BigInt` values, and `Uint8List`. The package copies mutable parameter lists,
maps, and blobs when accepting an operation. Missing, extra, mixed, and unsupported bindings fail
before execution, as do multiple SQL statements and SQL containing NUL characters.

Every SQL INTEGER returns as `BigInt`. Integral Dart numbers bind as integers only within
±9,007,199,254,740,991; use `BigInt` outside that portable range. `getInt` enforces the same range.
SQL REAL values return as `double`, without implicit integer conversion. Results preserve column and
row order and are immutable. Duplicate column names remain available through `valueAt`; lookup by an
ambiguous name fails. Blob getters return defensive copies.

`query` buffers all rows, including `RETURNING` rows. `execute` consumes returned rows and reports a
`BigInt rowsAffected`. V1 has no result-size limit or streaming API, so use bounded queries for data
that can grow.

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

## Attached databases and foreign keys

ATTACH and DETACH are enabled for every database connection. Use the existing raw SQL API to add a
schema, including a bound native path:

```dart
await database.execute(
  'ATTACH DATABASE ? AS auxiliary',
  parameters: [attachedPath],
);
await database.execute('CREATE TABLE auxiliary.items (id INTEGER PRIMARY KEY)');
final items = await database.query('SELECT id FROM auxiliary.items');
await database.execute('DETACH DATABASE auxiliary');
```

Native parent directories must already exist. `':memory:'` creates an in-memory attachment on
native and web. An alias belongs to one connection: DETACH or close releases it, and reopening the
main database does not restore it. The attached database contents persist independently, so callers
can explicitly re-attach the file later.

Foreign-key enforcement keeps the upstream default, which is off. Applications that need it issue
`PRAGMA foreign_keys=ON` after every open and before starting a transaction. Enforcement applies to
relationships within each schema; cross-schema foreign keys are unavailable. The package does not
scan or repair existing data, add multi-file crash atomicity beyond Turso, or make an attached file
inherit the main database's encryption key.

## Encryption

Pass `TursoEncryption` with either `TursoCipher.aegis256` or `TursoCipher.aes256gcm` and exactly 32
key bytes. Both ciphers have been verified with persistent reopen on every supported native runtime
and desktop browser. Wrong keys and missing encryption settings fail open; the package never retries
as plaintext.

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

The OPFS persistence, reload, lock-release, memory, and shared SQL contract checks run in current
stable desktop Chrome, Firefox, and actual macOS Safari. The same check covers callback transaction
commit, rollback, isolation, and handle expiry. Mobile browsers are outside the v1 support matrix.
Exact tested versions and runner images are recorded in [VERIFICATION.md](VERIFICATION.md).

## SQL features

`capabilities` reports features verified for the selected packaged artifact:

| Runtime | AEGIS-256 | AES-256-GCM | FTS | Vector functions | Vector indexes |
| --- | --- | --- | --- | --- | --- |
| Android, iOS, macOS, Linux, Windows | Yes | Yes | Yes | Yes | No |
| Desktop Chrome, Firefox, Safari | Yes | Yes | No | Yes | No |

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
