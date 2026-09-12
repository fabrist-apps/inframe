import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:rivet_generator/builder.dart';
import 'package:test/test.dart';

void main() {
  group('RivetGenerator', () {
    test('should generate a table row, accessor, and database open path', () async {
      final readerWriter = TestReaderWriter(rootPackage: 'rivet_generator');
      await readerWriter.testing.loadIsolateSources();
      const source = r'''
library example;

import 'package:rivet/rivet.dart';

part 'example.g.dart';

@RivetTable(schema: 'auth', name: 'userProfiles')
final class UserProfiles extends RivetTableDefinition<UserProfiles> {
  static const db = _$UserProfilesDB();

  late final displayName = text(name: 'displayName')();
}

@RivetDatabase(name: 'rivet_app', tables: [UserProfiles])
final class RivetApp extends _$RivetApp {}
''';

      await testBuilder(
        rivetBuilder(BuilderOptions.empty),
        {'rivet_generator|lib/example.dart': source},
        readerWriter: readerWriter,
        outputs: {
          'rivet_generator|lib/example.rivet.g.part': decodedMatches(
            allOf(
              contains('final class UserProfilesRow'),
              contains(r'final class _$UserProfilesDB'),
              contains(r'abstract class _$RivetApp'),
              contains("schemaName: 'auth'"),
              contains("tableName: 'userProfiles'"),
            ),
          ),
        },
      );
    });

    test('should reject an invalid or colliding generated row name', () async {
      final result = await testBuilder(
        rivetBuilder(BuilderOptions.empty),
        {
          'rivet_generator|lib/invalid_row.dart': r'''
import 'package:rivet/rivet.dart';

part 'invalid_row.g.dart';

@RivetTable(rowName: 'Users')
final class Users extends RivetTableDefinition<Users> {
  static const db = _$UsersDB();
  late final name = text()();
}
''',
        },
      );

      expect(result.succeeded, isFalse);
      expect(result.errors.single, contains('Could not resolve annotation'));
    });

    test('should reject duplicate native enum labels', () async {
      final result = await testBuilder(
        rivetBuilder(BuilderOptions.empty),
        {
          'rivet_generator|lib/invalid_enum.dart': '''
import 'package:rivet/rivet.dart';

part 'invalid_enum.g.dart';

@RivetEnum()
enum Status {
  @RivetEnumValue(name: 'same')
  first,
  @RivetEnumValue(name: 'same')
  second,
}
''',
        },
      );

      expect(result.succeeded, isFalse);
      expect(result.errors.single, contains('Could not resolve annotation'));
    });

    test('should reject ambiguous native enum rename hints', () async {
      final result = await testBuilder(
        rivetBuilder(BuilderOptions.empty),
        {
          'rivet_generator|lib/invalid_enum_rename.dart': '''
import 'package:rivet/rivet.dart';

part 'invalid_enum_rename.g.dart';

@RivetEnum()
enum Status {
  @RivetEnumValue(renamedFrom: 'old')
  first,
  @RivetEnumValue(renamedFrom: 'old')
  second,
}
''',
        },
      );

      expect(result.succeeded, isFalse);
      expect(result.errors.single, contains('Could not resolve annotation'));
    });
  });
}
