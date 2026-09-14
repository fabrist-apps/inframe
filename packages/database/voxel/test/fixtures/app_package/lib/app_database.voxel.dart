// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

part of 'app_database.dart';

// **************************************************************************
// VoxelDatabaseGenerator
// **************************************************************************

/// Connection-free physical schema metadata for [FixtureAppDatabase].
abstract final class FixtureAppDatabaseVoxelSchema {
  /// Builds the composed schema used by offline migration tooling.
  static VoxelDatabaseSchema build() => VoxelDatabaseSchema(
    name: 'fixture_app',
    tables: [
      Authors.db.buildSchema() as VoxelTableSchema<Object?, Object?>,
      Posts.db.buildSchema() as VoxelTableSchema<Object?, Object?>,
      Tags.db.buildSchema() as VoxelTableSchema<Object?, Object?>,
      PostTags.db.buildSchema() as VoxelTableSchema<Object?, Object?>,
      Locales.db.buildSchema() as VoxelTableSchema<Object?, Object?>,
      Translations.db.buildSchema() as VoxelTableSchema<Object?, Object?>,
    ],
  );

  /// Serializes the composed schema for the migration command-line probe.
  static Map<String, Object?> toJson() => voxelMigrationSchemaToJson(build());
}

abstract class _$FixtureAppDatabase {
  /// Connection-free metadata composed for this application database.
  VoxelDatabaseSchema get schema => FixtureAppDatabaseVoxelSchema.build();
}
