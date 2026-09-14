import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:voxel/voxel.dart';

import 'package:voxel_generator/src/migration/canonical_json.dart';
import 'package:voxel_generator/src/migration/checker.dart';
import 'package:voxel_generator/src/migration/schema_expression.dart';

// This coordinator is internal to VoxelMigrationGenerator's public operation.
// ignore_for_file: public_member_api_docs, unnecessary_cast, use_null_aware_elements

final class VoxelArtifactGenerator {
  VoxelArtifactGenerator({String Function()? createId}) : _createId = createId ?? _secureId;

  final String Function() _createId;

  Future<String?> generate({
    required VoxelDatabaseSchema schema,
    required Directory directory,
    required String name,
    Map<String, String> storageTransforms = const {},
  }) async {
    _validateLabel(name);
    return generateDeclaration(
      declaration: voxelMigrationSchemaToJson(schema),
      directory: directory,
      name: name,
      storageTransforms: storageTransforms,
    );
  }

  Future<String?> generateDeclaration({
    required Map<String, Object?> declaration,
    required Directory directory,
    required String name,
    Map<String, String>? source,
    Map<String, String> storageTransforms = const {},
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
        storageTransforms: storageTransforms,
      );
    }

    final databaseId = _nextId();
    final snapshot = _initialSnapshot(physicalDeclaration, databaseId);
    final migrationId = _nextId();
    snapshot['migrationId'] = migrationId;
    final sql = _initialSql(snapshot);
    final metadata = <String, Object?>{
      'formatVersion': 1,
      'dialect': 'voxel',
      'databaseId': databaseId,
      'id': migrationId,
      'parentId': null,
      'phases': _phases(snapshot, sql),
    };
    final checksum = _checksum(metadata, snapshot, sql);
    final migration = {...metadata, 'checksum': checksum};
    final directoryName = '0000_${_slug(name)}_$migrationId';
    final journal = <String, Object?>{
      'formatVersion': 1,
      'dialect': 'voxel',
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
    final declaredEnums = (declaration['enums']! as List<Object?>).cast<Map<String, Object?>>();
    for (final table in declaredTables) {
      schemaIds.putIfAbsent(table['schema']! as String, _nextId);
    }
    for (final value in declaredEnums) {
      schemaIds.putIfAbsent(value['schema']! as String, _nextId);
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
    final enums = _settleEnums(
      declaration,
      (previous['enums']! as List<Object?>).cast<Map<String, Object?>>(),
      schemaIds,
      previousSchemaNames,
    );
    _settleEnumStorage(tables, enums, schemas: schemaIds);
    _settleTableObjects(tables, declaredTables, previousTables, previousSchemaNames);
    tables.sort((left, right) => (left['id']! as String).compareTo(right['id']! as String));
    final schemas = [
      for (final entry in schemaIds.entries) {'id': entry.value, 'name': entry.key},
    ]..sort((left, right) => (left['id']! as String).compareTo(right['id']! as String));
    return {
      'formatVersion': 1,
      'dialect': 'voxel',
      'databaseId': databaseId,
      'migrationId': '',
      'schemas': schemas,
      'tables': tables,
      'enums': enums,
      'requirements': declaration['requirements'],
    };
  }

  Future<String?> _generateNext({
    required Map<String, Object?> declaration,
    required Directory directory,
    required String name,
    required Map<String, String> storageTransforms,
    Map<String, String>? source,
  }) async {
    await VoxelArtifactChecker().check(directory: directory);
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
    final rebuiltScopes = <String>{};
    final sql = _diffSql(
      previousSnapshot,
      snapshot,
      storageTransforms,
      rebuiltScopes,
    );
    final metadata = <String, Object?>{
      'formatVersion': 1,
      'dialect': 'voxel',
      'databaseId': databaseId,
      'id': migrationId,
      'parentId': previousEntry['id'],
      'phases': _phases(snapshot, sql, rebuiltScopes: rebuiltScopes),
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
          'Rename hints require a previous Voxel snapshot with a matching source.',
        );
      }
    }
    final schemaIds = <String, String>{};
    for (final table in declaredTables) {
      schemaIds.putIfAbsent(table['schema']! as String, _nextId);
    }
    for (final rawEnum in declaration['enums']! as List<Object?>) {
      final declaredEnum = rawEnum! as Map<String, Object?>;
      schemaIds.putIfAbsent(declaredEnum['schema']! as String, _nextId);
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
    final enums = _settleEnums(declaration, const [], schemaIds, const {});
    _settleEnumStorage(tables, enums, schemas: schemaIds);
    _settleTableObjects(tables, declaredTables, const [], const {});
    tables.sort((left, right) => (left['id']! as String).compareTo(right['id']! as String));

    return {
      'formatVersion': 1,
      'dialect': 'voxel',
      'databaseId': databaseId,
      'migrationId': '',
      'schemas': schemas,
      'tables': tables,
      'enums': enums,
      'requirements': declaration['requirements'],
    };
  }

  List<Map<String, Object?>> _settleEnums(
    Map<String, Object?> declaration,
    List<Map<String, Object?>> previousEnums,
    Map<String, String> schemaIds,
    Map<Object?, String> previousSchemaNames,
  ) {
    final usedIds = <String>{};
    final declaredNames = <String>{};
    final enums = <Map<String, Object?>>[];
    for (final raw in declaration['enums']! as List<Object?>) {
      final declared = raw! as Map<String, Object?>;
      final schema = declared['schema']! as String;
      final name = declared['name']! as String;
      if (!declaredNames.add('$schema.$name')) {
        throw FormatException('Duplicate Voxel enum declaration $schema.$name.');
      }
      var old = previousEnums
          .where(
            (value) => previousSchemaNames[value['schemaId']] == schema && value['name'] == name,
          )
          .singleOrNull;
      if (old == null && declared['renamedFrom'] is String) {
        final renamedFrom = declared['renamedFrom']! as String;
        final candidates = previousEnums.where(
          (value) =>
              previousSchemaNames[value['schemaId']] == schema &&
              value['name'] == renamedFrom &&
              !usedIds.contains(value['id']),
        );
        if (candidates.length != 1) {
          throw FormatException('Enum rename $schema.$renamedFrom -> $name has no unique source.');
        }
        old = candidates.single;
      }
      if (old != null && !usedIds.add(old['id']! as String)) {
        throw FormatException('Several enum declarations resolve to ${old['name']}.');
      }
      if (old == null &&
          (declared['renamedFrom'] != null ||
              (declared['values']! as List<Object?>).any(
                (value) => (value! as Map<String, Object?>)['renamedFrom'] != null,
              ))) {
        throw const FormatException('Enum rename hints require a matching previous snapshot.');
      }
      final oldValues = old == null
          ? const <Map<String, Object?>>[]
          : (old['values']! as List<Object?>).cast<Map<String, Object?>>();
      final usedValueIds = <String>{};
      final declaredLabels = <String>{};
      final values = <Map<String, Object?>>[];
      for (final rawValue in declared['values']! as List<Object?>) {
        final value = rawValue! as Map<String, Object?>;
        final label = value['label']! as String;
        if (!declaredLabels.add(label)) {
          throw FormatException('Enum $schema.$name has duplicate label `$label`.');
        }
        var oldValue = oldValues.where((candidate) => candidate['label'] == label).singleOrNull;
        if (oldValue == null && value['renamedFrom'] is String) {
          final renamedFrom = value['renamedFrom']! as String;
          final candidates = oldValues.where(
            (candidate) =>
                candidate['label'] == renamedFrom && !usedValueIds.contains(candidate['id']),
          );
          if (candidates.length != 1) {
            throw FormatException('Enum label rename $renamedFrom -> $label has no unique source.');
          }
          oldValue = candidates.single;
        }
        if (oldValue != null && !usedValueIds.add(oldValue['id']! as String)) {
          throw FormatException('Several enum values resolve to ${oldValue['label']}.');
        }
        values.add({
          'id': oldValue?['id'] as String? ?? _nextId(),
          'enumId': old?['id'],
          'label': label,
        });
      }
      final enumId = old?['id'] as String? ?? _nextId();
      for (final value in values) {
        value['enumId'] = enumId;
      }
      enums.add({
        'id': enumId,
        'schemaId': schemaIds[schema],
        'name': name,
        'values': values,
      });
    }
    enums.sort((left, right) => (left['id']! as String).compareTo(right['id']! as String));
    return enums;
  }

  void _settleEnumStorage(
    List<Map<String, Object?>> tables,
    List<Map<String, Object?>> enums, {
    required Map<String, String> schemas,
  }) {
    final byName = {
      for (final value in enums)
        '${schemas.entries.singleWhere((entry) => entry.value == value['schemaId']).key}.${value['name']}':
            value['id']! as String,
    };
    Map<String, Object?> settle(Map<String, Object?> storage) {
      if (storage['kind'] == 'enum') {
        final reference = storage['enum']! as Map<String, Object?>;
        final enumId = byName['${reference['schema']}.${reference['name']}'];
        if (enumId == null) throw const FormatException('Enum column references an unknown type.');
        return {..._withoutKey(storage, 'enum'), 'enumId': enumId};
      }
      if (storage['element'] case final Map<String, Object?> element) {
        return {...storage, 'element': settle(element)};
      }
      return storage;
    }

    for (final table in tables) {
      for (final column in (table['columns']! as List<Object?>).cast<Map<String, Object?>>()) {
        column['storage'] = settle(column['storage']! as Map<String, Object?>);
      }
    }
  }

  void _settleTableObjects(
    List<Map<String, Object?>> tables,
    List<Map<String, Object?>> declarations,
    List<Map<String, Object?>> previousTables,
    Map<Object?, String> previousSchemaNames,
  ) {
    final tableByName = <String, Map<String, Object?>>{};
    for (var index = 0; index < tables.length; index++) {
      final declaration = declarations[index];
      tableByName['${declaration['schema']}.${declaration['name']}'] = tables[index];
    }
    for (var index = 0; index < tables.length; index++) {
      final table = tables[index];
      final declaration = declarations[index];
      final columns = (table['columns']! as List<Object?>).cast<Map<String, Object?>>();
      final columnsByName = {
        for (final column in columns) column['name']! as String: column,
      };
      final oldTable = previousTables.where((value) => value['id'] == table['id']).singleOrNull;
      final oldIndexes = oldTable == null
          ? const <Map<String, Object?>>[]
          : (oldTable['indexes']! as List<Object?>).cast<Map<String, Object?>>();
      final indexes = <Map<String, Object?>>[];
      for (final raw in declaration['indexes']! as List<Object?>) {
        final declared = raw! as Map<String, Object?>;
        final name = declared['name']! as String;
        final old = oldIndexes.where((value) => value['name'] == name).singleOrNull;
        indexes.add({
          'id': old?['id'] as String? ?? _nextId(),
          'tableId': table['id'],
          'name': name,
          'unique': declared['unique'],
          'terms': [
            for (final rawTerm in declared['terms']! as List<Object?>)
              _settleIndexTerm(rawTerm! as Map<String, Object?>, columnsByName),
          ],
          if (declared['predicate'] case final Map<String, Object?> predicate)
            'predicate': _settleExpression(predicate, columnsByName),
          'options': declared['options'] ?? <String, Object?>{},
          'platforms': declared['platforms'] ?? const ['native'],
        });
      }

      final declaredConstraints = [
        ...(declaration['constraints']! as List<Object?>).cast<Map<String, Object?>>(),
        if (columns.any((column) => column['primaryKey'] == true))
          <String, Object?>{
            'name': '${declaration['name']}_pkey',
            'kind': 'primaryKey',
            'columns': [
              for (final column in columns)
                if (column['primaryKey'] == true) column['name'],
            ],
          },
      ];
      final oldConstraints = oldTable == null
          ? const <Map<String, Object?>>[]
          : (oldTable['constraints']! as List<Object?>).cast<Map<String, Object?>>();
      final constraints = <Map<String, Object?>>[];
      for (final declared in declaredConstraints) {
        final kind = declared['kind']! as String;
        final columnIds = [
          for (final name in (declared['columns']! as List<Object?>).cast<String>())
            columnsByName[name]?['id'] as String? ??
                (throw FormatException(
                  'Constraint ${declaration['schema']}.${declaration['name']}.${declared['name']} references unknown column $name.',
                )),
        ];
        final exact = oldConstraints.where((value) => value['name'] == declared['name']);
        final structural = oldConstraints.where(
          (value) =>
              value['kind'] == kind &&
              canonicalJson(value['columnIds']) == canonicalJson(columnIds),
        );
        final old = exact.singleOrNull ?? structural.singleOrNull;
        final constraint = <String, Object?>{
          'id': old?['id'] as String? ?? _nextId(),
          'tableId': table['id'],
          'name': declared['name'],
          'kind': kind,
          'columnIds': columnIds,
        };
        if (declared['expression'] case final Map<String, Object?> expression) {
          constraint['expression'] = _settleExpression(expression, columnsByName);
        }
        if (kind == 'foreignKey') {
          final reference = declared['references']! as Map<String, Object?>;
          final target = tableByName['${reference['schema']}.${reference['table']}'];
          if (target == null) {
            throw FormatException(
              'Foreign key ${declaration['schema']}.${declaration['name']}.${declared['name']} references an unknown table.',
            );
          }
          final targetColumns = {
            for (final value in (target['columns']! as List<Object?>).cast<Map<String, Object?>>())
              value['name']! as String: value,
          };
          final referenceIds = [
            for (final name in (reference['columns']! as List<Object?>).cast<String>())
              targetColumns[name]?['id'] as String? ??
                  (throw FormatException('Foreign key references unknown column $name.')),
          ];
          if (referenceIds.length != columnIds.length) {
            throw const FormatException('Foreign key column counts must match.');
          }
          for (var position = 0; position < columnIds.length; position++) {
            final local = columns.singleWhere((value) => value['id'] == columnIds[position]);
            final remote = (target['columns']! as List<Object?>)
                .cast<Map<String, Object?>>()
                .singleWhere((value) => value['id'] == referenceIds[position]);
            if (canonicalJson(_withoutKey(local['storage']! as Map<String, Object?>, 'nullable')) !=
                canonicalJson(
                  _withoutKey(remote['storage']! as Map<String, Object?>, 'nullable'),
                )) {
              throw const FormatException('Foreign key columns must use compatible storage.');
            }
          }
          constraint
            ..['referenceTableId'] = target['id']
            ..['referenceColumnIds'] = referenceIds
            ..['onDelete'] = declared['onDelete']
            ..['onUpdate'] = declared['onUpdate'];
        }
        constraints.add(constraint);
      }
      indexes.sort((left, right) => (left['id']! as String).compareTo(right['id']! as String));
      constraints.sort((left, right) => (left['id']! as String).compareTo(right['id']! as String));
      table
        ..['indexes'] = indexes
        ..['constraints'] = constraints;
    }
  }

  Map<String, Object?> _settleIndexTerm(
    Map<String, Object?> term,
    Map<String, Map<String, Object?>> columns,
  ) {
    final name = term['column']! as String;
    final column = columns[name];
    if (column == null) throw FormatException('Index references unknown column $name.');
    return {'columnId': column['id'], 'descending': term['descending'] == true};
  }

  Map<String, Object?> _settleExpression(
    Map<String, Object?> expression,
    Map<String, Map<String, Object?>> columns,
  ) {
    if (expression['kind'] == 'reference') {
      final name = expression['objectName'];
      final column = columns[name];
      if (name is! String || column == null) {
        throw FormatException('Schema expression references unknown column $name.');
      }
      return {'formatVersion': 1, 'kind': 'reference', 'objectId': column['id']};
    }
    return {
      ...expression,
      if (expression['arguments'] case final List<Object?> arguments)
        'arguments': [
          for (final argument in arguments)
            _settleExpression(argument! as Map<String, Object?>, columns),
        ],
    };
  }

  String _initialSql(Map<String, Object?> snapshot) {
    final schemas = (snapshot['schemas']! as List<Object?>).cast<Map<String, Object?>>();
    final schemaNames = {
      for (final schema in schemas) schema['id']: schema['name']! as String,
    };
    final buffer = StringBuffer();
    for (final table in (snapshot['tables']! as List<Object?>).cast<Map<String, Object?>>()) {
      buffer.write(
        _createTableSql(
          table,
          schemaNames.cast<String, String>(),
          _tablesById(snapshot),
          enums: _enumsById(snapshot),
        ),
      );
    }
    buffer.write(_addedObjectsSql(snapshot, const {}));
    return buffer.toString();
  }

  String _tursoType(Map<String, Object?> storage) => switch (storage['kind']) {
    'text' || 'json' || 'array' || 'enum' => 'TEXT',
    'integer' || 'boolean' || 'dateTime' => 'INTEGER',
    'real' => 'REAL',
    'vector' => 'F32_BLOB',
    final kind => throw UnsupportedError('Voxel migrations do not support $kind columns yet.'),
  };

  String _defaultSql(Map<String, Object?> column) {
    final expression = column['default'];
    if (expression is! Map<String, Object?>) return '';
    return ' DEFAULT ${renderSchemaExpression(expression)}';
  }

  String _fingerprint(Map<String, Object?> snapshot) => canonicalJson(
    _withoutKeysRecursively(snapshot, {'id', 'tableId', 'schemaId', 'migrationId', 'renamedFrom'}),
  );

  String _diffSql(
    Map<String, Object?> previous,
    Map<String, Object?> next,
    Map<String, String> storageTransforms,
    Set<String> rebuiltScopes,
  ) {
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
    final previousEnums = _enumsById(previous);
    final nextEnums = _enumsById(next);
    final changedEnumIds = <String>{
      for (final entry in nextEnums.entries)
        if (previousEnums[entry.key] case final oldEnum?
            when !_sameEnumLabels(oldEnum, entry.value))
          entry.key,
    };
    final destructiveEnumIds = <String>{
      for (final id in changedEnumIds)
        if (!_enumLabels(nextEnums[id]!).containsAll(_enumLabels(previousEnums[id]!))) id,
    };
    final rebuiltTableIds = <String>{
      for (final entry in nextTables.entries)
        if (previousTables[entry.key] case final oldTable?
            when _requiresRebuild(oldTable, entry.value, changedEnumIds))
          entry.key,
    };
    final usedTransformPaths = <String>{};
    final buffer = StringBuffer()..write(_droppedObjectsSql(previous, next, rebuiltTableIds));
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
        buffer.write(
          _createTableSql(nextTable, nextSchemas, nextTables, enums: nextEnums),
        );
        continue;
      }
      final oldSchema = previousSchemas[previousTable['schemaId']]!;
      final newSchema = nextSchemas[nextTable['schemaId']]!;
      if (oldSchema != newSchema) {
        throw UnsupportedError('Moving a Voxel table between schemas is not supported.');
      }
      if (rebuiltTableIds.contains(entry.key)) {
        rebuiltScopes.add(newSchema);
        buffer.write(
          _rebuildTableSql(
            previousTable,
            nextTable,
            nextSchemas,
            nextTables,
            nextEnums,
            storageTransforms,
            usedTransformPaths,
            destructiveEnumIds,
          ),
        );
        continue;
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
    final unusedTransforms = storageTransforms.keys.toSet().difference(usedTransformPaths);
    if (unusedTransforms.isNotEmpty) {
      throw FormatException(
        'Unused Voxel storage transforms: ${unusedTransforms.toList()..sort()}.',
      );
    }
    buffer.write(_addedObjectsSql(next, previous, rebuiltTableIds));
    return buffer.toString();
  }

  bool _requiresRebuild(
    Map<String, Object?> previous,
    Map<String, Object?> next,
    Set<String> changedEnumIds,
  ) {
    final oldColumns = {
      for (final column in (previous['columns']! as List<Object?>).cast<Map<String, Object?>>())
        column['id']: column,
    };
    final newColumns = {
      for (final column in (next['columns']! as List<Object?>).cast<Map<String, Object?>>())
        column['id']: column,
    };
    if (oldColumns.keys.any((id) => !newColumns.containsKey(id))) return true;
    for (final entry in newColumns.entries) {
      final old = oldColumns[entry.key];
      final column = entry.value;
      if (old == null) {
        if (column['storage'] case {'nullable': false} when column['default'] == null) {
          return true;
        }
        continue;
      }
      if (canonicalJson(old['storage']) != canonicalJson(column['storage']) ||
          canonicalJson(old['default']) != canonicalJson(column['default']) ||
          old['primaryKey'] != column['primaryKey']) {
        return true;
      }
      if (_referencesAnyEnum(column['storage']! as Map<String, Object?>, changedEnumIds)) {
        return true;
      }
    }
    final oldConstraints = _objects(
      previous,
      'constraints',
    ).map((value) => _withoutKeysRecursively(value, {'id', 'tableId', 'name'})).toList();
    final newConstraints = _objects(
      next,
      'constraints',
    ).map((value) => _withoutKeysRecursively(value, {'id', 'tableId', 'name'})).toList();
    return canonicalJson(oldConstraints) != canonicalJson(newConstraints);
  }

  String _rebuildTableSql(
    Map<String, Object?> previous,
    Map<String, Object?> next,
    Map<String, String> schemas,
    Map<String, Map<String, Object?>> tables,
    Map<String, Map<String, Object?>> enums,
    Map<String, String> storageTransforms,
    Set<String> usedTransformPaths,
    Set<String> destructiveEnumIds,
  ) {
    final schema = schemas[next['schemaId']]!;
    final oldName = previous['name']! as String;
    final newName = next['name']! as String;
    final replacement = '__voxel_rebuild_${(next['id']! as String).substring(0, 12)}';
    final oldColumns = {
      for (final column in (previous['columns']! as List<Object?>).cast<Map<String, Object?>>())
        column['id']: column,
    };
    final targetColumns = (next['columns']! as List<Object?>).cast<Map<String, Object?>>();
    final expressions = <String>[];
    for (final column in targetColumns) {
      final path = '$schema.$newName.${column['name']}';
      final transform = storageTransforms[path];
      if (transform != null) {
        if (transform.trim().isEmpty || transform.contains(';')) {
          throw FormatException('Storage transform `$path` must be one SQL expression.');
        }
        usedTransformPaths.add(path);
      }
      final old = oldColumns[column['id']];
      if (old == null) {
        if (transform != null) {
          expressions.add(transform);
        } else if (column['default'] case final Map<String, Object?> expression) {
          expressions.add(renderSchemaExpression(expression));
        } else if ((column['storage']! as Map<String, Object?>)['nullable'] == true) {
          expressions.add('NULL');
        } else {
          throw FormatException(
            'Rebuilding $schema.$newName requires a value for ${column['name']}.',
          );
        }
        continue;
      }
      if (canonicalJson(old['storage']) != canonicalJson(column['storage']) ||
          _referencesAnyEnum(
            column['storage']! as Map<String, Object?>,
            destructiveEnumIds,
          )) {
        if (transform == null) {
          throw FormatException('Rebuilding $schema.$newName requires storage transform `$path`.');
        }
        expressions.add(transform);
      } else {
        expressions.add(_quote(old['name']! as String));
      }
    }
    final temporaryTable = {...next, 'name': replacement, 'indexes': <Object?>[]};
    final columns = targetColumns.map((column) => _quote(column['name']! as String)).join(', ');
    final buffer = StringBuffer()
      ..write(_createTableSql(temporaryTable, schemas, tables, enums: enums))
      ..writeln(
        'INSERT INTO ${_quote(schema)}.${_quote(replacement)} ($columns) '
        'SELECT ${expressions.join(', ')} FROM ${_quote(schema)}.${_quote(oldName)};',
      )
      ..writeln('DROP TABLE ${_quote(schema)}.${_quote(oldName)};')
      ..writeln(
        'ALTER TABLE ${_quote(schema)}.${_quote(replacement)} RENAME TO ${_quote(newName)};',
      )
      ..write(_indexesForTable(next, schemas, tables));
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
          '${_tursoType(storage)}${_defaultSql(nextColumn)}'
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
        throw UnsupportedError(
          'Changing Voxel column storage requires an explicit table rebuild transform.',
        );
      }
      if (oldStorage['nullable'] != newStorage['nullable']) {
        throw UnsupportedError(
          'Changing Voxel column nullability requires a table rebuild.',
        );
      }
      if (canonicalJson(previousColumn['default']) != canonicalJson(nextColumn['default'])) {
        throw UnsupportedError(
          'Changing a Voxel column default requires a table rebuild.',
        );
      }
    }
    for (final entry in previousColumns.entries) {
      if (!nextColumns.containsKey(entry.key)) {
        throw UnsupportedError(
          'Dropping a Voxel column requires an explicit table rebuild.',
        );
      }
    }
  }

  String _createTableSql(
    Map<String, Object?> table,
    Map<String, String> schemaNames,
    Map<String, Map<String, Object?>> tables, {
    Map<String, Map<String, Object?>> enums = const {},
  }) {
    final columns = (table['columns']! as List<Object?>).cast<Map<String, Object?>>();
    final buffer = StringBuffer()
      ..writeln(
        'CREATE TABLE ${_quote(schemaNames[table['schemaId']]!)}.'
        '${_quote(table['name']! as String)} (',
      );
    final definitions = <String>[];
    for (final column in columns) {
      final storage = column['storage']! as Map<String, Object?>;
      definitions.add(
        '  ${_quote(column['name']! as String)} ${_tursoType(storage)}'
        '${storage['nullable'] == true ? '' : ' NOT NULL'}'
        '${_defaultSql(column)}',
      );
      if (storage['kind'] == 'enum') {
        final value =
            enums[storage['enumId']] ??
            (throw const FormatException('Enum column references an unknown snapshot enum.'));
        final labels = (value['values']! as List<Object?>)
            .cast<Map<String, Object?>>()
            .map((entry) => _stringLiteral(entry['label']! as String))
            .join(', ');
        definitions.add(
          '  CHECK (${_quote(column['name']! as String)} IN ($labels))',
        );
      }
      if (storage case {'kind': 'array', 'element': final Map<String, Object?> element}
          when element['kind'] == 'enum') {
        final name = _quote(column['name']! as String);
        definitions.add(
          '  CHECK (CASE WHEN $name IS NULL THEN ${storage['nullable'] == true ? '1' : '0'} '
          "WHEN json_valid($name) THEN json_type($name) = 'array' ELSE 0 END)",
        );
      }
    }
    final columnNames = <String, String>{
      for (final currentTable in tables.values)
        for (final column
            in (currentTable['columns']! as List<Object?>).cast<Map<String, Object?>>())
          column['id']! as String: column['name']! as String,
    };
    for (final constraint in _objects(table, 'constraints')) {
      definitions.add(
        '  CONSTRAINT ${_quote(constraint['name']! as String)} '
        '${_constraintDefinition(constraint, tables, columnNames)}',
      );
    }
    buffer.writeln('${definitions.join(',\n')}\n);');
    return buffer.toString();
  }

  String _droppedObjectsSql(
    Map<String, Object?> previous,
    Map<String, Object?> next,
    Set<String> rebuiltTableIds,
  ) {
    final previousSchemas = _schemaNames(previous);
    final nextTables = _tablesById(next);
    final buffer = StringBuffer();
    for (final oldTable in _snapshotTables(previous)) {
      final nextTable = nextTables[oldTable['id']];
      if (rebuiltTableIds.contains(oldTable['id'])) continue;
      for (final constraint in _objects(oldTable, 'constraints')) {
        final replacement = nextTable == null
            ? null
            : _objects(
                nextTable,
                'constraints',
              ).where((value) => value['id'] == constraint['id']).singleOrNull;
        if (nextTable != null &&
            (replacement == null || !_sameConstraint(constraint, replacement))) {
          throw UnsupportedError('Changing Voxel constraints requires a table rebuild.');
        }
      }
      if (nextTable == null) continue;
      for (final index in _objects(oldTable, 'indexes')) {
        final replacement = _objects(
          nextTable,
          'indexes',
        ).where((value) => value['id'] == index['id']).singleOrNull;
        if (replacement == null || !_sameObject(index, replacement)) {
          buffer.writeln(
            'DROP INDEX ${_quote(previousSchemas[oldTable['schemaId']]!)}.'
            '${_quote(index['name']! as String)};',
          );
        }
      }
    }
    return buffer.toString();
  }

  String _addedObjectsSql(
    Map<String, Object?> next,
    Map<String, Object?> previous, [
    Set<String> rebuiltTableIds = const {},
  ]) {
    final schemas = _schemaNames(next);
    final tables = _tablesById(next);
    final previousTables = previous.isEmpty
        ? const <String, Map<String, Object?>>{}
        : _tablesById(previous);
    final buffer = StringBuffer();
    for (final table in tables.values) {
      if (rebuiltTableIds.contains(table['id'])) continue;
      final oldTable = previousTables[table['id']];
      for (final constraint in _objects(table, 'constraints')) {
        final old = oldTable == null
            ? null
            : _objects(
                oldTable,
                'constraints',
              ).where((value) => value['id'] == constraint['id']).singleOrNull;
        if (old != null && _sameConstraint(old, constraint)) continue;
        if (oldTable != null) {
          throw UnsupportedError('Changing Voxel constraints requires a table rebuild.');
        }
      }
      buffer.write(_indexesForTable(table, schemas, tables, oldTable: oldTable));
    }
    return buffer.toString();
  }

  String _indexesForTable(
    Map<String, Object?> table,
    Map<String, String> schemas,
    Map<String, Map<String, Object?>> tables, {
    Map<String, Object?>? oldTable,
  }) {
    final columnNames = <String, String>{
      for (final current in tables.values)
        for (final column in (current['columns']! as List<Object?>).cast<Map<String, Object?>>())
          column['id']! as String: column['name']! as String,
    };
    final buffer = StringBuffer();
    for (final index in _objects(table, 'indexes')) {
      final old = oldTable == null
          ? null
          : _objects(
              oldTable,
              'indexes',
            ).where((value) => value['id'] == index['id']).singleOrNull;
      if (old != null && _sameObject(old, index)) continue;
      if (canonicalJson(index['options']) != canonicalJson(<String, Object?>{}) ||
          canonicalJson(index['platforms']) != canonicalJson(const ['native', 'browser'])) {
        throw UnsupportedError(
          'Index ${index['name']} uses options or platforms that ordinary Voxel migrations do not support.',
        );
      }
      final unique = index['unique'] == true ? 'UNIQUE ' : '';
      final terms = [
        for (final term in (index['terms']! as List<Object?>).cast<Map<String, Object?>>())
          '${_quote(columnNames[term['columnId']]!)}${term['descending'] == true ? ' DESC' : ' ASC'}',
      ].join(', ');
      final predicate = index['predicate'] is Map<String, Object?>
          ? ' WHERE ${renderSchemaExpression(index['predicate']! as Map<String, Object?>, resolveReference: (id) => columnNames[id]!)}'
          : '';
      buffer.writeln(
        'CREATE ${unique}INDEX '
        '${_quote(schemas[table['schemaId']]!)}.${_quote(index['name']! as String)} '
        'ON ${_quote(table['name']! as String)} ($terms)$predicate;',
      );
    }
    return buffer.toString();
  }

  String _constraintDefinition(
    Map<String, Object?> constraint,
    Map<String, Map<String, Object?>> tables,
    Map<String, String> columnNames,
  ) {
    final columns = (constraint['columnIds']! as List<Object?>)
        .cast<String>()
        .map((id) => _quote(columnNames[id]!))
        .join(', ');
    final definition = switch (constraint['kind']) {
      'primaryKey' => 'PRIMARY KEY ($columns)',
      'check' =>
        'CHECK (${renderSchemaExpression(constraint['expression']! as Map<String, Object?>, resolveReference: (id) => columnNames[id]!)})',
      'foreignKey' => _foreignKeySql(constraint, tables, columnNames, columns),
      final kind => throw UnsupportedError('Voxel migrations do not support $kind constraints.'),
    };
    return definition;
  }

  String _foreignKeySql(
    Map<String, Object?> constraint,
    Map<String, Map<String, Object?>> tables,
    Map<String, String> columnNames,
    String columns,
  ) {
    final target = tables[constraint['referenceTableId']]!;
    final targetColumns = (constraint['referenceColumnIds']! as List<Object?>)
        .cast<String>()
        .map((id) => _quote(columnNames[id]!))
        .join(', ');
    return 'FOREIGN KEY ($columns) REFERENCES '
        '${_quote(target['name']! as String)} '
        '($targetColumns) ON DELETE ${_referentialAction(constraint['onDelete']! as String)} '
        'ON UPDATE ${_referentialAction(constraint['onUpdate']! as String)}';
  }

  String _referentialAction(String value) => switch (value) {
    'noAction' => 'NO ACTION',
    'restrict' => 'RESTRICT',
    'cascade' => 'CASCADE',
    'setNull' => 'SET NULL',
    'setDefault' => 'SET DEFAULT',
    _ => throw FormatException('Unknown referential action `$value`.'),
  };

  bool _sameObject(Map<String, Object?> left, Map<String, Object?> right) =>
      canonicalJson(_withoutKeysRecursively(left, {'id', 'tableId'})) ==
      canonicalJson(_withoutKeysRecursively(right, {'id', 'tableId'}));

  bool _sameConstraint(Map<String, Object?> left, Map<String, Object?> right) =>
      canonicalJson(_withoutKeysRecursively(left, {'id', 'tableId', 'name'})) ==
      canonicalJson(_withoutKeysRecursively(right, {'id', 'tableId', 'name'}));

  List<Map<String, Object?>> _snapshotTables(Map<String, Object?> snapshot) =>
      (snapshot['tables']! as List<Object?>).cast<Map<String, Object?>>();

  Map<String, Map<String, Object?>> _tablesById(Map<String, Object?> snapshot) => {
    for (final table in _snapshotTables(snapshot)) table['id']! as String: table,
  };

  Map<String, Map<String, Object?>> _enumsById(Map<String, Object?> snapshot) => {
    for (final value in (snapshot['enums']! as List<Object?>).cast<Map<String, Object?>>())
      value['id']! as String: value,
  };

  Set<String> _enumLabels(Map<String, Object?> value) => {
    for (final item in (value['values']! as List<Object?>).cast<Map<String, Object?>>())
      item['label']! as String,
  };

  bool _sameEnumLabels(Map<String, Object?> left, Map<String, Object?> right) {
    final leftLabels = _enumLabels(left).toList()..sort();
    final rightLabels = _enumLabels(right).toList()..sort();
    return canonicalJson(leftLabels) == canonicalJson(rightLabels);
  }

  bool _referencesAnyEnum(Map<String, Object?> storage, Set<String> enumIds) =>
      enumIds.contains(storage['enumId']) ||
      (storage['element'] is Map<String, Object?> &&
          _referencesAnyEnum(storage['element']! as Map<String, Object?>, enumIds));

  Map<String, String> _schemaNames(Map<String, Object?> snapshot) => {
    for (final schema in (snapshot['schemas']! as List<Object?>).cast<Map<String, Object?>>())
      schema['id']! as String: schema['name']! as String,
  };

  List<Map<String, Object?>> _objects(Map<String, Object?> table, String key) =>
      (table[key]! as List<Object?>).cast<Map<String, Object?>>();

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
    final staging = Directory('${directory.path}/.voxel-staging-$migrationId');
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

  List<Map<String, Object?>> _phases(
    Map<String, Object?> snapshot,
    String sql, {
    Set<String> rebuiltScopes = const {},
  }) {
    final ranges = _statementRanges(sql);
    final bytes = utf8.encode(sql);
    final schemas = (snapshot['schemas']! as List<Object?>).cast<Map<String, Object?>>();
    final phases = <Map<String, Object?>>[];
    for (final range in ranges) {
      final statement = utf8.decode(
        bytes.sublist(range['startByte']!, range['endByte']),
      );
      final matchingSchemas = schemas
          .where(
            (schema) => statement.contains('${_quote(schema['name']! as String)}.'),
          )
          .toList(growable: false);
      if (matchingSchemas.length != 1) {
        throw StateError('Generated Voxel SQL statement has no unique file scope.');
      }
      final scopeId = matchingSchemas.single['id'];
      if (phases.isNotEmpty && phases.last['scopeId'] == scopeId) {
        (phases.last['statements']! as List<Map<String, int>>).add(range);
        continue;
      }
      phases.add({
        'id': '${phases.length}',
        'scopeId': scopeId,
        'mode': 'transactional',
        'platforms': ['native', 'browser'],
        'statements': <Map<String, int>>[range],
        'recovery': null,
        if (rebuiltScopes.contains(matchingSchemas.single['name']))
          'rebuild': {
            'foreignKeys': 'offOutsideTransaction',
            'validations': _rebuildValidations(
              snapshot,
              matchingSchemas.single['id']! as String,
            ),
          },
      });
    }
    return phases;
  }

  List<Map<String, Object?>> _rebuildValidations(
    Map<String, Object?> snapshot,
    String schemaId,
  ) {
    final tables = _tablesById(snapshot);
    final columnNames = <String, String>{
      for (final table in tables.values)
        for (final column in (table['columns']! as List<Object?>).cast<Map<String, Object?>>())
          column['id']! as String: column['name']! as String,
    };
    final validations = <Map<String, Object?>>[];
    for (final table in tables.values.where((value) => value['schemaId'] == schemaId)) {
      for (final column in (table['columns']! as List<Object?>).cast<Map<String, Object?>>()) {
        final storage = column['storage']! as Map<String, Object?>;
        if (storage case {'kind': 'array', 'element': final Map<String, Object?> element}
            when element['kind'] == 'enum') {
          final value = _enumsById(snapshot)[element['enumId']]!;
          final labels = _enumLabels(value).map(_stringLiteral).join(', ');
          final invalidValue = element['nullable'] == true
              ? '"voxel_value".value IS NOT NULL AND "voxel_value".value NOT IN ($labels)'
              : '"voxel_value".value IS NULL OR "voxel_value".value NOT IN ($labels)';
          validations.add({
            'kind': 'enumArrayLabels',
            'tableId': table['id'],
            'columnId': column['id'],
            'sql':
                'SELECT NOT EXISTS (SELECT 1 FROM '
                '${_quote(_schemaNames(snapshot)[schemaId]!)}.${_quote(table['name']! as String)} '
                'AS "voxel_row", json_each("voxel_row".${_quote(column['name']! as String)}) '
                'AS "voxel_value" WHERE "voxel_row".${_quote(column['name']! as String)} '
                'IS NOT NULL AND ($invalidValue)) AS "valid";',
          });
        }
      }
      for (final constraint in _objects(table, 'constraints')) {
        if (constraint['kind'] != 'foreignKey') continue;
        final target = tables[constraint['referenceTableId']]!;
        if (target['schemaId'] != schemaId) {
          throw UnsupportedError(
            'Voxel table rebuilds cannot validate a cross-file foreign key.',
          );
        }
        final childIds = (constraint['columnIds']! as List<Object?>).cast<String>();
        final parentIds = (constraint['referenceColumnIds']! as List<Object?>).cast<String>();
        _requireUniqueForeignKeyTarget(target, parentIds);
        final present = childIds
            .map((id) => '"voxel_child".${_quote(columnNames[id]!)} IS NOT NULL')
            .join(' AND ');
        final matches = [
          for (var index = 0; index < childIds.length; index++)
            '"voxel_parent".${_quote(columnNames[parentIds[index]]!)} = "voxel_child".${_quote(columnNames[childIds[index]]!)}',
        ].join(' AND ');
        validations.add({
          'kind': 'foreignKeyAntiJoin',
          'tableId': table['id'],
          'constraintId': constraint['id'],
          'sql':
              'SELECT NOT EXISTS (SELECT 1 FROM '
              '${_quote(_schemaNames(snapshot)[schemaId]!)}.${_quote(table['name']! as String)} '
              'AS "voxel_child" WHERE $present AND NOT EXISTS (SELECT 1 FROM '
              '${_quote(_schemaNames(snapshot)[schemaId]!)}.${_quote(target['name']! as String)} '
              'AS "voxel_parent" WHERE $matches)) AS "valid";',
        });
      }
    }
    return validations;
  }

  void _requireUniqueForeignKeyTarget(
    Map<String, Object?> table,
    List<String> targetColumnIds,
  ) {
    final columns = (table['columns']! as List<Object?>).cast<Map<String, Object?>>();
    final inlinePrimaryKey = [
      for (final column in columns)
        if (column['primaryKey'] == true) column['id']! as String,
    ];
    final candidates = <List<String>>[
      if (inlinePrimaryKey.isNotEmpty) inlinePrimaryKey,
      for (final constraint in _objects(table, 'constraints'))
        if (constraint['kind'] == 'primaryKey')
          (constraint['columnIds']! as List<Object?>).cast<String>(),
      for (final index in _objects(table, 'indexes'))
        if (index['unique'] == true && index['predicate'] == null)
          [
            for (final term in (index['terms']! as List<Object?>).cast<Map<String, Object?>>())
              term['columnId']! as String,
          ],
    ];
    if (!candidates.any(
      (candidate) => canonicalJson(candidate) == canonicalJson(targetColumnIds),
    )) {
      throw FormatException(
        'Foreign key target ${table['name']} must have an exact primary key or unique index.',
      );
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
      throw StateError('Voxel IDs must contain 32 lowercase hexadecimal characters.');
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

  String _stringLiteral(String value) => "'${value.replaceAll("'", "''")}'";

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
