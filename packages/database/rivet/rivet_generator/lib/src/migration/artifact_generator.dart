import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:rivet/rivet.dart';

import 'package:rivet_generator/src/migration/canonical_json.dart';

// This coordinator is internal to RivetMigrationGenerator's public operation.
// ignore_for_file: public_member_api_docs, unnecessary_cast, use_null_aware_elements

final class RivetArtifactGenerator {
  RivetArtifactGenerator({String Function()? createId}) : _createId = createId ?? _secureId;

  final String Function() _createId;

  Future<String?> generate({
    required RivetDatabaseSchema schema,
    required Directory directory,
    required String name,
  }) async {
    _validateLabel(name);
    return generateDeclaration(
      declaration: schema.toJson(),
      directory: directory,
      name: name,
    );
  }

  Future<String?> generateDeclaration({
    required Map<String, Object?> declaration,
    required Directory directory,
    required String name,
  }) async {
    _validateLabel(name);
    directory.createSync(recursive: true);
    final journalFile = File('${directory.path}/journal.json');
    if (journalFile.existsSync()) {
      throw UnsupportedError('Successive Rivet migrations are not implemented yet.');
    }

    final databaseId = _nextId();
    final snapshot = _initialSnapshot(declaration, databaseId);
    final migrationId = _nextId();
    snapshot['migrationId'] = migrationId;
    final sql = _initialSql(snapshot);
    final metadata = <String, Object?>{
      'formatVersion': 1,
      'dialect': 'rivet',
      'databaseId': databaseId,
      'id': migrationId,
      'parentId': null,
      'phases': [
        {
          'id': '0',
          'scopeId': databaseId,
          'mode': 'transactional',
          'platforms': ['postgresql'],
          'statements': _statementRanges(sql),
          'recovery': null,
        },
      ],
    };
    final checksum = _checksum(metadata, snapshot, sql);
    final migration = {...metadata, 'checksum': checksum};
    final directoryName = '0000_${_slug(name)}_$migrationId';
    final journal = <String, Object?>{
      'formatVersion': 1,
      'dialect': 'rivet',
      'databaseId': databaseId,
      'entries': [
        {'id': migrationId, 'directory': directoryName, 'checksum': checksum},
      ],
    };

    final staging = Directory('${directory.path}/.rivet-staging-$migrationId');
    if (staging.existsSync()) {
      throw StateError('Staging directory already exists: ${staging.path}');
    }
    staging.createSync();
    try {
      _writeText(File('${staging.path}/migration.sql'), sql);
      _writeJson(File('${staging.path}/snapshot.json'), snapshot);
      _writeJson(File('${staging.path}/migration.json'), migration);
      staging.renameSync('${directory.path}/$directoryName');

      final temporaryJournal = File('${directory.path}/.journal-$migrationId.tmp');
      _writeJson(temporaryJournal, journal);
      temporaryJournal.renameSync(journalFile.path);
    } finally {
      if (staging.existsSync()) staging.deleteSync(recursive: true);
    }
    return migrationId;
  }

  Map<String, Object?> _initialSnapshot(
    Map<String, Object?> declaration,
    String databaseId,
  ) {
    final declaredTables = (declaration['tables']! as List<Object?>).cast<Map<String, Object?>>();
    final schemaIds = <String, String>{};
    for (final table in declaredTables) {
      schemaIds.putIfAbsent(table['schema']! as String, _nextId);
    }
    final schemas = [
      for (final entry in schemaIds.entries) {'id': entry.value, 'name': entry.key},
    ]..sort((left, right) => (left['id']! as String).compareTo(right['id']! as String));

    final tables = <Map<String, Object?>>[];
    for (final declaredTable in declaredTables) {
      final tableId = _nextId();
      final columns = <Map<String, Object?>>[];
      for (final value in declaredTable['columns']! as List<Object?>) {
        final column = value! as Map<String, Object?>;
        columns.add({
          'id': _nextId(),
          'tableId': tableId,
          ...column,
        });
      }
      tables.add({
        'id': tableId,
        'schemaId': schemaIds[declaredTable['schema']],
        'name': declaredTable['name'],
        if (declaredTable['renamedFrom'] case final renamedFrom?) 'renamedFrom': renamedFrom,
        'columns': columns,
        'indexes': declaredTable['indexes'],
        'constraints': declaredTable['constraints'],
      });
    }
    tables.sort((left, right) => (left['id']! as String).compareTo(right['id']! as String));

    return {
      'formatVersion': 1,
      'dialect': 'rivet',
      'databaseId': databaseId,
      'migrationId': '',
      'schemas': schemas,
      'tables': tables,
      'enums': <Object?>[],
      'requirements': declaration['requirements'],
    };
  }

  String _initialSql(Map<String, Object?> snapshot) {
    final schemas = (snapshot['schemas']! as List<Object?>).cast<Map<String, Object?>>();
    final schemaNames = {
      for (final schema in schemas) schema['id']: schema['name']! as String,
    };
    final buffer = StringBuffer();
    for (final schema in schemas) {
      buffer.writeln('CREATE SCHEMA IF NOT EXISTS ${_quote(schema['name']! as String)};');
    }
    for (final table in (snapshot['tables']! as List<Object?>).cast<Map<String, Object?>>()) {
      final columns = (table['columns']! as List<Object?>).cast<Map<String, Object?>>();
      buffer.writeln(
        'CREATE TABLE ${_quote(schemaNames[table['schemaId']]!)}.${_quote(table['name']! as String)} (',
      );
      for (var index = 0; index < columns.length; index++) {
        final column = columns[index];
        final storage = column['storage']! as Map<String, Object?>;
        final suffix = index == columns.length - 1 ? '' : ',';
        buffer.writeln(
          '  ${_quote(column['name']! as String)} ${_postgresType(storage)}'
          '${storage['nullable'] == true ? '' : ' NOT NULL'}'
          '${column['primaryKey'] == true ? ' PRIMARY KEY' : ''}'
          '${_defaultSql(column)}$suffix',
        );
      }
      buffer.writeln(');');
    }
    return buffer.toString();
  }

  String _postgresType(Map<String, Object?> storage) => switch (storage['kind']) {
    'text' => 'text',
    'integer' => 'int4',
    'real' => 'float8',
    'boolean' => 'bool',
    'dateTime' => 'timestamptz(3)',
    'json' => 'jsonb',
    'array' => '${_postgresType(storage['element']! as Map<String, Object?>)}[]',
    final kind => throw UnsupportedError('Rivet migrations do not support $kind columns yet.'),
  };

  String _defaultSql(Map<String, Object?> column) {
    final expression = column['default'];
    if (expression is! Map<String, Object?>) return '';
    return ' DEFAULT ${expression['sql']}';
  }

  List<Map<String, int>> _statementRanges(String sql) {
    final bytes = utf8.encode(sql);
    final ranges = <Map<String, int>>[];
    var start = 0;
    for (var index = 0; index < bytes.length; index++) {
      if (bytes[index] != 0x3b) continue;
      ranges.add({'startByte': start, 'endByte': index + 1});
      start = index + 1;
      while (start < bytes.length && (bytes[start] == 0x0a || bytes[start] == 0x0d)) {
        start++;
      }
      index = start - 1;
    }
    if (start != bytes.length) {
      throw StateError('Generated SQL contains an incomplete statement.');
    }
    return ranges;
  }

  String _checksum(
    Map<String, Object?> metadata,
    Map<String, Object?> snapshot,
    String sql,
  ) => sha256
      .convert(
        utf8.encode(canonicalJson({'metadata': metadata, 'snapshot': snapshot, 'sql': sql})),
      )
      .toString();

  String _nextId() {
    final id = _createId();
    if (!RegExp(r'^[0-9a-f]{32}$').hasMatch(id)) {
      throw StateError('Rivet IDs must contain 32 lowercase hexadecimal characters.');
    }
    return id;
  }

  static String _secureId() {
    final random = Random.secure();
    return List.generate(16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }

  void _validateLabel(String value) {
    if (value.trim().isEmpty) throw ArgumentError.value(value, 'name', 'must not be empty');
  }

  String _slug(String value) {
    final slug = value.trim().toLowerCase().replaceAll(RegExp('[^a-z0-9]+'), '_');
    return slug.replaceAll(RegExp(r'^_+|_+$'), '');
  }

  String _quote(String identifier) => '"${identifier.replaceAll('"', '""')}"';

  void _writeText(File file, String contents) {
    file.writeAsBytesSync(utf8.encode(contents), flush: true);
  }

  void _writeJson(File file, Map<String, Object?> value) {
    final normalized = _sorted(value);
    _writeText(file, '${const JsonEncoder.withIndent('  ').convert(normalized)}\n');
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
