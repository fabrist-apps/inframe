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

    test('rejects mapped runtime hooks declared with the storage type', () async {
      final readerWriter = TestReaderWriter(rootPackage: 'voxel_generator');
      await readerWriter.testing.loadIsolateSources();
      final result = await testBuilder(
        voxelBuilder(BuilderOptions.empty),
        {
          'voxel_generator|lib/invalid_hook.dart': r'''
import 'package:voxel/voxel.dart';
part 'invalid_hook.voxel.dart';
final class Code { const Code(this.value); final String value; }
final class CodeConverter implements VoxelTypeConverter<Code, String> {
  const CodeConverter();
  @override Code fromSql(String value) => Code(value);
  @override String toSql(Code value) => value.value;
}
@VoxelTable()
final class Values extends VoxelTableDefinition<Values> {
  static const db = _$ValuesDB();
  late final code = text().defaultValue(() => 'storage').map(const CodeConverter())();
}
''',
        },
        readerWriter: readerWriter,
      );
      expect(result.succeeded, isFalse);
      expect(result.errors.single, contains('Mapped runtime hooks must be declared after map'));
    });

    test('rejects duplicate enum labels and ambiguous rename hints', () async {
      final readerWriter = TestReaderWriter(rootPackage: 'voxel_generator');
      await readerWriter.testing.loadIsolateSources();
      final duplicate = await testBuilder(
        voxelBuilder(BuilderOptions.empty),
        {
          'voxel_generator|lib/duplicate_enum.dart': '''
import 'package:voxel/voxel.dart';
part 'duplicate_enum.voxel.dart';
@VoxelEnum()
enum Status {
  @VoxelEnumValue(name: 'same') first,
  @VoxelEnumValue(name: 'same') second,
}
''',
        },
        readerWriter: readerWriter,
      );
      expect(duplicate.succeeded, isFalse);
      expect(duplicate.errors.single, contains('enum labels must be unique'));

      final ambiguous = await testBuilder(
        voxelBuilder(BuilderOptions.empty),
        {
          'voxel_generator|lib/ambiguous_enum.dart': '''
import 'package:voxel/voxel.dart';
part 'ambiguous_enum.voxel.dart';
@VoxelEnum()
enum Status {
  @VoxelEnumValue(renamedFrom: 'old') first,
  @VoxelEnumValue(renamedFrom: 'old') second,
}
''',
        },
        readerWriter: readerWriter,
      );
      expect(ambiguous.succeeded, isFalse);
      expect(ambiguous.errors.single, contains('rename hints must identify unambiguous'));
    });
  });
}
