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

  Future<void> resolve(String package) => _dart(package, ['pub', 'get', '--offline']);

  Future<void> analyze(String package, String file) =>
      _dart(package, ['analyze', '--format=machine', file]);

  Future<void> analyzeFails(
    String package,
    String file, {
    required String containing,
  }) async {
    final result = await Process.run(
      Platform.resolvedExecutable,
      ['analyze', '--format=machine', file],
      workingDirectory: '${_directory.path}/$package',
    );
    expect(result.exitCode, isNonZero, reason: '${result.stdout}\n${result.stderr}');
    expect('${result.stdout}\n${result.stderr}', contains(containing));
  }

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
