import 'dart:io';

import 'package:rivet_generator/src/cli.dart';

Future<void> main(List<String> arguments) async {
  exitCode = await RivetCli().run(arguments);
}
