import 'dart:convert';
import 'dart:io';

import 'package:rivet_generator/rivet_generator.dart';
import 'package:rivet_generator/src/migration/checker.dart';

// This type is public only so the executable can keep argument handling testable.
// ignore_for_file: public_member_api_docs, cascade_invocations

final class RivetCli {
  RivetCli({IOSink? stdout, IOSink? stderr})
    : _stdout = stdout ?? ioStdout,
      _stderr = stderr ?? ioStderr;

  final IOSink _stdout;
  final IOSink _stderr;

  Future<int> run(List<String> arguments) async {
    if (arguments.isEmpty || (arguments.length == 1 && arguments.single == '--help')) {
      _stdout.writeln(_usage);
      return 0;
    }
    try {
      return switch (arguments.first) {
        'generate' => await _generate(arguments.skip(1).toList()),
        'check' => await _check(arguments.skip(1).toList()),
        'seal' => throw UnsupportedError('seal is implemented by a later FBR-104 slice.'),
        _ => throw FormatException('Unknown Rivet command `${arguments.first}`.'),
      };
    } on Object catch (error) {
      _stderr.writeln('rivet: $error');
      return 64;
    }
  }

  Future<int> _generate(List<String> arguments) async {
    final options = _options(arguments);
    final database = options['database'];
    final output = options['out'];
    final name = options['name'];
    if (database == null || output == null || name == null) {
      throw const FormatException('generate requires --database, --out, and --name.');
    }
    final separator = database.lastIndexOf('#');
    if (separator <= 0 || separator == database.length - 1) {
      throw const FormatException('--database must be <library-uri>#<class>.');
    }
    final library = database.substring(0, separator);
    final className = database.substring(separator + 1);
    if (!RegExp(r'^[A-Za-z$][A-Za-z0-9_$]*$').hasMatch(className)) {
      throw FormatException('Invalid database class `$className`.');
    }
    final declaration = await _readDeclaration(library, className);
    final migrationId = await const RivetMigrationGenerator().generateDeclaration(
      declaration: declaration,
      directory: Directory(output),
      name: name,
      source: {'library': library, 'class': className},
    );
    _stdout.writeln(migrationId == null ? 'Schema is current.' : 'Generated $migrationId.');
    return 0;
  }

  Future<int> _check(List<String> arguments) async {
    final options = _options(arguments);
    final directoryPath = options['dir'];
    if (directoryPath == null) throw const FormatException('check requires --dir.');
    final directory = Directory(directoryPath);
    final checker = RivetArtifactChecker();
    await checker.check(directory: directory);
    final journalValue = jsonDecode(
      File('${directory.path}/journal.json').readAsStringSync(),
    );
    if (journalValue is! Map<String, Object?>) {
      throw const FormatException('journal.json must be a JSON object.');
    }
    Map<String, Object?>? declaration;
    if (journalValue['source'] case {
      'library': final String library,
      'class': final String className,
    }) {
      declaration = await _readDeclaration(library, className);
    }
    if (declaration != null) {
      await checker.check(directory: directory, declaration: declaration);
    }
    _stdout.writeln('Rivet migration artifacts are valid.');
    return 0;
  }

  Future<Map<String, Object?>> _readDeclaration(
    String library,
    String className,
  ) async {
    final toolDirectory = Directory('${Directory.current.path}/.dart_tool/rivet_generator');
    toolDirectory.createSync(recursive: true);
    final probe = File('${toolDirectory.path}/schema_probe_$pid.dart');
    final importUri = library.replaceAll(r'\', r'\\').replaceAll("'", r"\'");
    probe.writeAsStringSync('''
import 'dart:convert';
import 'dart:io';
import '$importUri' as target;

void main() {
  stdout.write(jsonEncode(target.${className}RivetSchema.build().toJson()));
}
''');
    try {
      final result = await Process.run(
        Platform.resolvedExecutable,
        [probe.path],
        workingDirectory: Directory.current.path,
      );
      if (result.exitCode != 0) {
        throw StateError('Could not load $library#$className:\n${result.stderr}');
      }
      final value = jsonDecode(result.stdout as String);
      if (value is! Map<String, Object?>) {
        throw const FormatException('Generated schema probe returned invalid JSON.');
      }
      return value;
    } finally {
      if (probe.existsSync()) probe.deleteSync();
    }
  }

  Map<String, String> _options(List<String> arguments) {
    final result = <String, String>{};
    for (var index = 0; index < arguments.length; index += 2) {
      if (index + 1 >= arguments.length || !arguments[index].startsWith('--')) {
        throw const FormatException('Options must use --name value pairs.');
      }
      result[arguments[index].substring(2)] = arguments[index + 1];
    }
    return result;
  }
}

const _usage = '''
Rivet migration tooling

  rivet generate --database <library-uri>#<class> --out <directory> --name <label>
  rivet check --dir <directory>
  rivet seal --dir <directory> --migration <id>
''';

final IOSink ioStdout = stdout;
final IOSink ioStderr = stderr;
