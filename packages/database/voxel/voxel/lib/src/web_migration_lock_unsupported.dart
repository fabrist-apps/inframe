// Internal conditional fallback for non-browser analysis.
// ignore_for_file: public_member_api_docs

import 'package:voxel/src/web_migration_lock_core.dart';

VoxelWebLockRequester createVoxelBrowserLockRequester() {
  throw UnsupportedError('Web Locks are available only in browsers.');
}
