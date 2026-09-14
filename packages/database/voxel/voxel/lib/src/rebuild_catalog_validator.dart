// This validator is internal to migration initialization.
// ignore_for_file: public_member_api_docs

typedef VoxelCatalogQuery = Future<List<Map<String, Object?>>> Function(String sql);

enum VoxelRebuildCatalogMismatch { missingTable, unmanagedDependency, structure }

final class VoxelRebuildCatalogException implements Exception {
  const VoxelRebuildCatalogException({
    required this.kind,
    required this.scopeName,
    required this.objectName,
  });

  final VoxelRebuildCatalogMismatch kind;
  final String scopeName;
  final String objectName;

  @override
  String toString() =>
      'Voxel rebuild precondition failed for ${_displayIdentifier(scopeName)}.'
      '${_displayIdentifier(objectName)}: ${kind.name}.';
}

final class VoxelRebuildCatalogValidator {
  const VoxelRebuildCatalogValidator();

  /// Verifies the target catalog before the caller disables foreign keys.
  ///
  /// [previousSnapshot] must be the snapshot immediately before the migration.
  /// [query] must use the connection reserved for the entire rebuild sequence.
  Future<void> validate({
    required String scopeName,
    required Map<String, Object?> rebuild,
    required Map<String, Object?> previousSnapshot,
    required VoxelCatalogQuery query,
  }) async {
    final catalog = await query(
      'SELECT type, name, tbl_name, sql FROM ${_quote(scopeName)}.sqlite_schema '
      "WHERE type IN ('table', 'index', 'trigger', 'view') ORDER BY type, name",
    );
    for (final rawTable in _list(rebuild['tables'])) {
      final table = _map(rawTable);
      await _validateTable(scopeName, table, previousSnapshot, catalog, query);
    }
  }

  /// Verifies the rebuilt scope and every final foreign-key target before commit.
  Future<void> validateFinalScope({
    required String scopeName,
    required String scopeId,
    required Map<String, Object?> snapshot,
    required VoxelCatalogQuery query,
  }) async {
    final catalog = await query(
      'SELECT type, name, tbl_name, sql FROM ${_quote(scopeName)}.sqlite_schema '
      "WHERE type IN ('table', 'index') ORDER BY type, name",
    );
    for (final table in _list(snapshot['tables']).map(_map)) {
      if (table['schemaId'] != scopeId) continue;
      final tableName = table['name']! as String;
      final tableSql = catalog
          .where(
            (row) =>
                row['type'] == 'table' &&
                (row['name'] as String?)?.toLowerCase() == tableName.toLowerCase(),
          )
          .singleOrNull?['sql'];
      if (tableSql is! String) _structureFailure(scopeName, tableName);
      await _validateColumns(scopeName, tableName, table, query);
      await _validateForeignKeys(scopeName, tableName, table, snapshot, query);
      await _validateIndexes(scopeName, tableName, table, catalog, query);
      _validateChecks(scopeName, tableName, table, snapshot, tableSql);
    }
    await _validateForeignKeyTargets(scopeName, scopeId, snapshot, query);
  }

  Future<void> _validateTable(
    String scopeName,
    Map<String, Object?> rebuildTable,
    Map<String, Object?> previousSnapshot,
    List<Map<String, Object?>> catalog,
    VoxelCatalogQuery query,
  ) async {
    final oldName = rebuildTable['oldName']! as String;
    final expected = _map(rebuildTable['expectedBefore']);
    final previousTable = _list(previousSnapshot['tables'])
        .map(_map)
        .where((table) => table['id'] == rebuildTable['tableId'])
        .singleOrNull;
    if (previousTable == null || !_sameJsonValue(previousTable, expected)) {
      _structureFailure(scopeName, oldName);
    }
    final tableRows = catalog.where(
      (row) =>
          row['type'] == 'table' &&
          (row['name'] as String?)?.toLowerCase() == oldName.toLowerCase(),
    );
    if (tableRows.length != 1) {
      throw VoxelRebuildCatalogException(
        kind: VoxelRebuildCatalogMismatch.missingTable,
        scopeName: scopeName,
        objectName: oldName,
      );
    }
    final tableSql = tableRows.single['sql'];
    if (tableSql is! String) _structureFailure(scopeName, oldName);

    _validateDependencies(scopeName, oldName, rebuildTable, catalog);
    await _validateColumns(scopeName, oldName, expected, query);
    await _validateForeignKeys(scopeName, oldName, expected, previousSnapshot, query);
    await _validateIndexes(scopeName, oldName, expected, catalog, query);
    _validateChecks(scopeName, oldName, expected, previousSnapshot, tableSql);
  }

  void _validateDependencies(
    String scopeName,
    String tableName,
    Map<String, Object?> rebuildTable,
    List<Map<String, Object?>> catalog,
  ) {
    final managedIndexes = {
      for (final raw in _list(rebuildTable['managedDependencies']))
        if (_map(raw)['kind'] == 'index') (_map(raw)['name']! as String).toLowerCase(),
    };
    for (final row in catalog) {
      final type = row['type'];
      final name = row['name'];
      if (name is! String) continue;
      if (type == 'index' &&
          (row['tbl_name'] as String?)?.toLowerCase() == tableName.toLowerCase()) {
        if (name.startsWith('sqlite_autoindex_') || managedIndexes.contains(name.toLowerCase())) {
          continue;
        }
        _dependencyFailure(scopeName, name);
      }
      if (type == 'trigger' &&
          (row['tbl_name'] as String?)?.toLowerCase() == tableName.toLowerCase()) {
        _dependencyFailure(scopeName, name);
      }
      if (type == 'view') {
        final sql = row['sql'];
        if (sql is String && _referencedTables(sql).contains(tableName.toLowerCase())) {
          _dependencyFailure(scopeName, name);
        }
      }
    }
  }

  Future<void> _validateColumns(
    String scopeName,
    String tableName,
    Map<String, Object?> expected,
    VoxelCatalogQuery query,
  ) async {
    final actual = await query(_pragma(scopeName, 'table_info', tableName));
    final constraints = _list(expected['constraints']).map(_map).toList(growable: false);
    final primaryKey = constraints
        .where((constraint) => constraint['kind'] == 'primaryKey')
        .singleOrNull;
    final primaryKeyPositions = <String, int>{
      if (primaryKey != null)
        for (final (position, id) in _list(primaryKey['columnIds']).cast<String>().indexed)
          id: position + 1,
    };
    final expectedColumns = _list(expected['columns']).map(_map).toList(growable: false);
    if (actual.length != expectedColumns.length) _structureFailure(scopeName, tableName);
    for (var index = 0; index < expectedColumns.length; index++) {
      final column = expectedColumns[index];
      final live = actual[index];
      final storage = _map(column['storage']);
      final rawExpectedDefault = column['default'];
      final expectedDefault = rawExpectedDefault is Map<String, Object?>
          ? _normalizeSql(_renderExpression(rawExpectedDefault, expectedColumns))
          : null;
      final rawLiveDefault = live['dflt_value'];
      final liveDefault = rawLiveDefault is String ? _normalizeSql(rawLiveDefault) : null;
      if (_integer(live['cid']) != index ||
          (live['name'] as String?)?.toLowerCase() != (column['name']! as String).toLowerCase() ||
          (live['type'] as String?)?.toUpperCase() != _storageType(storage) ||
          (_integer(live['notnull']) == 1) != (storage['nullable'] != true) ||
          liveDefault != expectedDefault ||
          _integer(live['pk']) != (primaryKeyPositions[column['id']] ?? 0)) {
        _structureFailure(scopeName, tableName);
      }
    }
  }

  Future<void> _validateForeignKeys(
    String scopeName,
    String tableName,
    Map<String, Object?> expected,
    Map<String, Object?> previousSnapshot,
    VoxelCatalogQuery query,
  ) async {
    final tables = {
      for (final raw in _list(previousSnapshot['tables'])) _map(raw)['id']! as String: _map(raw),
    };
    final columns = <String, String>{
      for (final table in tables.values)
        for (final raw in _list(table['columns']))
          _map(raw)['id']! as String: _map(raw)['name']! as String,
    };
    final expectedForeignKeys = <String>[];
    for (final constraint in _list(expected['constraints']).map(_map)) {
      if (constraint['kind'] != 'foreignKey') continue;
      final local = _list(constraint['columnIds']).cast<String>();
      final remote = _list(constraint['referenceColumnIds']).cast<String>();
      final target = tables[constraint['referenceTableId']]!;
      for (var index = 0; index < local.length; index++) {
        expectedForeignKeys.add(
          '${columns[local[index]]!.toLowerCase()}|${(target['name']! as String).toLowerCase()}|'
          '${columns[remote[index]]!.toLowerCase()}|'
          '${_action(constraint['onUpdate'])}|${_action(constraint['onDelete'])}',
        );
      }
    }
    final actualForeignKeys = <String>[];
    for (final row in await query(_pragma(scopeName, 'foreign_key_list', tableName))) {
      actualForeignKeys.add(
        '${(row['from']! as String).toLowerCase()}|${(row['table']! as String).toLowerCase()}|'
        '${(row['to']! as String).toLowerCase()}|${row['on_update']}|${row['on_delete']}',
      );
    }
    expectedForeignKeys.sort();
    actualForeignKeys.sort();
    if (!_sameList(expectedForeignKeys, actualForeignKeys)) {
      _structureFailure(scopeName, tableName);
    }
  }

  Future<void> _validateIndexes(
    String scopeName,
    String tableName,
    Map<String, Object?> expected,
    List<Map<String, Object?>> catalog,
    VoxelCatalogQuery query,
  ) async {
    final expectedColumns = {
      for (final raw in _list(expected['columns']))
        _map(raw)['id']! as String: _map(raw)['name']! as String,
    };
    final liveIndexes = {
      for (final row in await query(_pragma(scopeName, 'index_list', tableName)))
        (row['name']! as String).toLowerCase(): row,
    };
    for (final index in _list(expected['indexes']).map(_map)) {
      final name = index['name']! as String;
      final live = liveIndexes[name.toLowerCase()];
      if (live == null ||
          (_integer(live['unique']) == 1) != (index['unique'] == true) ||
          (_integer(live['partial']) == 1) != index.containsKey('predicate')) {
        _structureFailure(scopeName, name);
      }
      final terms = [
        for (final row in await query(_pragma(scopeName, 'index_xinfo', name)))
          if (_integer(row['key']) == 1)
            (
              name: row['name'],
              descending: _integer(row['desc']) == 1,
              collation: (row['coll'] as String?)?.toUpperCase(),
            ),
      ];
      final expectedTerms = _list(index['terms']).map(_map).toList(growable: false);
      if (terms.length != expectedTerms.length) _structureFailure(scopeName, name);
      for (var position = 0; position < expectedTerms.length; position++) {
        final expectedTerm = expectedTerms[position];
        final liveTerm = terms[position];
        if ((liveTerm.name as String?)?.toLowerCase() !=
                expectedColumns[expectedTerm['columnId']]!.toLowerCase() ||
            liveTerm.descending != (expectedTerm['descending'] == true) ||
            liveTerm.collation != 'BINARY') {
          _structureFailure(scopeName, name);
        }
      }
      if (index['predicate'] case final Map<String, Object?> predicate) {
        final sql = catalog
            .where(
              (row) =>
                  row['type'] == 'index' &&
                  (row['name'] as String?)?.toLowerCase() == name.toLowerCase(),
            )
            .singleOrNull?['sql'];
        final expectedPredicate = _normalizeSql(
          _renderExpression(predicate, _list(expected['columns']).map(_map).toList()),
        );
        if (sql is! String || !_normalizeSql(sql).contains('where$expectedPredicate')) {
          _structureFailure(scopeName, name);
        }
      }
    }
  }

  void _validateChecks(
    String scopeName,
    String tableName,
    Map<String, Object?> expected,
    Map<String, Object?> previousSnapshot,
    String tableSql,
  ) {
    final columns = _list(expected['columns']).map(_map).toList(growable: false);
    final normalizedTableSql = _normalizeSql(tableSql);
    final enums = {
      for (final raw in _list(previousSnapshot['enums'] ?? const <Object?>[]))
        _map(raw)['id']! as String: _map(raw),
    };
    for (final column in columns) {
      final storage = _map(column['storage']);
      final columnName = _quote(column['name']! as String);
      if (storage['kind'] == 'enum') {
        final value = enums[storage['enumId']];
        if (value == null) _structureFailure(scopeName, tableName);
        final labels = _list(value['values'])
            .map(_map)
            .map((entry) => _stringLiteral(entry['label']! as String))
            .join(', ');
        final check = _normalizeSql('CHECK ($columnName IN ($labels))');
        if (!normalizedTableSql.contains(check)) _structureFailure(scopeName, tableName);
      }
      if (storage['kind'] == 'array') {
        final nullableResult = storage['nullable'] == true ? '1' : '0';
        final check = _normalizeSql(
          'CHECK (CASE WHEN $columnName IS NULL THEN $nullableResult '
          "WHEN json_valid($columnName) THEN json_type($columnName) = 'array' ELSE 0 END)",
        );
        if (!normalizedTableSql.contains(check)) _structureFailure(scopeName, tableName);
      }
    }
    for (final constraint in _list(expected['constraints']).map(_map)) {
      if (constraint['kind'] != 'check') continue;
      final name = _normalizeSql(_quote(constraint['name']! as String));
      final expression = _normalizeSql(
        _renderExpression(_map(constraint['expression']), columns),
      );
      if (!normalizedTableSql.contains('constraint${name}check($expression)')) {
        _structureFailure(scopeName, constraint['name']! as String);
      }
    }
  }

  Future<void> _validateForeignKeyTargets(
    String scopeName,
    Object? scopeId,
    Map<String, Object?> snapshot,
    VoxelCatalogQuery query,
  ) async {
    final tables = {
      for (final raw in _list(snapshot['tables'])) _map(raw)['id']! as String: _map(raw),
    };
    for (final child in tables.values.where((table) => table['schemaId'] == scopeId)) {
      for (final constraint in _list(child['constraints']).map(_map)) {
        if (constraint['kind'] != 'foreignKey') continue;
        final target = tables[constraint['referenceTableId']]!;
        if (target['schemaId'] != scopeId) _structureFailure(scopeName, child['name']! as String);
        final targetColumns = _list(constraint['referenceColumnIds']).cast<String>();
        final primaryKey = _list(target['constraints'])
            .map(_map)
            .where((value) => value['kind'] == 'primaryKey')
            .singleOrNull;
        if (primaryKey != null && _sameObjectList(_list(primaryKey['columnIds']), targetColumns)) {
          await _validatePrimaryKeyCollations(scopeName, target, query);
          continue;
        }
        final uniqueIndex = _list(target['indexes']).map(_map).where((index) {
          if (index['unique'] != true || index.containsKey('predicate')) return false;
          return _sameObjectList(
            _list(index['terms']).map((term) => _map(term)['columnId']).toList(),
            targetColumns,
          );
        }).singleOrNull;
        if (uniqueIndex == null) {
          _structureFailure(scopeName, target['name']! as String);
        }
      }
    }
  }

  Future<void> _validatePrimaryKeyCollations(
    String scopeName,
    Map<String, Object?> table,
    VoxelCatalogQuery query,
  ) async {
    final tableName = table['name']! as String;
    final indexes = await query(_pragma(scopeName, 'index_list', tableName));
    final primaryKeyIndex = indexes.where((row) => row['origin'] == 'pk').singleOrNull;
    if (primaryKeyIndex == null) return;
    final name = primaryKeyIndex['name']! as String;
    final terms = await query(_pragma(scopeName, 'index_xinfo', name));
    if (terms.any(
      (row) => _integer(row['key']) == 1 && (row['coll'] as String?)?.toUpperCase() != 'BINARY',
    )) {
      _structureFailure(scopeName, tableName);
    }
  }
}

Never _structureFailure(String scopeName, String objectName) => throw VoxelRebuildCatalogException(
  kind: VoxelRebuildCatalogMismatch.structure,
  scopeName: scopeName,
  objectName: objectName,
);

Never _dependencyFailure(String scopeName, String objectName) => throw VoxelRebuildCatalogException(
  kind: VoxelRebuildCatalogMismatch.unmanagedDependency,
  scopeName: scopeName,
  objectName: objectName,
);

String _pragma(String scope, String pragma, String object) =>
    'PRAGMA ${_quote(scope)}.$pragma(${_quote(object)})';

String _quote(String value) => '"${value.replaceAll('"', '""')}"';

String _stringLiteral(String value) => "'${value.replaceAll("'", "''")}'";

String _displayIdentifier(String value) => value.replaceAll(RegExp('[^A-Za-z0-9_.-]'), '?');

List<Object?> _list(Object? value) => value! as List<Object?>;

Map<String, Object?> _map(Object? value) => value! as Map<String, Object?>;

int _integer(Object? value) => switch (value) {
  final int value => value,
  final BigInt value => value.toInt(),
  _ => -1,
};

String _storageType(Map<String, Object?> storage) => switch (storage['kind']) {
  'text' || 'json' || 'array' || 'enum' => 'TEXT',
  'integer' || 'boolean' || 'dateTime' => 'INTEGER',
  'real' => 'REAL',
  'vector' => 'F32_BLOB',
  _ => '',
};

String _action(Object? value) => switch (value) {
  'noAction' => 'NO ACTION',
  'restrict' => 'RESTRICT',
  'cascade' => 'CASCADE',
  'setNull' => 'SET NULL',
  'setDefault' => 'SET DEFAULT',
  _ => '$value',
};

String _renderExpression(
  Map<String, Object?> expression,
  List<Map<String, Object?>> columns,
) {
  final names = {for (final column in columns) column['id']: column['name']! as String};
  String render(Map<String, Object?> value) => switch (value['kind']) {
    'literal' => switch (value['literalType']) {
      'boolean' => value['value'] == true ? 'true' : 'false',
      'null' => 'null',
      'decimal' => value['value']! as String,
      'string' => "'${(value['value']! as String).replaceAll("'", "''")}'",
      _ => '',
    },
    'function' =>
      '${value['name']}(${_list(value['arguments']).map((argument) => render(_map(argument))).join(', ')})',
    'reference' => _quote(names[value['objectId']]!),
    'operator' => _renderOperator(value, render),
    _ => '',
  };

  return render(expression);
}

String _renderOperator(
  Map<String, Object?> expression,
  String Function(Map<String, Object?>) render,
) {
  final operator = expression['operator']! as String;
  final arguments = _list(expression['arguments']).map((value) => render(_map(value))).toList();
  return switch (operator) {
    'NOT' when arguments.length == 1 => 'NOT (${arguments.single})',
    'IS NULL' when arguments.length == 1 => '${arguments.single} IS NULL',
    '=' ||
    '<' ||
    '>' ||
    '+' ||
    'AND' ||
    'OR' when arguments.length == 2 => '(${arguments.first} $operator ${arguments.last})',
    _ => '',
  };
}

String _normalizeSql(String sql) {
  final result = StringBuffer();
  var index = 0;
  while (index < sql.length) {
    final character = sql[index];
    if (character == "'") {
      final start = index++;
      while (index < sql.length) {
        if (sql[index] == "'" && index + 1 < sql.length && sql[index + 1] == "'") {
          index += 2;
        } else if (sql[index++] == "'") {
          break;
        }
      }
      result.write(sql.substring(start, index));
      continue;
    }
    if (character == '"') {
      index++;
      while (index < sql.length && sql[index] != '"') {
        result.write(sql[index++].toLowerCase());
      }
      index++;
      continue;
    }
    if (!RegExp(r'\s').hasMatch(character)) result.write(character.toLowerCase());
    index++;
  }
  return result.toString();
}

Set<String> _referencedTables(String sql) {
  final tokens = _sqlTokens(sql);
  final tables = <String>{};
  for (var index = 0; index < tokens.length - 1; index++) {
    if (tokens[index] != 'from' && tokens[index] != 'join') continue;
    var tableIndex = index + 1;
    if (tokens[tableIndex] == '(') continue;
    if (tableIndex + 2 < tokens.length && tokens[tableIndex + 1] == '.') {
      tableIndex += 2;
    }
    tables.add(tokens[tableIndex]);
  }
  return tables;
}

List<String> _sqlTokens(String sql) {
  final tokens = <String>[];
  var index = 0;
  while (index < sql.length) {
    final character = sql[index];
    if (RegExp(r'\s').hasMatch(character)) {
      index++;
      continue;
    }
    if (character == "'") {
      index++;
      while (index < sql.length) {
        if (sql[index] == "'" && index + 1 < sql.length && sql[index + 1] == "'") {
          index += 2;
        } else if (sql[index++] == "'") {
          break;
        }
      }
      continue;
    }
    if (character == '-' && index + 1 < sql.length && sql[index + 1] == '-') {
      index = sql.indexOf('\n', index + 2);
      if (index < 0) break;
      continue;
    }
    if (character == '/' && index + 1 < sql.length && sql[index + 1] == '*') {
      index = sql.indexOf('*/', index + 2);
      if (index < 0) break;
      index += 2;
      continue;
    }
    if (character == '"' || character == '`' || character == '[') {
      final closing = character == '[' ? ']' : character;
      final token = StringBuffer();
      index++;
      while (index < sql.length && sql[index] != closing) {
        token.write(sql[index++]);
      }
      if (index < sql.length) index++;
      tokens.add(token.toString().toLowerCase());
      continue;
    }
    if (RegExp('[A-Za-z_]').hasMatch(character)) {
      final start = index++;
      while (index < sql.length && RegExp('[A-Za-z0-9_]').hasMatch(sql[index])) {
        index++;
      }
      tokens.add(sql.substring(start, index).toLowerCase());
      continue;
    }
    tokens.add(character);
    index++;
  }
  return tokens;
}

bool _sameList(List<String> left, List<String> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

bool _sameObjectList(Iterable<Object?> left, Iterable<Object?> right) {
  final leftValues = left.toList();
  final rightValues = right.toList();
  if (leftValues.length != rightValues.length) return false;
  for (var index = 0; index < leftValues.length; index++) {
    if (leftValues[index] != rightValues[index]) return false;
  }
  return true;
}

bool _sameJsonValue(Object? left, Object? right) {
  if (left is List<Object?> && right is List<Object?>) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (!_sameJsonValue(left[index], right[index])) return false;
    }
    return true;
  }
  if (left is Map<String, Object?> && right is Map<String, Object?>) {
    if (left.length != right.length || !left.keys.every(right.containsKey)) return false;
    return left.entries.every((entry) => _sameJsonValue(entry.value, right[entry.key]));
  }
  return left == right;
}
