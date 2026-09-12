// Fixture declarations intentionally omit public API documentation.
// ignore_for_file: public_member_api_docs

import 'package:voxel/voxel.dart';
import 'package:voxel_fixture_app/posts.dart';
import 'package:voxel_fixture_schema/authors.dart';

part 'app_database.voxel.dart';

@VoxelDatabase(name: 'fixture_app', tables: [Authors, Posts, Tags, PostTags])
final class FixtureAppDatabase extends _$FixtureAppDatabase {}
