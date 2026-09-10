import 'dart:io';

import 'package:turso/turso.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 1) {
    stderr.writeln('Usage: dart run example/turso_example.dart <database-path>');
    exitCode = 64;
    return;
  }

  final database = await TursoDatabase.open(TursoLocation.file(arguments.single));
  try {
    await database.execute(
      'CREATE TABLE IF NOT EXISTS notes (id INTEGER PRIMARY KEY, title TEXT)',
    );
    await database.execute(
      'INSERT INTO notes (title) VALUES (?)',
      parameters: ['Hello from Turso'],
    );
    final result = await database.query('SELECT id, title FROM notes ORDER BY id');
    for (final row in result.rows) {
      stdout.writeln('${row.getBigInt('id')}: ${row.getString('title')}');
    }
  } finally {
    await database.close();
  }
}
