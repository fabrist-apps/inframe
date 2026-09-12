import 'dart:io';

import 'package:runnel/runnel.dart';

Future<void> main() async {
  final endpoint = Platform.environment['RUNNEL_URL'] ?? 'redis://localhost:6379';
  final redis = await Runnel.connect(endpoint);
  try {
    final batch = redis.pipeline();
    final name = batch.add(Get('user:42:name'));
    final visits = batch.add(Incr('user:42:visits'));
    final results = await batch.exec();

    stdout
      ..writeln(results.value(name))
      ..writeln(results.value(visits));
  } finally {
    await redis.close();
  }
}
