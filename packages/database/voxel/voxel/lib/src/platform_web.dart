// Platform selection helpers are internal to the Voxel connection owner.
// ignore_for_file: public_member_api_docs

import 'package:turso/turso.dart';

const voxelPlatform = 'browser';

TursoWebOptions voxelWebOptions() => TursoWebOptions(
  moduleUri: Uri.parse('turso/turso_bridge.js'),
);
