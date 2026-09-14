import 'package:test/test.dart';
import 'package:voxel/src/web_migration_lock.dart';

void main() {
  group('Voxel browser lock adapter', () {
    test('should fail explicitly outside a browser', () {
      expect(createVoxelBrowserLockRequester, throwsUnsupportedError);
    }, testOn: 'vm');
  });
}
