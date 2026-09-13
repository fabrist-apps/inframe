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
    Map<String, String> enumLabelTransforms = const {},
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
        enumLabelTransforms: enumLabelTransforms,
      );
    }
    if (enumLabelTransforms.isNotEmpty) {
      throw const FormatException('Enum label transforms require a previous snapshot.');
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
    for (final rawEnum in declaration['enums']! as List<Object?>) {
      final declaredEnum = rawEnum! as Map<String, Object?>;
      schemaIds.putIfAbsent(declaredEnum['schema']! as String, _nextId);
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
      'dialect': 'rivet',
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
    required Map<String, String> enumLabelTransforms,
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
    final plan = _diffPlan(previousSnapshot, snapshot, enumLabelTransforms);
    final sql = plan.sql;
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
      'phases': _phaseMetadata(plan, databaseId),
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
      'dialect': 'rivet',
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
        throw FormatException('Duplicate Rivet enum declaration $schema.$name.');
      }
      var old = previousEnums
          .where(
            (value) => previousSchemaNames[value['schemaId']] == schema && value['name'] == name,
          )
          .singleOrNull;
      if (old == null && declared['renamedFrom'] is String) {
        final renamedFrom = declared['renamedFrom']! as String;
        final candidates = previousEnums.where(
          (value) => value['name'] == renamedFrom && !usedIds.contains(value['id']),
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
          'platforms': declared['platforms'] ?? const ['postgresql'],
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
    for (final schema in schemas) {
      buffer.writeln('CREATE SCHEMA IF NOT EXISTS ${_quote(schema['name']! as String)};');
    }
    final enumTypes = _enumTypes(snapshot, schemaNames.cast<String, String>());
    for (final enumValue in (snapshot['enums']! as List<Object?>).cast<Map<String, Object?>>()) {
      final labels = (enumValue['values']! as List<Object?>)
          .cast<Map<String, Object?>>()
          .map((value) => _stringLiteral(value['label']! as String))
          .join(', ');
      buffer.writeln('CREATE TYPE ${enumTypes[enumValue['id']]} AS ENUM ($labels);');
    }
    for (final table in (snapshot['tables']! as List<Object?>).cast<Map<String, Object?>>()) {
      buffer.write(_createTableSql(table, schemaNames.cast<String, String>(), enumTypes));
    }
    buffer.write(_addedObjectsSql(snapshot, const {}));
    return buffer.toString();
  }

  String _postgresType(
    Map<String, Object?> storage, [
    Map<String, String> enumTypes = const {},
  ]) => switch (storage['kind']) {
    'text' => 'text',
    'integer' => 'int4',
    'real' => 'float8',
    'boolean' => 'bool',
    'dateTime' => 'timestamptz(3)',
    'json' => 'jsonb',
    'enum' =>
      enumTypes[storage['enumId']] ??
          (throw const FormatException('Enum storage references an unknown type.')),
    'array' => '${_postgresType(storage['element']! as Map<String, Object?>, enumTypes)}[]',
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
    final nextEnumTypes = _enumTypes(next, nextSchemas);
    final buffer = StringBuffer()..write(_droppedObjectsSql(previous, next));
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
        buffer.write(_createTableSql(nextTable, nextSchemas, nextEnumTypes));
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
      _writeColumnDiff(buffer, qualifiedTable, previousTable, nextTable, nextEnumTypes);
    }
    buffer.write(_addedObjectsSql(next, previous));
    return buffer.toString();
  }

  _MigrationPlan _diffPlan(
    Map<String, Object?> previous,
    Map<String, Object?> next,
    Map<String, String> enumLabelTransforms,
  ) {
    final phases = <String>[];
    final enumChanges = _enumChangeSql(previous, next, enumLabelTransforms);
    if (enumChanges.ordinary.isNotEmpty) phases.add(enumChanges.ordinary);
    phases.addAll(enumChanges.additions.where((sql) => sql.isNotEmpty));
    final ordinary = _diffSql(previous, next);
    if (ordinary.isNotEmpty) phases.add(ordinary);
    return _MigrationPlan(phases);
  }

  ({String ordinary, List<String> additions}) _enumChangeSql(
    Map<String, Object?> previous,
    Map<String, Object?> next,
    Map<String, String> enumLabelTransforms,
  ) {
    final previousSchemas = _schemaNames(previous);
    final nextSchemas = _schemaNames(next);
    final oldEnums = {
      for (final value in (previous['enums']! as List<Object?>).cast<Map<String, Object?>>())
        value['id']! as String: value,
    };
    final newEnums = {
      for (final value in (next['enums']! as List<Object?>).cast<Map<String, Object?>>())
        value['id']! as String: value,
    };
    final ordinary = StringBuffer();
    final additions = <String>[];
    final usedTransforms = <String>{};
    for (final entry in newEnums.entries) {
      final nextEnum = entry.value;
      final oldEnum = oldEnums[entry.key];
      final nextQualified =
          '${_quote(nextSchemas[nextEnum['schemaId']]!)}.'
          '${_quote(nextEnum['name']! as String)}';
      if (oldEnum == null) {
        final labels = (nextEnum['values']! as List<Object?>)
            .cast<Map<String, Object?>>()
            .map((value) => _stringLiteral(value['label']! as String))
            .join(', ');
        ordinary.writeln('CREATE TYPE $nextQualified AS ENUM ($labels);');
        continue;
      }
      final oldSchema = previousSchemas[oldEnum['schemaId']]!;
      final nextSchema = nextSchemas[nextEnum['schemaId']]!;
      var currentQualified = '${_quote(oldSchema)}.${_quote(oldEnum['name']! as String)}';
      if (oldSchema != nextSchema) {
        ordinary
          ..writeln('CREATE SCHEMA IF NOT EXISTS ${_quote(nextSchema)};')
          ..writeln('ALTER TYPE $currentQualified SET SCHEMA ${_quote(nextSchema)};');
        currentQualified = '${_quote(nextSchema)}.${_quote(oldEnum['name']! as String)}';
      }
      if (oldEnum['name'] != nextEnum['name']) {
        ordinary.writeln(
          'ALTER TYPE $currentQualified RENAME TO ${_quote(nextEnum['name']! as String)};',
        );
      }
      final oldValues = {
        for (final value in (oldEnum['values']! as List<Object?>).cast<Map<String, Object?>>())
          value['id']! as String: value,
      };
      final nextValues = (nextEnum['values']! as List<Object?>).cast<Map<String, Object?>>();
      final nextIds = nextValues.map((value) => value['id']! as String).toList(growable: false);
      final retainedOldIds = (oldEnum['values']! as List<Object?>)
          .cast<Map<String, Object?>>()
          .map((value) => value['id']! as String)
          .where(nextIds.contains)
          .toList(growable: false);
      final retainedNextIds = nextIds.where(oldValues.containsKey).toList(growable: false);
      final removed = oldValues.keys.where((id) => !nextIds.contains(id));
      final reordered = canonicalJson(retainedOldIds) != canonicalJson(retainedNextIds);
      if (reordered || removed.isNotEmpty) {
        ordinary.write(
          _enumRebuildSql(
            previous,
            next,
            oldEnum,
            nextEnum,
            enumLabelTransforms,
            usedTransforms,
          ),
        );
        continue;
      }
      for (final value in nextValues) {
        final oldValue = oldValues[value['id']];
        if (oldValue != null && oldValue['label'] != value['label']) {
          ordinary.writeln(
            'ALTER TYPE $nextQualified RENAME VALUE ${_stringLiteral(oldValue['label']! as String)} '
            'TO ${_stringLiteral(value['label']! as String)};',
          );
        }
      }
      final availableIds = oldValues.keys.toSet();
      for (var index = 0; index < nextValues.length; index++) {
        final value = nextValues[index];
        final id = value['id']! as String;
        if (availableIds.contains(id)) continue;
        final following = nextValues
            .skip(index + 1)
            .where(
              (candidate) => availableIds.contains(candidate['id']),
            );
        final position = following.isNotEmpty
            ? ' BEFORE ${_stringLiteral(following.first['label']! as String)}'
            : index > 0
            ? ' AFTER ${_stringLiteral(nextValues[index - 1]['label']! as String)}'
            : '';
        additions.add(
          'ALTER TYPE $nextQualified ADD VALUE ${_stringLiteral(value['label']! as String)}$position;\n',
        );
        availableIds.add(id);
      }
    }
    final unusedTransforms = enumLabelTransforms.keys.where((key) => !usedTransforms.contains(key));
    if (unusedTransforms.isNotEmpty) {
      throw FormatException('Unused enum label transforms: ${unusedTransforms.join(', ')}.');
    }
    return (ordinary: ordinary.toString(), additions: additions);
  }

  String _enumRebuildSql(
    Map<String, Object?> previous,
    Map<String, Object?> next,
    Map<String, Object?> oldEnum,
    Map<String, Object?> nextEnum,
    Map<String, String> transforms,
    Set<String> usedTransforms,
  ) {
    final previousSchemas = _schemaNames(previous);
    final nextSchemas = _schemaNames(next);
    final oldSchema = previousSchemas[oldEnum['schemaId']]!;
    final nextSchema = nextSchemas[nextEnum['schemaId']]!;
    final oldQualified = '${_quote(oldSchema)}.${_quote(oldEnum['name']! as String)}';
    final temporaryName = '__rivet_${(nextEnum['id']! as String).substring(0, 12)}';
    final temporaryQualified = '${_quote(nextSchema)}.${_quote(temporaryName)}';
    final oldValues = {
      for (final value in (oldEnum['values']! as List<Object?>).cast<Map<String, Object?>>())
        value['id']! as String: value['label']! as String,
    };
    final nextValues = {
      for (final value in (nextEnum['values']! as List<Object?>).cast<Map<String, Object?>>())
        value['id']! as String: value['label']! as String,
    };
    final nextLabels = nextValues.values.toSet();
    final affectedColumns =
        <String, ({Map<String, Object?> table, Map<String, Object?> column, bool array})>{};
    for (final table in _snapshotTables(next)) {
      for (final column in (table['columns']! as List<Object?>).cast<Map<String, Object?>>()) {
        final storage = column['storage']! as Map<String, Object?>;
        final array =
            storage['kind'] == 'array' &&
            (storage['element']! as Map<String, Object?>)['enumId'] == nextEnum['id'];
        if (storage['enumId'] == nextEnum['id'] || array) {
          affectedColumns[column['id']! as String] = (table: table, column: column, array: array);
        }
      }
    }
    final affectedIds = affectedColumns.keys.toSet();
    final dependentConstraints = <({Map<String, Object?> table, Map<String, Object?> object})>[];
    final dependentIndexes = <({Map<String, Object?> table, Map<String, Object?> object})>[];
    for (final table in _snapshotTables(next)) {
      for (final constraint in _objects(table, 'constraints')) {
        if (_containsAny(constraint, affectedIds)) {
          dependentConstraints.add((table: table, object: constraint));
        }
      }
      for (final index in _objects(table, 'indexes')) {
        if (_containsAny(index, affectedIds)) dependentIndexes.add((table: table, object: index));
      }
    }
    final buffer = StringBuffer();
    if (oldSchema != nextSchema) {
      buffer.writeln('CREATE SCHEMA IF NOT EXISTS ${_quote(nextSchema)};');
    }
    final labels = (nextEnum['values']! as List<Object?>)
        .cast<Map<String, Object?>>()
        .map((value) => _stringLiteral(value['label']! as String))
        .join(', ');
    buffer.writeln('CREATE TYPE $temporaryQualified AS ENUM ($labels);');
    for (final entry in oldValues.entries) {
      final nextLabel = nextValues[entry.key];
      if (nextLabel != null && nextLabel != entry.value) {
        buffer.writeln(
          'ALTER TYPE $oldQualified RENAME VALUE ${_stringLiteral(entry.value)} '
          'TO ${_stringLiteral(nextLabel)};',
        );
        oldValues[entry.key] = nextLabel;
      }
    }
    final nextTables = _tablesById(next);
    final columnNames = <String, String>{
      for (final table in nextTables.values)
        for (final column in (table['columns']! as List<Object?>).cast<Map<String, Object?>>())
          column['id']! as String: column['name']! as String,
    };
    for (final dependency in dependentConstraints) {
      buffer.writeln(
        'ALTER TABLE ${_qualifiedTable(dependency.table, nextSchemas)} DROP CONSTRAINT '
        '${_quote(dependency.object['name']! as String)};',
      );
    }
    for (final dependency in dependentIndexes) {
      buffer.writeln(
        'DROP INDEX ${_quote(nextSchemas[dependency.table['schemaId']]!)}.'
        '${_quote(dependency.object['name']! as String)};',
      );
    }
    for (final dependency in affectedColumns.values) {
      if (dependency.column['default'] != null) {
        buffer.writeln(
          'ALTER TABLE ${_qualifiedTable(dependency.table, nextSchemas)} ALTER COLUMN '
          '${_quote(dependency.column['name']! as String)} DROP DEFAULT;',
        );
      }
    }
    for (final removed in oldValues.entries.where((entry) => !nextValues.containsKey(entry.key))) {
      final key = '$nextSchema.${nextEnum['name']}.${removed.value}';
      final replacement = transforms[key];
      if (replacement == null || !nextLabels.contains(replacement)) {
        throw FormatException(
          'Removing enum label ${removed.value} requires --enum-transform '
          '$key=<retained-label>.',
        );
      }
      usedTransforms.add(key);
      for (final dependency in affectedColumns.values) {
        final table = _qualifiedTable(dependency.table, nextSchemas);
        final column = _quote(dependency.column['name']! as String);
        if (dependency.array) {
          buffer.writeln(
            'UPDATE $table SET $column = array_replace($column, '
            '${_stringLiteral(removed.value)}::$oldQualified, '
            '${_stringLiteral(replacement)}::$oldQualified) '
            'WHERE $column @> ARRAY[${_stringLiteral(removed.value)}::$oldQualified];',
          );
        } else {
          buffer.writeln(
            'UPDATE $table SET $column = ${_stringLiteral(replacement)}::$oldQualified '
            'WHERE $column = ${_stringLiteral(removed.value)}::$oldQualified;',
          );
        }
      }
    }
    for (final dependency in affectedColumns.values) {
      final table = _qualifiedTable(dependency.table, nextSchemas);
      final column = _quote(dependency.column['name']! as String);
      final targetType = dependency.array ? '$temporaryQualified[]' : temporaryQualified;
      final textType = dependency.array ? 'text[]' : 'text';
      buffer.writeln(
        'ALTER TABLE $table ALTER COLUMN $column TYPE $targetType '
        'USING $column::$textType::$targetType;',
      );
    }
    buffer
      ..writeln('DROP TYPE $oldQualified;')
      ..writeln('ALTER TYPE $temporaryQualified RENAME TO ${_quote(nextEnum['name']! as String)};');
    for (final dependency in affectedColumns.values) {
      if (dependency.column['default'] != null) {
        buffer.writeln(
          'ALTER TABLE ${_qualifiedTable(dependency.table, nextSchemas)} ALTER COLUMN '
          '${_quote(dependency.column['name']! as String)} SET'
          '${_defaultSql(dependency.column)};',
        );
      }
    }
    for (final dependency in dependentConstraints.where(
      (dependency) => dependency.object['kind'] != 'foreignKey',
    )) {
      buffer.writeln(
        _addConstraintSql(
          _qualifiedTable(dependency.table, nextSchemas),
          dependency.object,
          nextTables,
          nextSchemas,
          columnNames,
        ),
      );
    }
    for (final dependency in dependentIndexes) {
      buffer.writeln(
        _createIndexSql(
          _qualifiedTable(dependency.table, nextSchemas),
          dependency.object,
          columnNames,
        ),
      );
    }
    for (final dependency in dependentConstraints.where(
      (dependency) => dependency.object['kind'] == 'foreignKey',
    )) {
      buffer.writeln(
        _addConstraintSql(
          _qualifiedTable(dependency.table, nextSchemas),
          dependency.object,
          nextTables,
          nextSchemas,
          columnNames,
        ),
      );
    }
    return buffer.toString();
  }

  bool _containsAny(Object? value, Set<String> ids) => switch (value) {
    final String string => ids.contains(string),
    final List<Object?> list => list.any((item) => _containsAny(item, ids)),
    final Map<String, Object?> map => map.values.any((item) => _containsAny(item, ids)),
    _ => false,
  };

  String _qualifiedTable(Map<String, Object?> table, Map<String, String> schemas) =>
      '${_quote(schemas[table['schemaId']]!)}.${_quote(table['name']! as String)}';

  List<Map<String, Object?>> _phaseMetadata(_MigrationPlan plan, String databaseId) {
    var byteOffset = 0;
    final phases = <Map<String, Object?>>[];
    for (final (index, phaseSql) in plan.phases.indexed) {
      final ranges = [
        for (final range in _statementRanges(phaseSql))
          {
            'startByte': range['startByte']! + byteOffset,
            'endByte': range['endByte']! + byteOffset,
          },
      ];
      phases.add({
        'id': '$index',
        'scopeId': databaseId,
        'mode': 'transactional',
        'platforms': ['postgresql'],
        'statements': ranges,
        'recovery': null,
      });
      byteOffset += utf8.encode(phaseSql).length;
    }
    return phases;
  }

  void _writeColumnDiff(
    StringBuffer buffer,
    String qualifiedTable,
    Map<String, Object?> previousTable,
    Map<String, Object?> nextTable,
    Map<String, String> enumTypes,
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
          '${_postgresType(storage, enumTypes)}${_defaultSql(nextColumn)}'
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
        final type = _postgresType(newStorage, enumTypes);
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
    Map<String, String> enumTypes,
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
        '  ${_quote(column['name']! as String)} ${_postgresType(storage, enumTypes)}'
        '${storage['nullable'] == true ? '' : ' NOT NULL'}'
        '${_defaultSql(column)}${index == columns.length - 1 ? '' : ','}',
      );
    }
    return (buffer..writeln(');')).toString();
  }

  String _droppedObjectsSql(
    Map<String, Object?> previous,
    Map<String, Object?> next,
  ) {
    final previousSchemas = _schemaNames(previous);
    final nextTables = _tablesById(next);
    final buffer = StringBuffer();
    for (final oldTable in _snapshotTables(previous)) {
      final nextTable = nextTables[oldTable['id']];
      final qualified =
          '${_quote(previousSchemas[oldTable['schemaId']]!)}.'
          '${_quote(oldTable['name']! as String)}';
      for (final constraint in _objects(oldTable, 'constraints')) {
        final replacement = nextTable == null
            ? null
            : _objects(
                nextTable,
                'constraints',
              ).where((value) => value['id'] == constraint['id']).singleOrNull;
        if (nextTable == null || replacement == null || !_sameObject(constraint, replacement)) {
          buffer.writeln(
            'ALTER TABLE $qualified DROP CONSTRAINT ${_quote(constraint['name']! as String)};',
          );
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
    Map<String, Object?> previous,
  ) {
    final schemas = _schemaNames(next);
    final tables = _tablesById(next);
    final previousTables = previous.isEmpty
        ? const <String, Map<String, Object?>>{}
        : _tablesById(previous);
    final columnNames = <String, String>{};
    for (final table in tables.values) {
      for (final column in (table['columns']! as List<Object?>).cast<Map<String, Object?>>()) {
        columnNames[column['id']! as String] = column['name']! as String;
      }
    }
    final buffer = StringBuffer();
    final foreignKeys = StringBuffer();
    for (final table in tables.values) {
      final oldTable = previousTables[table['id']];
      final qualified =
          '${_quote(schemas[table['schemaId']]!)}.${_quote(table['name']! as String)}';
      for (final constraint in _objects(table, 'constraints')) {
        final old = oldTable == null
            ? null
            : _objects(
                oldTable,
                'constraints',
              ).where((value) => value['id'] == constraint['id']).singleOrNull;
        if (old != null && _sameObject(old, constraint)) continue;
        (constraint['kind'] == 'foreignKey' ? foreignKeys : buffer).writeln(
          _addConstraintSql(qualified, constraint, tables, schemas, columnNames),
        );
      }
      for (final index in _objects(table, 'indexes')) {
        final old = oldTable == null
            ? null
            : _objects(
                oldTable,
                'indexes',
              ).where((value) => value['id'] == index['id']).singleOrNull;
        if (old != null && _sameObject(old, index)) continue;
        if (canonicalJson(index['options']) != canonicalJson(<String, Object?>{}) ||
            canonicalJson(index['platforms']) != canonicalJson(const ['postgresql'])) {
          throw UnsupportedError(
            'Index ${index['name']} uses options or platforms that ordinary Rivet migrations do not support.',
          );
        }
        buffer.writeln(_createIndexSql(qualified, index, columnNames));
      }
    }
    return '$buffer$foreignKeys';
  }

  String _createIndexSql(
    String qualified,
    Map<String, Object?> index,
    Map<String, String> columnNames,
  ) {
    final unique = index['unique'] == true ? 'UNIQUE ' : '';
    final terms = [
      for (final term in (index['terms']! as List<Object?>).cast<Map<String, Object?>>())
        '${_quote(columnNames[term['columnId']]!)}${term['descending'] == true ? ' DESC' : ' ASC'}',
    ].join(', ');
    final predicate = index['predicate'] is Map<String, Object?>
        ? ' WHERE ${renderSchemaExpression(index['predicate']! as Map<String, Object?>, resolveReference: (id) => columnNames[id]!)}'
        : '';
    return 'CREATE ${unique}INDEX ${_quote(index['name']! as String)} '
        'ON $qualified ($terms)$predicate;';
  }

  String _addConstraintSql(
    String qualified,
    Map<String, Object?> constraint,
    Map<String, Map<String, Object?>> tables,
    Map<String, String> schemas,
    Map<String, String> columnNames,
  ) {
    final name = _quote(constraint['name']! as String);
    final columns = (constraint['columnIds']! as List<Object?>)
        .cast<String>()
        .map((id) => _quote(columnNames[id]!))
        .join(', ');
    final definition = switch (constraint['kind']) {
      'primaryKey' => 'PRIMARY KEY ($columns)',
      'check' =>
        'CHECK (${renderSchemaExpression(constraint['expression']! as Map<String, Object?>, resolveReference: (id) => columnNames[id]!)})',
      'foreignKey' => _foreignKeySql(constraint, tables, schemas, columnNames, columns),
      final kind => throw UnsupportedError('Rivet migrations do not support $kind constraints.'),
    };
    return 'ALTER TABLE $qualified ADD CONSTRAINT $name $definition;';
  }

  String _foreignKeySql(
    Map<String, Object?> constraint,
    Map<String, Map<String, Object?>> tables,
    Map<String, String> schemas,
    Map<String, String> columnNames,
    String columns,
  ) {
    final target = tables[constraint['referenceTableId']]!;
    final targetColumns = (constraint['referenceColumnIds']! as List<Object?>)
        .cast<String>()
        .map((id) => _quote(columnNames[id]!))
        .join(', ');
    return 'FOREIGN KEY ($columns) REFERENCES '
        '${_quote(schemas[target['schemaId']]!)}.${_quote(target['name']! as String)} '
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

  List<Map<String, Object?>> _snapshotTables(Map<String, Object?> snapshot) =>
      (snapshot['tables']! as List<Object?>).cast<Map<String, Object?>>();

  Map<String, Map<String, Object?>> _tablesById(Map<String, Object?> snapshot) => {
    for (final table in _snapshotTables(snapshot)) table['id']! as String: table,
  };

  Map<String, String> _schemaNames(Map<String, Object?> snapshot) => {
    for (final schema in (snapshot['schemas']! as List<Object?>).cast<Map<String, Object?>>())
      schema['id']! as String: schema['name']! as String,
  };

  Map<String, String> _enumTypes(
    Map<String, Object?> snapshot,
    Map<String, String> schemaNames,
  ) => {
    for (final value in (snapshot['enums']! as List<Object?>).cast<Map<String, Object?>>())
      value['id']! as String:
          '${_quote(schemaNames[value['schemaId']]!)}.${_quote(value['name']! as String)}',
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

final class _MigrationPlan {
  const _MigrationPlan(this.phases);

  final List<String> phases;
  String get sql => phases.join();
}
