# Voxel

Voxel generates typed Dart rows, mutation companions, connection-free schema metadata, and checked
migration bundles for embedded Turso databases. Generated applications can open isolated memory
databases or persistent native databases; executable typed reads and mutations, watches, and search
are delivered by later Voxel changes.

```dart
import 'package:voxel/voxel.dart';

part 'users.voxel.dart';

@VoxelTable(name: 'users')
final class Users extends VoxelTableDefinition<Users> {
  static const db = _$UsersDB();

  late final id = chronoID(prefix: 'usr').primaryKey()();
  late final name = text()();
}
```

Run `dart run build_runner build` from the containing workspace. Generated accessors own metadata
only; they do not retain a Turso connection. The generated migration library adds the application
open extension. Import it and close the returned owner when finished:

```dart
import 'package:my_app/app_database.dart';
import 'package:my_app/my_app.voxel_migrations.dart';

final database = await MyAppDatabase().open(
  storage: const VoxelStorage.memory(),
);
try {
  await database.transaction((transaction) async {
    // Pass transaction to typed query and mutation terminals.
    transaction.afterCommit(() {
      // Refresh process-local state after the transaction commits.
    });
  });
} finally {
  await database.close();
}
```

On native platforms, pass an explicit parent directory for persistent storage:

```dart
final database = await MyAppDatabase().open(
  storage: const VoxelStorage.directory('/application-owned/data'),
  encryption: VoxelEncryption(
    cipher: VoxelCipher.aegis256,
    key: keyBytes, // Exactly 32 bytes.
  ),
);
```

Plain Dart requires an explicit directory. Flutter applications can register an
application-support directory resolver during startup and then omit `storage`:

```dart
VoxelNativeStorageDefaults.register(
  () async => (await getApplicationSupportDirectory()).path,
);
final database = await MyAppDatabase().open();
```

The resolver returns a path string and can wrap the application's platform-path
provider. An explicit directory always takes precedence. Voxel safely encodes
the database annotation name as a filename inside the selected directory,
coordinates migrations with an operating-system sidecar lock, and enables
foreign keys on every open. `aegis256` and `aes256gcm` use Turso's page
encryption; opening with a wrong key fails and never falls back to plaintext.
Changing encryption on an existing file is not an implicit re-encryption
operation.

SQLite transactions are atomic within one physical database file. Work that
spans independently attached files cannot commit atomically across those files;
Voxel records and verifies completion in each affected file.

Transaction executors are bound to their database and expire when their
callback finishes. Use the transaction executor for all work inside the
callback; root database work is rejected there. A callback failure rolls the
transaction back and is rethrown. Registered `afterCommit` callbacks run only
after a successful commit, outside the expired transaction context and in
registration order. If any fail, Voxel continues the queue and throws an
`AfterCommitException` whose `alreadyCommitted` value is true.

`database.afterCommit` runs its callback immediately when called outside a
transaction. These callbacks are process-local and are not persisted or
replayed after a crash. Closing rejects new work, waits for accepted SQL,
transactions, and callbacks, then releases the single owned Turso connection.
Calling `close` from this database's transaction or after-commit callback is
rejected before shutdown begins.

On web, host the version-matched Turso bridge files under `turso/`; generated open code resolves
`turso/turso_bridge.js`. Memory open validates the complete bundle before acquiring the driver,
attaches each registered named schema as an independent memory database, applies applicable phases
with their receipts, and verifies foreign-key enforcement before returning.
