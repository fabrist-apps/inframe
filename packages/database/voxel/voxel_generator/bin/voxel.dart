import 'dart:io';

import 'package:voxel_generator/src/cli.dart';

Future<void> main(List<String> arguments) async {
  exitCode = await VoxelCli().run(arguments);
}
