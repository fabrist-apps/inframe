import 'dart:convert';
import 'dart:io';

import 'package:turso/native_migration_lock.dart';

Future<void> main(List<String> arguments) async {
  final lock = NativeMigrationLock.tryAcquire(arguments.single);
  if (lock == null) {
    stderr.writeln('contended');
    exitCode = 2;
    return;
  }

  stdout.writeln('acquired');
  await stdout.flush();
  await stdin.transform(utf8.decoder).first;
  lock.release();
}
