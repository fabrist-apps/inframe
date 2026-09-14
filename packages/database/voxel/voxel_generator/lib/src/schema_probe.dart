import 'dart:convert';
import 'dart:io';
import 'dart:math';

// Shared by the CLI and migration bundle builder.
// ignore_for_file: public_member_api_docs

Future<Map<String, Object?>> readVoxelSchemaDeclaration(
  String library,
  String className, {
  Directory? workingDirectory,
}) async {
  final root = workingDirectory ?? Directory.current;
  final toolDirectory = Directory('${root.path}/.dart_tool/voxel_generator')
    ..createSync(recursive: true);
  final nonce = List.generate(
    8,
    (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
  final probe = File('${toolDirectory.path}/schema_probe_${pid}_$nonce.dart');
  final importUri = library.replaceAll(r'\', r'\\').replaceAll("'", r"\'");
  probe.writeAsStringSync('''
import 'dart:convert';
import 'dart:io';
import '$importUri' as target;

void main() {
  stdout.write(jsonEncode(target.${className}VoxelSchema.toJson()));
}
''');
  try {
    final result = await Process.run(
      _dartExecutable(),
      [probe.path],
      workingDirectory: root.path,
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

String _dartExecutable() {
  final resolved = File(Platform.resolvedExecutable);
  if (resolved.uri.pathSegments.last == 'dartaotruntime') {
    return File('${resolved.parent.path}/dart').path;
  }
  return resolved.path;
}
