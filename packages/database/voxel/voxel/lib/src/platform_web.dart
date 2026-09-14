// Platform selection helpers are internal to the Voxel connection owner.
// ignore_for_file: public_member_api_docs

import 'package:turso/turso.dart';

import 'package:voxel/src/migration.dart';

const voxelPlatform = 'browser';

TursoWebOptions voxelWebOptions() => TursoWebOptions(
  moduleUri: Uri.parse('turso/turso_bridge.js'),
);

void registerVoxelNativeDefaultStorage(Future<String> Function() resolver) {
  throw UnsupportedError('Native default storage is unavailable in browsers.');
}

Future<TursoDatabase> openVoxelPersistentMain({
  required String databaseName,
  required String? directory,
  required VoxelMigrationPlan migrations,
  required Duration lockTimeout,
  required String? encryptionCipher,
  required Object? encryptionKey,
}) {
  throw UnsupportedError('Native directory storage is unavailable in browsers.');
}
