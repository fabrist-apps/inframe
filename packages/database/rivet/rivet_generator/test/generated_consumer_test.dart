import 'package:analyzer/dart/analysis/utilities.dart';
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

part 'example.rivet.dart';

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
          'rivet_generator|lib/example.rivet.dart': decodedMatches(
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

part 'invalid_row.rivet.dart';

final class ExistingRow {}

@RivetTable(rowName: 'ExistingRow')
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

    test('should escape generated Dart metadata literals', () async {
      final readerWriter = TestReaderWriter(rootPackage: 'rivet_generator');
      await readerWriter.testing.loadIsolateSources();
      const source = r'''
import 'package:rivet/rivet.dart';

part 'escaped.rivet.dart';

@RivetEnum(name: 'state\n\$type')
enum State {
  @RivetEnumValue(name: 'line\n\$value')
  ready,
}

@RivetTable(schema: 'schema\n\$value', name: "quote'name")
final class Escaped extends RivetTableDefinition<Escaped> {
  static const db = _$EscapedDB();
  late final value = text()();
}
''';

      await testBuilder(
        rivetBuilder(BuilderOptions.empty),
        {'rivet_generator|lib/escaped.dart': source},
        readerWriter: readerWriter,
        outputs: {
          'rivet_generator|lib/escaped.rivet.dart': decodedMatches(
            allOf(
              contains(r"schemaName: 'schema\n\$value'"),
              contains(r"tableName: 'quote\'name'"),
              contains(r"'line\n\$value'"),
              predicate<String>(
                (output) => parseString(content: output).errors.isEmpty,
                'valid generated Dart syntax',
              ),
            ),
          ),
        },
      );
    });

    test('should discover an enum codec from the declared column type', () async {
      final readerWriter = TestReaderWriter(rootPackage: 'rivet_generator');
      await readerWriter.testing.loadIsolateSources();
      const source = r'''
import 'package:rivet/rivet.dart';

part 'enum_helper.rivet.dart';

@RivetEnum()
enum Status { ready }

RivetColumn<Status> statusColumn(EnumHelper table) =>
    table.enumText</* retained comment */ Status>()();

@RivetTable()
final class EnumHelper extends RivetTableDefinition<EnumHelper> {
  static const db = _$EnumHelperDB();
  late final RivetColumn<Status> status = statusColumn(this);
}
''';

      await testBuilder(
        rivetBuilder(BuilderOptions.empty),
        {'rivet_generator|lib/enum_helper.dart': source},
        readerWriter: readerWriter,
        outputs: {
          'rivet_generator|lib/enum_helper.rivet.dart': decodedMatches(
            contains('definition.status.configureEnum(StatusRivetEnum.codec);'),
          ),
        },
      );
    });

    test('should reject a repeated array declaration', () async {
      final readerWriter = TestReaderWriter(rootPackage: 'rivet_generator');
      await readerWriter.testing.loadIsolateSources();
      final result = await testBuilder(
        rivetBuilder(BuilderOptions.empty),
        {
          'rivet_generator|lib/repeated_array.dart': r'''
import 'package:rivet/rivet.dart';

part 'repeated_array.rivet.dart';

@RivetTable()
final class RepeatedArray extends RivetTableDefinition<RepeatedArray> {
  static const db = _$RepeatedArrayDB();
  late final values = integer().array().nullable().array()();
}
''',
        },
        readerWriter: readerWriter,
      );

      expect(result.succeeded, isFalse);
    });

    test('should reject duplicate native enum labels', () async {
      final result = await testBuilder(
        rivetBuilder(BuilderOptions.empty),
        {
          'rivet_generator|lib/invalid_enum.dart': '''
import 'package:rivet/rivet.dart';

part 'invalid_enum.rivet.dart';

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

part 'invalid_enum_rename.rivet.dart';

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
