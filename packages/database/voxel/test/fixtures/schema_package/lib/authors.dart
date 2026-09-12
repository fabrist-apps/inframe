// Fixture declarations intentionally rely on inferred DSL types.
// ignore_for_file: public_member_api_docs, specify_nonobvious_property_types

import 'package:voxel/voxel.dart';

part 'authors.voxel.dart';

@VoxelTable(schema: 'content')
final class Authors extends VoxelTableDefinition<Authors> {
  static const db = _$AuthorsDB();

  late final id = text().primaryKey()();
  late final name = text()();
  late final _indexes = [
    uniqueIndex('authors_name').on([name]),
  ];
  late final _constraints = [check('authors_name_present', ~name.equals(''))];
}
