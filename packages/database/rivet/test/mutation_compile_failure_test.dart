import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('generated mutation APIs reject each invalid call at compile time', () async {
    final directory = await Directory.systemTemp.createTemp('rivet_compile_failure_');
    addTearDown(() => directory.delete(recursive: true));
    final candidates = [
      File(
        '${Directory.current.absolute.path}/packages/database/rivet/test/generated_consumer.dart',
      ),
      File('${Directory.current.absolute.path}/test/generated_consumer.dart'),
    ];
    final generatedConsumer = candidates.firstWhere((file) => file.existsSync()).uri;
    final packageConfigs = [
      File('${Directory.current.absolute.path}/.dart_tool/package_config.json'),
      File(
        '${Directory.current.absolute.path}/packages/database/rivet/.dart_tool/package_config.json',
      ),
      File(
        '${Directory.current.absolute.path}/../../../.dart_tool/package_config.json',
      ),
    ];
    final packageConfig = packageConfigs.firstWhere((file) => file.existsSync()).path;
    final invalidCases = <({String name, String diagnostic, String statement})>[
      (
        name: 'missing required insert values',
        diagnostic: 'MISSING_REQUIRED_ARGUMENT',
        statement: 'MutationUsersCompanion.insert();',
      ),
      (
        name: 'insert domain value of the wrong type',
        diagnostic: 'ARGUMENT_TYPE_NOT_ASSIGNABLE',
        statement: '''
MutationUsersCompanion.insert(
  id: const RivetValue.present('wrong'),
  name: const RivetValue.present('Ada'),
);''',
      ),
      (
        name: 'insert expression value of the wrong storage type',
        diagnostic: 'ARGUMENT_TYPE_NOT_ASSIGNABLE',
        statement: '''
MutationUsersCompanion.insert(
  id: RivetValue.expression((users) => users.name.value(1)),
  name: const RivetValue.present('Ada'),
);''',
      ),
      (
        name: 'asynchronous runtime default',
        diagnostic: 'ARGUMENT_TYPE_NOT_ASSIGNABLE',
        statement: 'MutationUsers().integer().defaultValue(() async => 1);',
      ),
      (
        name: 'expression returned from an update hook',
        diagnostic: 'RETURN_OF_INVALID_TYPE_FROM_CLOSURE',
        statement: 'MutationUsers().integer().onUpdate(() => MutationUsers().id.value(1));',
      ),
      (
        name: 'mapped insert storage value passed as a domain value',
        diagnostic: 'ARGUMENT_TYPE_NOT_ASSIGNABLE',
        statement: '''
MetadataColumnsCompanion.insert(
  code: const RivetValue.present('storage'),
);''',
      ),
      (
        name: 'mapped insert domain value passed to a storage expression',
        diagnostic: 'RETURN_OF_INVALID_TYPE_FROM_CLOSURE',
        statement: '''
MetadataColumnsCompanion.insert(
  code: RivetValue.expression(
    (values) => values.code.value(const UserCode('domain')),
  ),
);''',
      ),
      (
        name: 'update value of the wrong type',
        diagnostic: 'ARGUMENT_TYPE_NOT_ASSIGNABLE',
        statement: '''
MutationUpdateUsersCompanion.update(
  age: const RivetValue.present('wrong'),
);''',
      ),
      (
        name: 'mapped update storage value passed as a domain value',
        diagnostic: 'ARGUMENT_TYPE_NOT_ASSIGNABLE',
        statement: '''
MutationUpdateUsersCompanion.update(
  code: const RivetValue.present('storage'),
);''',
      ),
      (
        name: 'mapped update domain value passed to a storage expression',
        diagnostic: 'RETURN_OF_INVALID_TYPE_FROM_CLOSURE',
        statement: '''
MutationUpdateUsersCompanion.update(
  code: RivetValue.expression(
    (values) => values.code.value(const MutationCode('domain')),
  ),
);''',
      ),
      (
        name: 'invalid conflict callback result',
        diagnostic: 'RETURN_OF_INVALID_TYPE_FROM_CLOSURE',
        statement: '''
MutationConflictGroups.db.insert(
  MutationConflictGroupsCompanion.insert(
    id: const RivetValue.present(1),
  ),
  onConflict: (_) => 1,
);''',
      ),
      (
        name: 'conflict update without a target',
        diagnostic: 'MISSING_REQUIRED_ARGUMENT',
        statement: '''
MutationUpsertUsers.db.insert(
  MutationUpsertUsersCompanion.insert(
    id: const RivetValue.present(1),
    email: const RivetValue.present('user@example.com'),
    name: const RivetValue.present('user'),
    age: const RivetValue.present(30),
    active: const RivetValue.present(true),
  ),
  onConflict: (conflict) => conflict.update(
    set: (_, _) => MutationUpsertUsersCompanion.update(),
  ),
);''',
      ),
      (
        name: 'conflict update expression of the wrong mapped storage type',
        diagnostic: 'RETURN_OF_INVALID_TYPE_FROM_CLOSURE',
        statement: '''
MutationUpsertUsers.db.insert(
  MutationUpsertUsersCompanion.insert(
    id: const RivetValue.present(2),
    email: const RivetValue.present('other@example.com'),
    name: const RivetValue.present('other'),
    age: const RivetValue.present(30),
    active: const RivetValue.present(true),
  ),
  onConflict: (conflict) => conflict.update(
    target: (users) => [users.email],
    set: (_, excluded) => MutationUpsertUsersCompanion.update(
      code: RivetValue.expression((_) => excluded.code),
    ),
  ),
);''',
      ),
    ];

    final invalidSources = <File>[];
    for (final (index, invalidCase) in invalidCases.indexed) {
      final invalidSource = File('${directory.path}/invalid_mutation_$index.dart');
      invalidSources.add(invalidSource);
      await invalidSource.writeAsString('''
import 'package:rivet/rivet.dart';
import '$generatedConsumer';

void invalidMutationCall() {
  ${invalidCase.statement}
}
''');
    }

    final result = await Process.run(
      Platform.resolvedExecutable,
      ['--packages=$packageConfig', 'analyze', '--format=machine', directory.path],
      workingDirectory: Directory.current.path,
    );

    expect(result.exitCode, 3, reason: '${result.stdout}\n${result.stderr}');
    final outputLines = (result.stdout as String).split('\n');
    for (final (index, invalidCase) in invalidCases.indexed) {
      final sourceDiagnostics = outputLines
          .where((line) => line.contains('/${invalidSources[index].uri.pathSegments.last}|'))
          .join('\n');
      expect(
        sourceDiagnostics,
        contains(invalidCase.diagnostic),
        reason: '${invalidCase.name}:\n$sourceDiagnostics',
      );
    }
  });
}
