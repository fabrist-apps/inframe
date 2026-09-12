# Voxel

Voxel generates typed Dart rows, mutation companions, and connection-free schema metadata for
embedded Turso databases. This package currently provides the declaration and codec boundary. The
database lifecycle, executable reads and mutations, migrations, watches, and search are delivered
by later Voxel packages and changes.

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
only; they do not retain or open a Turso connection.
