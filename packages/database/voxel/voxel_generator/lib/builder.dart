import 'package:build/build.dart';
import 'package:source_gen/source_gen.dart';
import 'package:voxel_generator/src/database_generator.dart';
import 'package:voxel_generator/src/enum_generator.dart';
import 'package:voxel_generator/src/migration_bundle_builder.dart';
import 'package:voxel_generator/src/table_generator.dart';

/// Builds generated Voxel table and database parts.
Builder voxelBuilder(BuilderOptions options) => PartBuilder(
  const [VoxelTableGenerator(), VoxelDatabaseGenerator(), VoxelEnumGenerator()],
  '.voxel.dart',
  options: options,
);

/// Embeds checked migration artifacts in a standalone Dart library.
Builder voxelMigrationBundleBuilder(BuilderOptions options) => const VoxelMigrationBundleBuilder();
