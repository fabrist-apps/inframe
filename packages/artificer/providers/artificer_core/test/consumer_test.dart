import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:test/test.dart';

void main() {
  group('Public consumer', () {
    test('should execute and persist shipped models without consumer generation', () async {
      final entry = Isolate.resolvePackageUriSync(
        Uri.parse('package:artificer_core/artificer_core.dart'),
      )!;
      final package = File.fromUri(entry).parent.parent;
      final directory = await Directory.systemTemp.createTemp('artificer-consumer-');
      addTearDown(() => directory.delete(recursive: true));
      await File('${directory.path}/pubspec.yaml').writeAsString('''
name: artificer_consumer
publish_to: none
environment:
  sdk: ^3.13.0
dependencies:
  artificer_core:
    path: ${jsonEncode(package.path)}
  conflux:
    path: ${jsonEncode(Directory('${package.path}/../../../conflux').absolute.path)}
  dart_mappable: ^4.10.0
''');
      await for (final source in Directory('${package.path}/test/fixtures/consumer').list()) {
        if (source is File && source.path.endsWith('.dart.txt')) {
          final name = source.uri.pathSegments.last.replaceFirst('.txt', '');
          await source.copy('${directory.path}/$name');
        }
      }
      for (final args in [
        ['pub', 'get', '--offline'],
        ['analyze', 'main.dart'],
        ['run', 'main.dart'],
      ]) {
        final result = await Process.run(
          Platform.resolvedExecutable,
          args,
          workingDirectory: directory.path,
        );
        expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      }
    });
  });
}
