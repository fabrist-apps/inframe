import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:test/test.dart';

/// Stages real consumer packages outside the workspace for public API checks.
final class ConsumerFixtures {
  ConsumerFixtures._(this._directory);

  final Directory _directory;

  static Future<ConsumerFixtures> create() async {
    final entrypoint = Isolate.resolvePackageUriSync(Uri.parse('package:conflux/conflux.dart'))!;
    final package = File.fromUri(entrypoint).parent.parent;
    final source = Directory.fromUri(package.uri.resolve('test/fixtures/'));
    final directory = await Directory.systemTemp.createTemp('conflux_consumers_');
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
        contents = contents.replaceAll('path: ../../..', 'path: ${jsonEncode(package.path)}');
      }
      await destination.writeAsString(contents);
    }
    return ConsumerFixtures._(directory);
  }

  Future<void> resolve(String package) async {
    final result = await _dart(package, ['pub', 'get', '--offline']);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
  }

  Future<void> analyze(String package, String file) async {
    final result = await _dart(package, ['analyze', '--format=machine', file]);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
  }

  Future<void> run(String package, String file) async {
    final result = await _dart(package, ['run', file]);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
  }

  Future<ProcessResult> _dart(String package, List<String> arguments) => Process.run(
    Platform.resolvedExecutable,
    arguments,
    workingDirectory: '${_directory.path}/$package',
  );
}
