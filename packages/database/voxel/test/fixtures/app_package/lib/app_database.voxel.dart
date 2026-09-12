// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

part of 'app_database.dart';

// **************************************************************************
// VoxelDatabaseGenerator
// **************************************************************************

abstract class _$FixtureAppDatabase {
  /// Connection-free metadata composed for this application database.
  VoxelDatabaseSchema get schema => VoxelDatabaseSchema(
    name: 'fixture_app',
    tables: [
      Authors.db.buildSchema() as VoxelTableSchema<Object?, Object?>,
      Posts.db.buildSchema() as VoxelTableSchema<Object?, Object?>,
      Tags.db.buildSchema() as VoxelTableSchema<Object?, Object?>,
      PostTags.db.buildSchema() as VoxelTableSchema<Object?, Object?>,
    ],
  );
}
