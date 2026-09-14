# Voxel

Voxel generates typed Dart rows, mutation companions, connection-free schema metadata, and checked
migration bundles for embedded Turso databases. Generated applications can currently open isolated
memory databases; persistent storage, executable typed reads and mutations, watches, and search are
delivered by later Voxel changes.

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
  // Typed query terminals are added by the Voxel reads package.
} finally {
  await database.close();
}
```

On web, host the version-matched Turso bridge files under `turso/`; generated open code resolves
`turso/turso_bridge.js`. Memory open validates the complete bundle before acquiring the driver,
attaches each registered named schema as an independent memory database, applies applicable phases
with their receipts, and verifies foreign-key enforcement before returning.
