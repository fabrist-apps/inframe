import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:test/test.dart';
import 'package:voxel_generator/builder.dart';

void main() {
  group('Voxel table generation', () {
    test('generates rows, companions and connection-free metadata', () async {
      final readerWriter = TestReaderWriter(rootPackage: 'voxel_generator');
      await readerWriter.testing.loadIsolateSources();
      await testBuilder(
        voxelBuilder(BuilderOptions.empty),
        {
          'voxel_generator|lib/users.dart': r'''
import 'package:voxel/voxel.dart';
part 'users.voxel.dart';

@VoxelTable(name: 'users', renamedFrom: 'people', rowName: 'User')
final class Users extends VoxelTableDefinition<Users> {
  static const db = _$UsersDB();
  late final id = chronoID(prefix: 'usr')();
  late final name = text()();
  late final nickname = text().nullable()();
}
''',
        },
        readerWriter: readerWriter,
        outputs: {
          'voxel_generator|lib/users.voxel.dart': decodedMatches(
            allOf([
              contains('final class User'),
              contains('final class UsersCompanion implements VoxelCompanion<Users>'),
              contains('required VoxelValue<Users, String, String> name'),
              contains('VoxelValue<Users, String, String> id = const VoxelValue.absent()'),
              contains(r'final class _$UsersDB'),
              contains("schemaName: 'main'"),
              contains("tableName: 'users'"),
              contains("renamedFrom: 'people'"),
              isNot(contains('Future<')),
            ]),
          ),
        },
      );
    });

    test('rejects an invalid or colliding row name', () async {
      final readerWriter = TestReaderWriter(rootPackage: 'voxel_generator');
      await readerWriter.testing.loadIsolateSources();
      final result = await testBuilder(
        voxelBuilder(BuilderOptions.empty),
        {
          'voxel_generator|lib/invalid.dart': r'''
import 'package:voxel/voxel.dart';
part 'invalid.voxel.dart';
final class ExistingRow {}
@VoxelTable(rowName: 'ExistingRow')
final class Users extends VoxelTableDefinition<Users> {
  static const db = _$UsersDB();
  late final name = text()();
}
''',
        },
        readerWriter: readerWriter,
      );
      expect(result.succeeded, isFalse);
      expect(result.errors.single, contains('rowName `ExistingRow` is invalid or collides'));
    });
  });
}
