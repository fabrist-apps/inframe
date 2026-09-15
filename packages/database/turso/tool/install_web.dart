import 'dart:io';

const _assets = [
  'turso_attachment_registry.js',
  'turso_bridge.js',
  'turso_worker.js',
  'turso_database.js',
  'turso_attachments.js',
  'turso_codec.js',
  'turso_sql_guard.js',
  'turso_opfs_paths.js',
  'turso_upstream.js',
  'turso_sql_guard.wasm',
  'UPSTREAM_LICENSE.md',
];

void main(List<String> arguments) {
  if (arguments.length != 1) {
    stderr.writeln('Usage: dart run tool/install_web.dart <application-web-directory>');
    exitCode = 64;
    return;
  }

  final packageRoot = File.fromUri(Platform.script).parent.parent;
  final sourceDirectory = Directory('${packageRoot.path}/web');
  final destination = Directory(arguments.single)..createSync(recursive: true);
  for (final asset in _assets) {
    File('${sourceDirectory.path}/$asset').copySync('${destination.path}/$asset');
  }
  stdout.writeln('Installed Turso $upstreamVersion web assets in ${destination.path}.');
}

/// The upstream Turso version installed by this package.
const upstreamVersion = '0.8.0-pre.10';
