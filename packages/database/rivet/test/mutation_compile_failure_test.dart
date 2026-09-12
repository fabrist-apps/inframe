import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('generated insert companions reject invalid calls at compile time', () async {
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
    final invalidSource = File('${directory.path}/invalid_insert.dart');
    await invalidSource.writeAsString('''
import 'package:rivet/rivet.dart';
import '$generatedConsumer';

void invalidInsertCalls() {
  MutationUsersCompanion.insert();
  MutationUsersCompanion.insert(
    id: const RivetValue.present('wrong'),
    name: const RivetValue.present('Ada'),
  );
  MutationUsersCompanion.insert(
    id: RivetValue.expression((users) => users.name.value(1)),
    name: const RivetValue.present('Ada'),
  );
  MutationUsers().integer().defaultValue(() async => 1);
  MutationUsers().integer().onUpdate(() => MutationUsers().id.value(1));
  MetadataColumnsCompanion.insert(
    code: const RivetValue.present('storage'),
  );
  MetadataColumnsCompanion.insert(
    code: RivetValue.expression((values) => values.code.value(const UserCode('domain'))),
  );
}
''');

    final result = await Process.run(
      Platform.resolvedExecutable,
      ['--packages=$packageConfig', 'analyze', '--format=machine', invalidSource.path],
      workingDirectory: Directory.current.path,
    );

    expect(result.exitCode, 3, reason: '${result.stdout}\n${result.stderr}');
    final diagnostics = result.stdout as String;
    expect(diagnostics, contains('MISSING_REQUIRED_ARGUMENT'));
    expect(diagnostics, contains('ARGUMENT_TYPE_NOT_ASSIGNABLE'));
    expect(diagnostics, contains('RETURN_OF_INVALID_TYPE_FROM_CLOSURE'));
  });
}
