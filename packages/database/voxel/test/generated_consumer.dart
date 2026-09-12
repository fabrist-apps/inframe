// The declaration DSL relies on inferred field types for generated output.
// ignore_for_file: specify_nonobvious_property_types

import 'package:voxel/voxel.dart';

part 'generated_consumer.voxel.dart';

@VoxelTable(name: 'users', renamedFrom: 'people', rowName: 'User')
final class Users extends VoxelTableDefinition<Users> {
  static const db = _$UsersDB();

  late final id = chronoID(prefix: 'usr').primaryKey()();
  late final displayName = text(name: 'displayName', renamedFrom: 'name')();
  late final nickname = text().nullable()();
}
