import 'package:build_test/build_test.dart';
import 'package:build/build.dart';
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
              contains('final class _\$UserProfilesDB'),
              contains('abstract class _\$RivetApp'),
              contains("schemaName: 'auth'"),
              contains("tableName: 'userProfiles'"),
            ),
          ),
        },
      );
    });
  });
}
