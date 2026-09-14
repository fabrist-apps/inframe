import 'dart:convert';
import 'dart:io';

import 'package:rivet/rivet.dart';
import 'package:rivet_generator/rivet_generator.dart';
import 'package:rivet_generator/src/migration/checker.dart';
import 'package:rivet_generator/src/migration/sealer.dart';

// This type is public only so the executable can keep argument handling testable.
// ignore_for_file: public_member_api_docs, cascade_invocations

final class RivetCli {
  RivetCli({IOSink? stdout, IOSink? stderr, Map<String, String>? environment})
    : _stdout = stdout ?? ioStdout,
      _stderr = stderr ?? ioStderr,
      _environment = environment ?? Platform.environment;

  final IOSink _stdout;
  final IOSink _stderr;
  final Map<String, String> _environment;
  final Set<String> _redactions = {};

  Future<int> run(List<String> arguments) async {
    if (arguments.isEmpty || (arguments.length == 1 && arguments.single == '--help')) {
      _stdout.writeln(_usage);
      return 0;
    }
    try {
      return switch (arguments.first) {
        'generate' => await _generate(arguments.skip(1).toList()),
        'check' => await _check(arguments.skip(1).toList()),
        'seal' => await _seal(arguments.skip(1).toList()),
        'migrate' => await _migrate(arguments.skip(1).toList()),
        'status' => await _status(arguments.skip(1).toList()),
        'resolve' => await _resolve(arguments.skip(1).toList()),
        _ => throw FormatException('Unknown Rivet command `${arguments.first}`.'),
      };
    } on Object catch (error) {
      _stderr.writeln('rivet: ${_redact('$error')}');
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
    final transforms = options['transforms'] == null
        ? const <String, String>{}
        : _readEnumTransforms(File(options['transforms']!));
    final migrationId = await const RivetMigrationGenerator().generateDeclaration(
      declaration: declaration,
      directory: Directory(output),
      name: name,
      source: {'library': library, 'class': className},
      enumLabelTransforms: transforms,
    );
    _stdout.writeln(migrationId == null ? 'Schema is current.' : 'Generated $migrationId.');
    return 0;
  }

  Map<String, String> _readEnumTransforms(File file) {
    final value = jsonDecode(file.readAsStringSync());
    if (value is! Map<String, Object?> || value.entries.any((entry) => entry.value is! String)) {
      throw const FormatException(
        'The transforms file must be a JSON object mapping enum label paths to retained labels.',
      );
    }
    return {for (final entry in value.entries) entry.key: entry.value! as String};
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

  Future<int> _seal(List<String> arguments) async {
    final options = _options(arguments);
    final directory = options['dir'];
    final migration = options['migration'];
    if (directory == null || migration == null) {
      throw const FormatException('seal requires --dir and --migration.');
    }
    await RivetArtifactSealer().seal(
      directory: Directory(directory),
      migrationId: migration,
    );
    _stdout.writeln('Sealed $migration.');
    return 0;
  }

  Future<int> _migrate(List<String> arguments) async {
    final options = _options(arguments);
    final migrator = _deploymentMigrator(options);
    await migrator.migrate();
    _stdout.writeln('Rivet migrations are current.');
    return 0;
  }

  Future<int> _status(List<String> arguments) async {
    final options = _options(arguments);
    final status = await _deploymentMigrator(options).status();
    _stdout.writeln(
      jsonEncode({
        'databaseId': status.databaseId,
        'migrations': [
          for (final migration in status.migrations)
            {
              'id': migration.id,
              'checksum': migration.checksum,
              'ordinal': migration.ordinal,
              'phases': [
                for (final phase in migration.phases)
                  {
                    'id': phase.id,
                    'state': phase.state.name,
                    if (phase.attemptId != null) 'attemptId': phase.attemptId,
                    if (phase.evidence != null) 'evidence': phase.evidence,
                  },
              ],
            },
        ],
      }),
    );
    return 0;
  }

  Future<int> _resolve(List<String> arguments) async {
    final options = _options(arguments);
    final migration = options['migration'];
    final phase = options['phase'];
    final checksum = options['checksum'];
    final attempt = options['attempt'];
    final reason = options['reason'];
    final resolution = switch (options['resolution']) {
      'completed' => RivetMigrationResolution.completed,
      'retry' => RivetMigrationResolution.retry,
      _ => null,
    };
    if ([migration, phase, checksum, attempt, reason].contains(null) || resolution == null) {
      throw const FormatException(
        'resolve requires --migration, --phase, --checksum, --attempt, '
        '--reason, and --resolution completed|retry.',
      );
    }
    await _deploymentMigrator(options).resolve(
      migrationId: migration!,
      phaseId: phase!,
      expectedChecksum: checksum!,
      attemptId: attempt!,
      reason: reason!,
      resolution: resolution,
    );
    _stdout.writeln('Resolved $migration phase $phase as ${resolution.name}.');
    return 0;
  }

  RivetMigrator _deploymentMigrator(Map<String, String> options) {
    final directory = options['dir'];
    final environmentName = options['connection-env'];
    if (directory == null || environmentName == null) {
      throw const FormatException('Deployment commands require --dir and --connection-env.');
    }
    final databaseUrl = _environment[environmentName];
    if (databaseUrl == null || databaseUrl.isEmpty) {
      throw FormatException('Environment variable `$environmentName` is not set.');
    }
    _rememberCredentials(databaseUrl);
    final timeoutText = options['lock-timeout'] ?? '30';
    final timeoutSeconds = int.tryParse(timeoutText);
    if (timeoutSeconds == null || timeoutSeconds < 0) {
      throw const FormatException(
        '--lock-timeout must be a nonnegative integer number of seconds.',
      );
    }
    return RivetMigrator(
      connection: RivetConnection.url(databaseUrl),
      directory: Directory(directory),
      lockTimeout: Duration(seconds: timeoutSeconds),
    );
  }

  void _rememberCredentials(String databaseUrl) {
    _redactions.add(databaseUrl);
    final uri = Uri.tryParse(databaseUrl);
    if (uri == null) return;
    if (uri.userInfo.isNotEmpty) {
      _redactions.add(uri.userInfo);
      _redactions.add(Uri.decodeComponent(uri.userInfo));
      final separator = uri.userInfo.indexOf(':');
      if (separator >= 0 && separator < uri.userInfo.length - 1) {
        _redactions.add(uri.userInfo.substring(separator + 1));
        _redactions.add(Uri.decodeComponent(uri.userInfo.substring(separator + 1)));
      }
    }
    uri.queryParametersAll.values.forEach(_redactions.addAll);
  }

  String _redact(String message) {
    var redacted = message;
    for (final secret in _redactions.where((value) => value.isNotEmpty)) {
      redacted = redacted.replaceAll(secret, '[REDACTED]');
    }
    return redacted;
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

  rivet generate --database <library-uri>#<class> --out <directory> --name <label> [--transforms <file>]
  rivet check --dir <directory>
  rivet seal --dir <directory> --migration <id>
  rivet migrate --dir <directory> --connection-env <name> [--lock-timeout <seconds>]
  rivet status --dir <directory> --connection-env <name> [--lock-timeout <seconds>]
  rivet resolve --dir <directory> --connection-env <name> --migration <id> --phase <id> --checksum <sha256> --attempt <id> --reason <text> --resolution completed|retry [--lock-timeout <seconds>]
''';

final IOSink ioStdout = stdout;
final IOSink ioStderr = stderr;
