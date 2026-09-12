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

final class NotARivetRelation<T> {}

@RivetTable(schema: 'auth', name: 'userProfiles')
final class UserProfiles extends RivetTableDefinition<UserProfiles> {
  static const db = _$UserProfilesDB();

  late final displayName = text(name: 'displayName')();
  late final ignoredColumns = <RivetColumn<int>>[];
  late final ignoredRelation = NotARivetRelation<int>();
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
              isNot(contains('ignoredColumns')),
              isNot(contains('ignoredRelation')),
            ),
          ),
        },
      );
    });

    test('should generate typed insert companions from column defaults', () async {
      final readerWriter = TestReaderWriter(rootPackage: 'rivet_generator');
      await readerWriter.testing.loadIsolateSources();
      const source = r'''
import 'package:rivet/rivet.dart';

part 'mutations.rivet.dart';

@RivetTable()
final class Users extends RivetTableDefinition<Users> {
  static const db = _$UsersDB();

  late final id = chronoID(prefix: 'usr')();
  late final name = text()();
  late final nickname = text().nullable()();
  late final createdAt = dateTime().defaultValue(DateTime.now)();
  late final updatedAt = dateTime().onUpdate(DateTime.now)();
  late final sequence = integer().defaultSql("nextval('users_seq')")();
}
''';

      await testBuilder(
        rivetBuilder(BuilderOptions.empty),
        {'rivet_generator|lib/mutations.dart': source},
        readerWriter: readerWriter,
        outputs: {
          'rivet_generator|lib/mutations.rivet.dart': decodedMatches(
            allOf(
              allOf(
                contains('final class UsersCompanion implements RivetCompanion<Users>'),
                contains('factory UsersCompanion.insert({'),
                contains('required RivetValue<Users, String, String> name,'),
                contains(
                  'RivetValue<Users, String, String> id = const RivetValue.absent(),',
                ),
                contains(
                  'RivetValue<Users, String?, String?> nickname = const RivetValue.absent(),',
                ),
                contains(
                  'RivetValue<Users, DateTime, DateTime> updatedAt = '
                  'const RivetValue.absent(),',
                ),
              ),
              contains('factory UsersCompanion.update({'),
              contains(
                'RivetValue<Users, String, String> name = const RivetValue.absent(),',
              ),
              contains('RivetInsert<Users, UsersRow> insert(UsersCompanion companion)'),
              contains('RivetUpdate<Users, UsersRow> update('),
            ),
          ),
        },
      );
    });

    test('should preserve mapped array domain and storage mutation types', () async {
      final readerWriter = TestReaderWriter(rootPackage: 'rivet_generator');
      await readerWriter.testing.loadIsolateSources();
      const source = r'''
import 'package:rivet/rivet.dart';

part 'mapped_mutations.rivet.dart';

final class Code {}

final class CodeConverter implements RivetTypeConverter<Code, String> {
  const CodeConverter();
  @override
  Code fromSql(String value) => Code();
  @override
  String toSql(Code value) => 'code';
}

@RivetTable()
final class Values extends RivetTableDefinition<Values> {
  static const db = _$ValuesDB();
  late final codes = text().map(const CodeConverter()).nullable().array()();
}
''';

      await testBuilder(
        rivetBuilder(BuilderOptions.empty),
        {'rivet_generator|lib/mapped_mutations.dart': source},
        readerWriter: readerWriter,
        outputs: {
          'rivet_generator|lib/mapped_mutations.rivet.dart': decodedMatches(
            contains(
              'required RivetValue<Values, List<Code?>, List<String?>> codes,',
            ),
          ),
        },
      );
    });

    test('should reject mapped hooks declared with the storage type', () async {
      final readerWriter = TestReaderWriter(rootPackage: 'rivet_generator');
      await readerWriter.testing.loadIsolateSources();
      final result = await testBuilder(
        rivetBuilder(BuilderOptions.empty),
        {
          'rivet_generator|lib/invalid_mapped_hook.dart': r'''
import 'package:rivet/rivet.dart';

part 'invalid_mapped_hook.rivet.dart';

final class Code {
  const Code(this.value);
  final String value;
}

final class CodeConverter implements RivetTypeConverter<Code, String> {
  const CodeConverter();
  @override
  Code fromSql(String value) => Code(value);
  @override
  String toSql(Code value) => value.value;
}

@RivetTable()
final class Values extends RivetTableDefinition<Values> {
  static const db = _$ValuesDB();
  late final code = text().defaultValue(() => 'storage').map(const CodeConverter())();
}
''',
        },
        readerWriter: readerWriter,
      );

      expect(result.succeeded, isFalse);
      expect(
        result.errors.single,
        contains('Mapped runtime hooks must be declared after map'),
      );
    });

    test('should preserve prefixes for tables with the same class name', () async {
      final readerWriter = TestReaderWriter(rootPackage: 'rivet_generator');
      await readerWriter.testing.loadIsolateSources();

      await testBuilder(
        rivetBuilder(BuilderOptions.empty),
        {
          'rivet_generator|lib/first.dart': r'''
import 'package:rivet/rivet.dart';

part 'first.rivet.dart';

@RivetTable()
final class Users extends RivetTableDefinition<Users> {
  static const db = _$UsersDB();
  late final id = integer()();
}
''',
          'rivet_generator|lib/second.dart': r'''
import 'package:rivet/rivet.dart';

part 'second.rivet.dart';

@RivetTable()
final class Users extends RivetTableDefinition<Users> {
  static const db = _$UsersDB();
  late final id = integer()();
}
''',
          'rivet_generator|lib/prefixed_database.dart': r'''
import 'package:rivet/rivet.dart';
import 'first.dart' as first;
import 'second.dart' as second;

part 'prefixed_database.rivet.dart';

const firstTables = <Type>[first.Users];
const tables = <Type>[...firstTables, second.Users];

@RivetDatabase(name: 'prefixed', tables: tables)
final class PrefixedDatabase extends _$PrefixedDatabase {}
''',
        },
        readerWriter: readerWriter,
        outputs: {
          'rivet_generator|lib/first.rivet.dart': decodedMatches(
            contains(r'final class _$UsersDB'),
          ),
          'rivet_generator|lib/second.rivet.dart': decodedMatches(
            contains(r'final class _$UsersDB'),
          ),
          'rivet_generator|lib/prefixed_database.rivet.dart': decodedMatches(
            allOf(
              contains("name: 'prefixed'"),
              contains('first.Users.db.buildSchema()'),
              contains('second.Users.db.buildSchema()'),
            ),
          ),
        },
      );
    });

    test('should reject an invalid or colliding generated row name', () async {
      final readerWriter = TestReaderWriter(rootPackage: 'rivet_generator');
      await readerWriter.testing.loadIsolateSources();
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
        readerWriter: readerWriter,
      );

      expect(result.succeeded, isFalse);
      expect(result.errors.single, contains('rowName `ExistingRow` is invalid or collides'));
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
      final readerWriter = TestReaderWriter(rootPackage: 'rivet_generator');
      await readerWriter.testing.loadIsolateSources();
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
        readerWriter: readerWriter,
      );

      expect(result.succeeded, isFalse);
      expect(result.errors.single, contains('Native enum labels must be unique.'));
    });

    test('should reject ambiguous native enum rename hints', () async {
      final readerWriter = TestReaderWriter(rootPackage: 'rivet_generator');
      await readerWriter.testing.loadIsolateSources();
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
        readerWriter: readerWriter,
      );

      expect(result.succeeded, isFalse);
      expect(
        result.errors.single,
        contains('Native enum rename hints must identify unambiguous previous labels.'),
      );
    });
  });
}
