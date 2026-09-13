import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:rivet_generator/src/migration/canonical_json.dart';
import 'package:rivet_generator/src/migration/checker.dart';
import 'package:rivet_generator/src/migration/recovery_validator.dart';
import 'package:rivet_generator/src/migration/sql_parser.dart';

// The sealer is internal to the CLI operation.
// ignore_for_file: public_member_api_docs

final class RivetArtifactSealer {
  Future<void> seal({required Directory directory, required String migrationId}) async {
    await RivetArtifactChecker().check(
      directory: directory,
      allowUnsealedMigrationId: migrationId,
    );
    final journalFile = File('${directory.path}/journal.json');
    final journal = jsonDecode(journalFile.readAsStringSync()) as Map<String, Object?>;
    final entries = (journal['entries']! as List<Object?>).cast<Map<String, Object?>>();
    final matches = entries.where((entry) => entry['id'] == migrationId);
    if (matches.length != 1) throw FormatException('Unknown migration `$migrationId`.');
    final entry = matches.single;
    final migrationDirectory = '${directory.path}/${entry['directory']}';
    final migrationFile = File('$migrationDirectory/migration.json');
    final snapshotFile = File('$migrationDirectory/snapshot.json');
    final sqlFile = File('$migrationDirectory/migration.sql');
    final migration = jsonDecode(migrationFile.readAsStringSync()) as Map<String, Object?>;
    final snapshot = jsonDecode(snapshotFile.readAsStringSync()) as Map<String, Object?>;
    final sql = _readUtf8(sqlFile);
    final sqlBytes = utf8.encode(sql);
    final ranges = parseRivetSqlStatements(sql);
    final phases = (migration['phases']! as List<Object?>).cast<Map<String, Object?>>();
    final statementCounts = [
      for (final phase in phases) (phase['statements']! as List<Object?>).length,
    ];
    if (statementCounts.fold<int>(0, (sum, count) => sum + count) != ranges.length) {
      throw const FormatException(
        'Reviewed SQL changed the statement count, so phase assignment is ambiguous.',
      );
    }
    var offset = 0;
    for (var index = 0; index < phases.length; index++) {
      final count = statementCounts[index];
      phases[index]['statements'] = ranges.sublist(offset, offset + count);
      offset += count;
      validateRivetRecovery(
        phases[index],
        [
          for (final range in phases[index]['statements']! as List<Object?>)
            utf8.decode(
              sqlBytes.sublist(
                (range! as Map<String, Object?>)['startByte']! as int,
                (range as Map<String, Object?>)['endByte']! as int,
              ),
            ),
        ],
      );
    }
    final metadata = Map<String, Object?>.from(migration)..remove('checksum');
    final checksum = sha256
        .convert(
          utf8.encode(canonicalJson({'metadata': metadata, 'snapshot': snapshot, 'sql': sql})),
        )
        .toString();
    final sealedMigration = {...metadata, 'checksum': checksum};
    final sealedJournal = <String, Object?>{
      ...journal,
      'entries': [
        for (final value in entries)
          if (value['id'] == migrationId) {...value, 'checksum': checksum} else value,
      ],
    };
    RivetArtifactChecker().validateSealedMigration(sealedMigration, snapshot, sql);
    final migrationTemporary = File('$migrationDirectory/.migration.$migrationId.tmp');
    final journalTemporary = File('${directory.path}/.journal.$migrationId.tmp');
    _writeJson(migrationTemporary, sealedMigration);
    _writeJson(journalTemporary, sealedJournal);
    migrationTemporary.renameSync(migrationFile.path);
    journalTemporary.renameSync(journalFile.path);
    await RivetArtifactChecker().check(directory: directory);
  }

  String _readUtf8(File file) {
    final bytes = file.readAsBytesSync();
    if (bytes.length >= 3 && bytes[0] == 0xef && bytes[1] == 0xbb && bytes[2] == 0xbf) {
      throw const FormatException('Migration SQL must not contain a UTF-8 BOM.');
    }
    return utf8.decode(bytes);
  }

  void _writeJson(File file, Map<String, Object?> value) {
    file.writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(_sorted(value))}\n',
      flush: true,
    );
  }

  Object? _sorted(Object? value) => switch (value) {
    final Map<String, Object?> map => Map.fromEntries(
      (map.entries.toList()..sort((left, right) => left.key.compareTo(right.key))).map(
        (entry) => MapEntry(entry.key, _sorted(entry.value)),
      ),
    ),
    final List<Object?> list => [for (final item in list) _sorted(item)],
    _ => value,
  };
}
