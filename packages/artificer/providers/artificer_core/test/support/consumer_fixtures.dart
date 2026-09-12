import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:test/test.dart';

final class ConsumerFixtures {
  ConsumerFixtures._(this._directory);

  final Directory _directory;

  static Future<ConsumerFixtures> create() async {
    final entrypoint = Isolate.resolvePackageUriSync(
      Uri.parse('package:artificer_core/artificer_core.dart'),
    )!;
    final package = File.fromUri(entrypoint).parent.parent;
    final source = Directory.fromUri(package.uri.resolve('test/fixtures/'));
    final directory = await Directory.systemTemp.createTemp('artificer_core_consumers_');
    addTearDown(() => directory.delete(recursive: true));

    await for (final entity in source.list(recursive: true)) {
      if (entity is! File) continue;
      final relativePath = entity.path.substring(source.path.length).replaceFirst(RegExp('^/'), '');
      final destination = File(
        '${directory.path}/${relativePath.replaceAll('.dart.txt', '.dart')}',
      );
      await destination.parent.create(recursive: true);
      var contents = await entity.readAsString();
      if (relativePath.endsWith('pubspec.yaml')) {
        final conflux = Directory.fromUri(package.uri.resolve('../../../conflux'));
        contents = contents
            .replaceAll('path: ../../../../../../conflux', 'path: ${jsonEncode(conflux.path)}')
            .replaceAll('path: ../../..', 'path: ${jsonEncode(package.path)}');
      }
      await destination.writeAsString(contents);
    }
    return ConsumerFixtures._(directory);
  }

  Future<void> resolve(String package) => _dart(package, ['pub', 'get', '--offline']);

  Future<void> analyze(String package, String file) =>
      _dart(package, ['analyze', '--format=machine', file]);

  Future<void> run(String package, String file) => _dart(package, ['run', file]);

  Future<void> _dart(String package, List<String> arguments) async {
    final result = await Process.run(
      Platform.resolvedExecutable,
      arguments,
      workingDirectory: '${_directory.path}/$package',
    );
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
  }
}
