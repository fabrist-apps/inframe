import 'dart:io';

import 'package:rivet/rivet.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 2) {
    stderr.writeln('usage: migrator_process.dart <directory> <connection-url>');
    exitCode = 64;
    return;
  }
  await RivetMigrator(
    connection: RivetConnection.url(arguments[1], sslMode: RivetSslMode.disable),
    directory: Directory(arguments[0]),
  ).migrate();
}
