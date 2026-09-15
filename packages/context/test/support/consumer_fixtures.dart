import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:test/test.dart';

/// Stages a consumer package outside the workspace for analyzer checks.
///
/// Sources are stored as .dart.txt so expected-invalid cases do not enter
/// ordinary workspace analysis.
final class ConsumerFixtures {
  ConsumerFixtures._(this._directory);

  final Directory _directory;

  static Future<ConsumerFixtures> create() async {
    final entrypoint = Isolate.resolvePackageUriSync(Uri.parse('package:context/context.dart'))!;
    final package = File.fromUri(entrypoint).parent.parent;
    final source = Directory.fromUri(package.uri.resolve('test/fixtures/core_consumer/'));
    final directory = await Directory.systemTemp.createTemp('context_consumers_');
    addTearDown(() => directory.delete(recursive: true));

    await for (final entity in source.list()) {
      if (entity is! File) continue;
      final relativePath = entity.path.substring(source.path.length).replaceFirst(RegExp('^/'), '');
      final destination = File(
        '${directory.path}/${relativePath.replaceAll('.dart.txt', '.dart')}',
      );
      await destination.parent.create(recursive: true);
      var contents = await entity.readAsString();
      if (relativePath.endsWith('pubspec.yaml')) {
        contents = contents.replaceAll('path: ../../..', 'path: ${jsonEncode(package.path)}');
      }
      await destination.writeAsString(contents);
    }
    final fixtures = ConsumerFixtures._(directory);
    final result = await fixtures._dart(['pub', 'get', '--offline']);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    return fixtures;
  }

  Future<void> analyze(String file, {required List<String> errors}) async {
    final result = await _dart(['analyze', '--format=machine', file]);
    final output = '${result.stdout}\n${result.stderr}';
    final diagnostics = const LineSplitter()
        .convert(output)
        .where((line) => line.startsWith('ERROR|'))
        .map((line) => line.split('|')[2]);
    expect(diagnostics, unorderedEquals(errors), reason: output);
    expect(result.exitCode, 3, reason: output);
  }

  Future<ProcessResult> _dart(List<String> arguments) => Process.run(
    Platform.resolvedExecutable,
    arguments,
    workingDirectory: _directory.path,
  );
}
