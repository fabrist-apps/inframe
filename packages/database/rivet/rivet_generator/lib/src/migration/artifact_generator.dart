import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:rivet/rivet.dart';

import 'package:rivet_generator/src/migration/canonical_json.dart';
import 'package:rivet_generator/src/migration/checker.dart';
import 'package:rivet_generator/src/migration/schema_expression.dart';

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
    Map<String, String>? source,
  }) async {
    _validateLabel(name);
    final physicalDeclaration = normalizeDeclaration(declaration);
    directory.createSync(recursive: true);
    final journalFile = File('${directory.path}/journal.json');
    if (journalFile.existsSync()) {
      return _generateNext(
        declaration: physicalDeclaration,
        directory: directory,
        name: name,
        source: source,
      );
    }

    final databaseId = _nextId();
    final snapshot = _initialSnapshot(physicalDeclaration, databaseId);
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
      if (source != null) 'source': source,
      'entries': [
        {'id': migrationId, 'directory': directoryName, 'checksum': checksum},
      ],
    };

    _publish(
      directory: directory,
      directoryName: directoryName,
      migrationId: migrationId,
      sql: sql,
      snapshot: snapshot,
      migration: migration,
      journal: journal,
    );
    return migrationId;
  }

  Map<String, Object?> _nextSnapshot(
    Map<String, Object?> declaration,
    Map<String, Object?> previous,
    String databaseId,
  ) {
    final previousSchemas = (previous['schemas']! as List<Object?>).cast<Map<String, Object?>>();
    final previousSchemaNames = {
      for (final schema in previousSchemas) schema['id']!: schema['name']! as String,
    };
    final schemaIds = {
      for (final schema in previousSchemas) schema['name']! as String: schema['id']! as String,
    };
    final declaredTables = (declaration['tables']! as List<Object?>).cast<Map<String, Object?>>();
    for (final table in declaredTables) {
      schemaIds.putIfAbsent(table['schema']! as String, _nextId);
    }
    final previousTables = (previous['tables']! as List<Object?>).cast<Map<String, Object?>>();
    final usedTableIds = <String>{};
    final tables = <Map<String, Object?>>[];
    for (final declaredTable in declaredTables) {
      final schemaName = declaredTable['schema']! as String;
      final tableName = declaredTable['name']! as String;
      final exact = previousTables.where(
        (table) =>
            previousSchemaNames[table['schemaId']] == schemaName && table['name'] == tableName,
      );
      var oldTable = exact.singleOrNull;
      if (oldTable == null) {
        final renamedFrom = declaredTable['renamedFrom'];
        if (renamedFrom is String) {
          final candidates = previousTables.where(
            (table) =>
                previousSchemaNames[table['schemaId']] == schemaName &&
                table['name'] == renamedFrom &&
                !usedTableIds.contains(table['id']),
          );
          if (candidates.length != 1) {
            throw FormatException(
              'Table rename $schemaName.$renamedFrom -> $tableName has no unique source.',
            );
          }
          oldTable = candidates.single;
        }
      }
      if (oldTable != null && !usedTableIds.add(oldTable['id']! as String)) {
        throw FormatException('Several table declarations resolve to ${oldTable['name']}.');
      }
      final tableId = oldTable?['id'] as String? ?? _nextId();
      final oldColumns = oldTable == null
          ? const <Map<String, Object?>>[]
          : (oldTable['columns']! as List<Object?>).cast<Map<String, Object?>>();
      final usedColumnIds = <String>{};
      final columns = <Map<String, Object?>>[];
      for (final rawColumn in declaredTable['columns']! as List<Object?>) {
        final declaredColumn = rawColumn! as Map<String, Object?>;
        final columnName = declaredColumn['name']! as String;
        var oldColumn = oldColumns.where((column) => column['name'] == columnName).singleOrNull;
        if (oldColumn == null) {
          final renamedFrom = declaredColumn['renamedFrom'];
          if (renamedFrom is String) {
            final candidates = oldColumns.where(
              (column) => column['name'] == renamedFrom && !usedColumnIds.contains(column['id']),
            );
            if (candidates.length != 1) {
              throw FormatException(
                'Column rename $schemaName.$tableName.$renamedFrom -> $columnName has no unique source.',
              );
            }
            oldColumn = candidates.single;
          }
        }
        if (oldColumn != null && !usedColumnIds.add(oldColumn['id']! as String)) {
          throw FormatException('Several columns resolve to ${oldColumn['name']}.');
        }
        columns.add({
          'id': oldColumn?['id'] as String? ?? _nextId(),
          'tableId': tableId,
          ..._withoutKey(declaredColumn, 'renamedFrom'),
        });
      }
      tables.add({
        'id': tableId,
        'schemaId': schemaIds[schemaName],
        'name': tableName,
        'columns': columns,
        'indexes': declaredTable['indexes'],
        'constraints': declaredTable['constraints'],
      });
    }
    tables.sort((left, right) => (left['id']! as String).compareTo(right['id']! as String));
    final schemas = [
      for (final entry in schemaIds.entries) {'id': entry.value, 'name': entry.key},
    ]..sort((left, right) => (left['id']! as String).compareTo(right['id']! as String));
    return {
      'formatVersion': 1,
      'dialect': 'rivet',
      'databaseId': databaseId,
      'migrationId': '',
      'schemas': schemas,
      'tables': tables,
      'enums': previous['enums'],
      'requirements': declaration['requirements'],
    };
  }

  Future<String?> _generateNext({
    required Map<String, Object?> declaration,
    required Directory directory,
    required String name,
    Map<String, String>? source,
  }) async {
    await RivetArtifactChecker().check(directory: directory);
    final journalFile = File('${directory.path}/journal.json');
    final journal = jsonDecode(journalFile.readAsStringSync()) as Map<String, Object?>;
    final entries = (journal['entries']! as List<Object?>).cast<Map<String, Object?>>();
    final previousEntry = entries.last;
    final previousDirectory = previousEntry['directory']! as String;
    final previousSnapshot = jsonDecode(
      File('${directory.path}/$previousDirectory/snapshot.json').readAsStringSync(),
    ) as Map<String, Object?>;
    final databaseId = journal['databaseId']! as String;
    final snapshot = _nextSnapshot(declaration, previousSnapshot, databaseId);
    if (_fingerprint(snapshot) == _fingerprint(previousSnapshot)) return null;

    final migrationId = _nextId();
    snapshot['migrationId'] = migrationId;
    final sql = _diffSql(previousSnapshot, snapshot);
    if (sql.isEmpty) {
      throw UnsupportedError(
        'The composed schema changed, but Rivet cannot generate its PostgreSQL DDL.',
      );
    }
    final metadata = <String, Object?>{
      'formatVersion': 1,
      'dialect': 'rivet',
      'databaseId': databaseId,
      'id': migrationId,
      'parentId': previousEntry['id'],
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
    final directoryName =
        '${entries.length.toString().padLeft(4, '0')}_${_slug(name)}_$migrationId';
    final updatedJournal = <String, Object?>{
      ...journal,
      if (source != null) 'source': source,
      'entries': [
        ...entries,
        {'id': migrationId, 'directory': directoryName, 'checksum': checksum},
      ],
    };
    _publish(
      directory: directory,
      directoryName: directoryName,
      migrationId: migrationId,
      sql: sql,
      snapshot: snapshot,
      migration: migration,
      journal: updatedJournal,
    );
    return migrationId;
  }

  Map<String, Object?> _initialSnapshot(
    Map<String, Object?> declaration,
    String databaseId,
  ) {
    final declaredTables = (declaration['tables']! as List<Object?>).cast<Map<String, Object?>>();
    for (final table in declaredTables) {
      if (table['renamedFrom'] != null ||
          (table['columns']! as List<Object?>).any(
            (column) => (column! as Map<String, Object?>)['renamedFrom'] != null,
          )) {
        throw const FormatException(
          'Rename hints require a previous Rivet snapshot with a matching source.',
        );
      }
    }
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
    return ' DEFAULT ${renderSchemaExpression(expression)}';
  }

  String _fingerprint(Map<String, Object?> snapshot) => canonicalJson(
    _withoutKeysRecursively(snapshot, {'id', 'tableId', 'schemaId', 'migrationId', 'renamedFrom'}),
  );

  String _diffSql(Map<String, Object?> previous, Map<String, Object?> next) {
    final previousSchemas = {
      for (final value in (previous['schemas']! as List<Object?>).cast<Map<String, Object?>>())
        value['id']! as String: value['name']! as String,
    };
    final nextSchemas = {
      for (final value in (next['schemas']! as List<Object?>).cast<Map<String, Object?>>())
        value['id']! as String: value['name']! as String,
    };
    final previousTables = {
      for (final value in (previous['tables']! as List<Object?>).cast<Map<String, Object?>>())
        value['id']! as String: value,
    };
    final nextTables = {
      for (final value in (next['tables']! as List<Object?>).cast<Map<String, Object?>>())
        value['id']! as String: value,
    };
    final buffer = StringBuffer();
    for (final entry in nextSchemas.entries) {
      if (!previousSchemas.containsKey(entry.key)) {
        buffer.writeln('CREATE SCHEMA IF NOT EXISTS ${_quote(entry.value)};');
      }
    }
    for (final entry in previousTables.entries) {
      if (!nextTables.containsKey(entry.key)) {
        buffer.writeln(
          'DROP TABLE ${_quote(previousSchemas[entry.value['schemaId']]!)}.'
          '${_quote(entry.value['name']! as String)};',
        );
      }
    }
    for (final entry in nextTables.entries) {
      final nextTable = entry.value;
      final previousTable = previousTables[entry.key];
      if (previousTable == null) {
        buffer.write(_createTableSql(nextTable, nextSchemas));
        continue;
      }
      final oldSchema = previousSchemas[previousTable['schemaId']]!;
      final newSchema = nextSchemas[nextTable['schemaId']]!;
      if (oldSchema != newSchema) {
        throw UnsupportedError('Moving a Rivet table between schemas is not supported.');
      }
      var qualifiedTable = '${_quote(oldSchema)}.${_quote(previousTable['name']! as String)}';
      if (previousTable['name'] != nextTable['name']) {
        buffer.writeln(
          'ALTER TABLE $qualifiedTable RENAME TO ${_quote(nextTable['name']! as String)};',
        );
        qualifiedTable = '${_quote(newSchema)}.${_quote(nextTable['name']! as String)}';
      }
      _writeColumnDiff(buffer, qualifiedTable, previousTable, nextTable);
    }
    return buffer.toString();
  }

  void _writeColumnDiff(
    StringBuffer buffer,
    String qualifiedTable,
    Map<String, Object?> previousTable,
    Map<String, Object?> nextTable,
  ) {
    final previousColumns = {
      for (final value in (previousTable['columns']! as List<Object?>).cast<Map<String, Object?>>())
        value['id']! as String: value,
    };
    final nextColumns = {
      for (final value in (nextTable['columns']! as List<Object?>).cast<Map<String, Object?>>())
        value['id']! as String: value,
    };
    for (final entry in nextColumns.entries) {
      final nextColumn = entry.value;
      final previousColumn = previousColumns[entry.key];
      if (previousColumn == null) {
        final storage = nextColumn['storage']! as Map<String, Object?>;
        buffer.writeln(
          'ALTER TABLE $qualifiedTable ADD COLUMN ${_quote(nextColumn['name']! as String)} '
          '${_postgresType(storage)}${_defaultSql(nextColumn)}'
          '${storage['nullable'] == true ? '' : ' NOT NULL'};',
        );
        continue;
      }
      var columnName = previousColumn['name']! as String;
      if (columnName != nextColumn['name']) {
        buffer.writeln(
          'ALTER TABLE $qualifiedTable RENAME COLUMN ${_quote(columnName)} '
          'TO ${_quote(nextColumn['name']! as String)};',
        );
        columnName = nextColumn['name']! as String;
      }
      final oldStorage = previousColumn['storage']! as Map<String, Object?>;
      final newStorage = nextColumn['storage']! as Map<String, Object?>;
      if (canonicalJson(_withoutKey(oldStorage, 'nullable')) !=
          canonicalJson(_withoutKey(newStorage, 'nullable'))) {
        final type = _postgresType(newStorage);
        buffer.writeln(
          'ALTER TABLE $qualifiedTable ALTER COLUMN ${_quote(columnName)} '
          'TYPE $type USING ${_quote(columnName)}::$type;',
        );
      }
      if (oldStorage['nullable'] != newStorage['nullable']) {
        buffer.writeln(
          'ALTER TABLE $qualifiedTable ALTER COLUMN ${_quote(columnName)} '
          '${newStorage['nullable'] == true ? 'DROP' : 'SET'} NOT NULL;',
        );
      }
      if (canonicalJson(previousColumn['default']) != canonicalJson(nextColumn['default'])) {
        buffer.writeln(
          'ALTER TABLE $qualifiedTable ALTER COLUMN ${_quote(columnName)} '
          '${nextColumn['default'] == null ? 'DROP DEFAULT' : 'SET${_defaultSql(nextColumn)}'};',
        );
      }
      if (previousColumn['primaryKey'] != nextColumn['primaryKey']) {
        throw UnsupportedError('Changing an existing primary key is not supported.');
      }
    }
    for (final entry in previousColumns.entries) {
      if (!nextColumns.containsKey(entry.key)) {
        buffer.writeln(
          'ALTER TABLE $qualifiedTable DROP COLUMN '
          '${_quote(entry.value['name']! as String)};',
        );
      }
    }
  }

  String _createTableSql(
    Map<String, Object?> table,
    Map<String, String> schemaNames,
  ) {
    final columns = (table['columns']! as List<Object?>).cast<Map<String, Object?>>();
    final buffer = StringBuffer()
      ..writeln(
        'CREATE TABLE ${_quote(schemaNames[table['schemaId']]!)}.'
        '${_quote(table['name']! as String)} (',
      );
    for (var index = 0; index < columns.length; index++) {
      final column = columns[index];
      final storage = column['storage']! as Map<String, Object?>;
      buffer.writeln(
        '  ${_quote(column['name']! as String)} ${_postgresType(storage)}'
        '${storage['nullable'] == true ? '' : ' NOT NULL'}'
        '${column['primaryKey'] == true ? ' PRIMARY KEY' : ''}'
        '${_defaultSql(column)}${index == columns.length - 1 ? '' : ','}',
      );
    }
    return (buffer..writeln(');')).toString();
  }

  Map<String, Object?> _withoutKey(Map<String, Object?> value, String key) => {
    for (final entry in value.entries)
      if (entry.key != key) entry.key: entry.value,
  };

  Object? _withoutKeysRecursively(Object? value, Set<String> keys) => switch (value) {
    final Map<String, Object?> map => {
      for (final entry in map.entries)
        if (!keys.contains(entry.key)) entry.key: _withoutKeysRecursively(entry.value, keys),
    },
    final List<Object?> list => [
      for (final item in list) _withoutKeysRecursively(item, keys),
    ],
    _ => value,
  };

  void _publish({
    required Directory directory,
    required String directoryName,
    required String migrationId,
    required String sql,
    required Map<String, Object?> snapshot,
    required Map<String, Object?> migration,
    required Map<String, Object?> journal,
  }) {
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
      temporaryJournal.renameSync('${directory.path}/journal.json');
    } finally {
      if (staging.existsSync()) staging.deleteSync(recursive: true);
    }
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
