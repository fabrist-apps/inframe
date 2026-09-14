// The checker is internal to VoxelMigrationChecker's documented operation.
// ignore_for_file: public_member_api_docs

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:voxel_generator/src/migration/canonical_json.dart';
import 'package:voxel_generator/src/migration/recovery_validator.dart';
import 'package:voxel_generator/src/migration/schema_expression.dart';
import 'package:voxel_generator/src/migration/sql_parser.dart';

final class VoxelArtifactChecker {
  Future<void> check({
    required Directory directory,
    Map<String, Object?>? declaration,
    String? allowUnsealedMigrationId,
  }) async {
    final journal = _readJson(File('${directory.path}/journal.json'));
    validateJournal(journal);
    final databaseId = _id(journal['databaseId'], 'journal databaseId');
    final entries = _list(journal['entries'], 'journal entries');
    String? parentId;
    Map<String, Object?>? finalSnapshot;
    final migrationIds = <String>{};
    for (final (ordinal, rawEntry) in entries.indexed) {
      final entry = _map(rawEntry, 'journal entry $ordinal');
      final migrationId = _id(entry['id'], 'journal entry id');
      if (!migrationIds.add(migrationId)) {
        throw FormatException('Duplicate migration ID `$migrationId`.');
      }
      final relativeDirectory = _safeDirectory(entry['directory']);
      final migrationDirectory = Directory('${directory.path}/$relativeDirectory');
      final migration = _readJson(File('${migrationDirectory.path}/migration.json'));
      final snapshot = _readJson(File('${migrationDirectory.path}/snapshot.json'));
      final sql = _readUtf8(File('${migrationDirectory.path}/migration.sql'));
      _validateMigrationRecord(migration, '$relativeDirectory/migration.json');
      _validateSnapshotRecord(snapshot, '$relativeDirectory/snapshot.json');
      if (migration['databaseId'] != databaseId || snapshot['databaseId'] != databaseId) {
        throw FormatException('Migration $migrationId has a different database ID.');
      }
      if (migration['id'] != migrationId || snapshot['migrationId'] != migrationId) {
        throw FormatException('Migration $migrationId has inconsistent artifact identities.');
      }
      if (migration['parentId'] != parentId) {
        throw FormatException('Migration $migrationId has a broken parent chain.');
      }
      final expectedChecksum = _checksum(migration, snapshot, sql);
      final recordedChecksum = entry['checksum'];
      if (migrationId != allowUnsealedMigrationId &&
          (migration['checksum'] != expectedChecksum || recordedChecksum != expectedChecksum)) {
        throw FormatException('Migration $migrationId checksum does not match its artifacts.');
      }
      _validateSnapshot(snapshot);
      if (migrationId != allowUnsealedMigrationId) {
        _validatePhases(migration, snapshot, sql);
      }
      parentId = migrationId;
      finalSnapshot = snapshot;
    }
    if (finalSnapshot == null) {
      throw const FormatException('A Voxel journal must contain at least one migration.');
    }
    if (declaration != null &&
        canonicalJson(_physicalSnapshot(finalSnapshot)) !=
            canonicalJson(_physicalDeclaration(declaration))) {
      throw const FormatException(
        'The current composed Voxel schema does not match the final migration snapshot.',
      );
    }
  }

  void validateJournal(Map<String, Object?> journal) {
    _record(
      journal,
      'journal.json',
      required: const {'formatVersion', 'dialect', 'databaseId', 'entries'},
      optional: const {'source'},
    );
    _expectVersion(journal, 'journal.json');
    _id(journal['databaseId'], 'journal databaseId');
    if (journal['source'] case final Map<String, Object?> source) {
      _record(source, 'journal source', required: const {'library', 'class'});
      _nonemptyString(source['library'], 'journal source library');
      _nonemptyString(source['class'], 'journal source class');
    } else if (journal['source'] != null) {
      throw const FormatException('journal source must be a JSON object.');
    }
    for (final rawEntry in _list(journal['entries'], 'journal entries')) {
      final entry = _map(rawEntry, 'journal entry');
      _record(entry, 'journal entry', required: const {'id', 'directory', 'checksum'});
      _id(entry['id'], 'journal entry id');
      _safeDirectory(entry['directory']);
      _hex(entry['checksum'], 64, 'journal entry checksum');
    }
  }

  void validateSealedMigration(
    Map<String, Object?> migration,
    Map<String, Object?> snapshot,
    String sql,
  ) {
    _validateMigrationRecord(migration, 'migration.json');
    _validateSnapshotRecord(snapshot, 'snapshot.json');
    _validateSnapshot(snapshot);
    _validatePhases(migration, snapshot, sql);
  }

  void _validateMigrationRecord(Map<String, Object?> migration, String source) {
    _record(
      migration,
      source,
      required: const {
        'formatVersion',
        'dialect',
        'databaseId',
        'id',
        'parentId',
        'checksum',
        'phases',
      },
    );
    _expectVersion(migration, source);
    _id(migration['databaseId'], '$source databaseId');
    _id(migration['id'], '$source id');
    if (migration['parentId'] != null) _id(migration['parentId'], '$source parentId');
    _hex(migration['checksum'], 64, '$source checksum');
    for (final rawPhase in _list(migration['phases'], '$source phases')) {
      final phase = _map(rawPhase, 'migration phase');
      _record(
        phase,
        'migration phase',
        required: const {'id', 'scopeId', 'mode', 'platforms', 'statements', 'recovery'},
        optional: const {'rebuild'},
      );
      final phaseId = phase['id'];
      if (phaseId is! String || !RegExp(r'^(0|[1-9][0-9]*)$').hasMatch(phaseId)) {
        throw const FormatException('migration phase id must be a decimal string.');
      }
      _id(phase['scopeId'], 'migration phase scopeId');
      _oneOf(phase['mode'], const {'transactional', 'nontransactional'}, 'phase mode');
      _stringList(phase['platforms'], 'phase platforms');
      for (final rawStatement in _list(phase['statements'], 'phase statements')) {
        final statement = _map(rawStatement, 'statement range');
        _record(statement, 'statement range', required: const {'startByte', 'endByte'});
        _positiveInt(statement['startByte'], 'statement startByte', allowZero: true);
        _positiveInt(statement['endByte'], 'statement endByte');
      }
      if (phase['recovery'] case final Map<String, Object?> recovery) {
        _validateRecoveryRecord(recovery);
      } else if (phase['recovery'] != null) {
        throw const FormatException('phase recovery must be an object or null.');
      }
      if (phase['rebuild'] case final Map<String, Object?> rebuild) {
        _validateRebuildRecord(rebuild);
      } else if (phase['rebuild'] != null) {
        throw const FormatException('phase rebuild must be an object.');
      }
    }
  }

  void _validateRecoveryRecord(Map<String, Object?> recovery) {
    _record(
      recovery,
      'phase recovery',
      required: const {'kind', 'operationId', 'before', 'after'},
      optional: const {'checks', 'inspector'},
    );
    final kind = _oneOf(recovery['kind'], const {'catalog', 'manual'}, 'recovery kind');
    _id(recovery['operationId'], 'recovery operationId');
    _map(recovery['before'], 'recovery before');
    _map(recovery['after'], 'recovery after');
    if (kind == 'manual') {
      if (recovery.containsKey('checks') || recovery.containsKey('inspector')) {
        throw const FormatException('manual recovery cannot contain checks or an inspector.');
      }
      return;
    }
    if (!recovery.containsKey('checks') && recovery['inspector'] != 'native.index.v1') {
      throw const FormatException('catalog recovery requires checks or its native inspector.');
    }
    if (recovery.containsKey('inspector') && recovery['inspector'] != 'native.index.v1') {
      throw const FormatException('recovery inspector is unsupported.');
    }
    if (recovery.containsKey('checks')) {
      final checks = _list(recovery['checks'], 'recovery checks');
      if (checks.isEmpty) throw const FormatException('recovery checks must not be empty.');
      for (final rawCheck in checks) {
        final check = _map(rawCheck, 'recovery check');
        _record(check, 'recovery check', required: const {'sql', 'parameters', 'expected'});
        _nonemptyString(check['sql'], 'recovery check sql');
        if (check['expected'] is! bool) {
          throw const FormatException('recovery check expected must be boolean.');
        }
        for (final rawParameter in _list(check['parameters'], 'recovery parameters')) {
          final parameter = _map(rawParameter, 'recovery parameter');
          _record(parameter, 'recovery parameter', required: const {'type', 'value'});
          final type = _oneOf(
            parameter['type'],
            const {'null', 'boolean', 'decimal', 'string'},
            'recovery parameter type',
          );
          final value = parameter['value'];
          if ((type == 'null' && value != null) ||
              (type == 'boolean' && value is! bool) ||
              ((type == 'decimal' || type == 'string') && value is! String)) {
            throw const FormatException('recovery parameter value does not match its type.');
          }
        }
      }
    }
  }

  void _validateRebuildRecord(Map<String, Object?> rebuild) {
    _record(rebuild, 'phase rebuild', required: const {'foreignKeys', 'validations'});
    if (rebuild['foreignKeys'] != 'offOutsideTransaction') {
      throw const FormatException('rebuild foreignKeys mode is unsupported.');
    }
    for (final rawValidation in _list(rebuild['validations'], 'rebuild validations')) {
      final validation = _map(rawValidation, 'rebuild validation');
      final kind = _oneOf(
        validation['kind'],
        const {'foreignKeyAntiJoin', 'enumArrayLabels'},
        'rebuild validation kind',
      );
      _record(
        validation,
        'rebuild validation',
        required: {
          'kind',
          'tableId',
          'sql',
          if (kind == 'foreignKeyAntiJoin') 'constraintId' else 'columnId',
        },
      );
      _id(validation['tableId'], 'rebuild validation tableId');
      _id(
        validation[kind == 'foreignKeyAntiJoin' ? 'constraintId' : 'columnId'],
        'rebuild validation identity',
      );
      _nonemptyString(validation['sql'], 'rebuild validation sql');
    }
  }

  void _expectVersion(Map<String, Object?> value, String source) {
    if (value['formatVersion'] != 1 || value['dialect'] != 'voxel') {
      throw FormatException('$source has an unknown format version or dialect.');
    }
  }

  void _validateSnapshot(Map<String, Object?> snapshot) {
    final ids = <String>{};
    final schemaIds = <String>{};
    final tableIds = <String>{};
    final columnOwners = <String, String>{};
    final enumIds = <String>{};
    for (final raw in _list(snapshot['schemas'], 'snapshot schemas')) {
      final schema = _map(raw, 'snapshot schema');
      final id = _id(schema['id'], 'schema identity');
      if (!ids.add(id)) throw FormatException('Duplicate snapshot identity `$id`.');
      schemaIds.add(id);
    }
    for (final group in ['schemas', 'tables', 'enums']) {
      if (group == 'schemas') continue;
      for (final raw in _list(snapshot[group], 'snapshot $group')) {
        final value = _map(raw, 'snapshot $group entry');
        final id = _id(value['id'], '$group identity');
        if (!ids.add(id)) throw FormatException('Duplicate snapshot identity `$id`.');
        if (group == 'tables') tableIds.add(id);
        if (group == 'enums') enumIds.add(id);
        if (!schemaIds.contains(value['schemaId'])) {
          throw FormatException('$group entry $id references an unknown schema.');
        }
        for (final childGroup in ['columns', 'values', 'indexes', 'constraints']) {
          final children = value[childGroup];
          if (children == null) continue;
          for (final rawChild in _list(children, '$group $childGroup')) {
            final child = _map(rawChild, '$group $childGroup entry');
            final childId = child['id'];
            if (childId == null) continue;
            final id = _id(childId, '$childGroup identity');
            if (!ids.add(id)) throw FormatException('Duplicate snapshot identity `$id`.');
            if ((childGroup == 'columns' ||
                    childGroup == 'indexes' ||
                    childGroup == 'constraints') &&
                child['tableId'] != value['id']) {
              throw FormatException('$childGroup entry $id references the wrong table.');
            }
            if (childGroup == 'columns') columnOwners[id] = value['id']! as String;
            if (childGroup == 'values' && child['enumId'] != value['id']) {
              throw FormatException('Enum value $id references the wrong enum.');
            }
          }
        }
      }
    }
    for (final rawTable in _list(snapshot['tables'], 'snapshot tables')) {
      final table = _map(rawTable, 'snapshot table');
      final tableId = table['id']! as String;
      for (final rawColumn in _list(table['columns'], 'table columns')) {
        _validateStorageReferences(
          _map(rawColumn, 'table column')['storage']! as Map<String, Object?>,
          enumIds,
        );
      }
      for (final rawIndex in _list(table['indexes'], 'table indexes')) {
        final index = _map(rawIndex, 'table index');
        for (final rawTerm in _list(index['terms'], 'index terms')) {
          final columnId = _map(rawTerm, 'index term')['columnId'];
          if (columnOwners[columnId] != tableId) {
            throw const FormatException('Index term references a column outside its table.');
          }
        }
        if (index['predicate'] case final Map<String, Object?> expression) {
          _validateExpressionReferences(expression, tableId, columnOwners);
        }
      }
      for (final rawConstraint in _list(table['constraints'], 'table constraints')) {
        final constraint = _map(rawConstraint, 'table constraint');
        for (final columnId in _list(constraint['columnIds'], 'constraint columns')) {
          if (columnOwners[columnId] != tableId) {
            throw const FormatException('Constraint references a column outside its table.');
          }
        }
        if (constraint['expression'] case final Map<String, Object?> expression) {
          _validateExpressionReferences(expression, tableId, columnOwners);
        }
        if (constraint['kind'] == 'foreignKey') {
          final target = constraint['referenceTableId'];
          if (!tableIds.contains(target)) {
            throw const FormatException('Foreign key references an unknown table.');
          }
          for (final columnId in _list(
            constraint['referenceColumnIds'],
            'foreign key columns',
          )) {
            if (columnOwners[columnId] != target) {
              throw const FormatException('Foreign key references a column outside its target.');
            }
          }
        }
      }
    }
    _list(snapshot['requirements'], 'snapshot requirements');
  }

  void _validateSnapshotRecord(Map<String, Object?> snapshot, String source) {
    _record(
      snapshot,
      source,
      required: const {
        'formatVersion',
        'dialect',
        'databaseId',
        'migrationId',
        'schemas',
        'tables',
        'enums',
        'requirements',
      },
    );
    _expectVersion(snapshot, source);
    _id(snapshot['databaseId'], '$source databaseId');
    _id(snapshot['migrationId'], '$source migrationId');
    for (final rawSchema in _list(snapshot['schemas'], '$source schemas')) {
      final schema = _map(rawSchema, 'snapshot schema');
      _record(schema, 'snapshot schema', required: const {'id', 'name'});
      _id(schema['id'], 'schema identity');
      _nonemptyString(schema['name'], 'schema name');
    }
    for (final rawTable in _list(snapshot['tables'], '$source tables')) {
      final table = _map(rawTable, 'snapshot table');
      _record(
        table,
        'snapshot table',
        required: const {'id', 'schemaId', 'name', 'columns', 'indexes', 'constraints'},
      );
      _id(table['id'], 'table identity');
      _id(table['schemaId'], 'table schemaId');
      _nonemptyString(table['name'], 'table name');
      for (final rawColumn in _list(table['columns'], 'table columns')) {
        final column = _map(rawColumn, 'table column');
        _record(
          column,
          'table column',
          required: const {'id', 'tableId', 'name', 'storage', 'primaryKey'},
          optional: const {'default'},
        );
        _id(column['id'], 'column identity');
        _id(column['tableId'], 'column tableId');
        _nonemptyString(column['name'], 'column name');
        if (column['primaryKey'] is! bool) {
          throw const FormatException('column primaryKey must be a boolean.');
        }
        _validateStorage(_map(column['storage'], 'column storage'));
        if (column.containsKey('default')) {
          _validateExpressionRecord(_map(column['default'], 'column default'));
        }
      }
      for (final rawIndex in _list(table['indexes'], 'table indexes')) {
        final index = _map(rawIndex, 'table index');
        _record(
          index,
          'table index',
          required: const {'id', 'tableId', 'name', 'unique', 'terms', 'options', 'platforms'},
          optional: const {'predicate'},
        );
        _id(index['id'], 'index identity');
        _id(index['tableId'], 'index tableId');
        _nonemptyString(index['name'], 'index name');
        if (index['unique'] is! bool) throw const FormatException('index unique must be boolean.');
        final terms = _list(index['terms'], 'index terms');
        if (terms.isEmpty) throw const FormatException('index terms must not be empty.');
        for (final rawTerm in terms) {
          final term = _map(rawTerm, 'index term');
          _record(term, 'index term', required: const {'columnId', 'descending'});
          _id(term['columnId'], 'index term columnId');
          if (term['descending'] is! bool) {
            throw const FormatException('index term descending must be boolean.');
          }
        }
        if (index.containsKey('predicate')) {
          _validateExpressionRecord(_map(index['predicate'], 'index predicate'));
        }
        _map(index['options'], 'index options');
        _stringList(index['platforms'], 'index platforms');
      }
      for (final rawConstraint in _list(table['constraints'], 'table constraints')) {
        _validateConstraintRecord(_map(rawConstraint, 'table constraint'));
      }
    }
    for (final rawEnum in _list(snapshot['enums'], '$source enums')) {
      final value = _map(rawEnum, 'snapshot enum');
      _record(
        value,
        'snapshot enum',
        required: const {'id', 'schemaId', 'name', 'values'},
      );
      _id(value['id'], 'enum identity');
      _id(value['schemaId'], 'enum schemaId');
      _nonemptyString(value['name'], 'enum name');
      final values = _list(value['values'], 'enum values');
      if (values.isEmpty) throw const FormatException('enum values must not be empty.');
      for (final rawValue in values) {
        final enumValue = _map(rawValue, 'enum value');
        _record(enumValue, 'enum value', required: const {'id', 'enumId', 'label'});
        _id(enumValue['id'], 'enum value identity');
        _id(enumValue['enumId'], 'enum value enumId');
        _nonemptyString(enumValue['label'], 'enum value label');
      }
    }
    for (final requirement in _list(snapshot['requirements'], '$source requirements')) {
      _map(requirement, 'snapshot requirement');
    }
  }

  void _validateStorage(Map<String, Object?> storage) {
    final kind = _oneOf(
      storage['kind'],
      const {'text', 'integer', 'real', 'boolean', 'dateTime', 'json', 'enum', 'vector', 'array'},
      'storage kind',
    );
    final specific = switch (kind) {
      'enum' => const {'enumId'},
      'vector' => const {'dimensions'},
      'array' => const {'element'},
      _ => const <String>{},
    };
    _record(
      storage,
      'column storage',
      required: {'kind', 'nullable', 'codecVersion', ...specific},
    );
    if (storage['nullable'] is! bool) {
      throw const FormatException('storage nullable must be boolean.');
    }
    _positiveInt(storage['codecVersion'], 'storage codecVersion');
    if (kind == 'enum') _id(storage['enumId'], 'storage enumId');
    if (kind == 'vector') _positiveInt(storage['dimensions'], 'storage dimensions');
    if (kind == 'array') _validateStorage(_map(storage['element'], 'array element storage'));
  }

  void _validateConstraintRecord(Map<String, Object?> constraint) {
    final kind = _oneOf(
      constraint['kind'],
      const {'check', 'primaryKey', 'foreignKey'},
      'constraint kind',
    );
    final specific = switch (kind) {
      'check' => const {'expression'},
      'foreignKey' => const {
        'referenceTableId',
        'referenceColumnIds',
        'onDelete',
        'onUpdate',
      },
      _ => const <String>{},
    };
    _record(
      constraint,
      'table constraint',
      required: {'id', 'tableId', 'name', 'kind', 'columnIds', ...specific},
    );
    _id(constraint['id'], 'constraint identity');
    _id(constraint['tableId'], 'constraint tableId');
    _nonemptyString(constraint['name'], 'constraint name');
    for (final columnId in _list(constraint['columnIds'], 'constraint columns')) {
      _id(columnId, 'constraint columnId');
    }
    if (kind == 'check') {
      _validateExpressionRecord(_map(constraint['expression'], 'constraint expression'));
    }
    if (kind == 'foreignKey') {
      _id(constraint['referenceTableId'], 'foreign key referenceTableId');
      final references = _list(constraint['referenceColumnIds'], 'foreign key columns');
      for (final columnId in references) {
        _id(columnId, 'foreign key referenceColumnId');
      }
      if (references.length != (constraint['columnIds']! as List<Object?>).length) {
        throw const FormatException('foreign key columns must have matching arity.');
      }
      const actions = {'noAction', 'restrict', 'cascade', 'setNull', 'setDefault'};
      _oneOf(constraint['onDelete'], actions, 'foreign key onDelete');
      _oneOf(constraint['onUpdate'], actions, 'foreign key onUpdate');
    }
  }

  void _validateExpressionRecord(Map<String, Object?> expression) {
    if (expression['formatVersion'] != 1) {
      throw const FormatException('schema expression has an unknown format version.');
    }
    final kind = _oneOf(
      expression['kind'],
      const {'literal', 'reference', 'operator', 'function'},
      'schema expression kind',
    );
    final specific = switch (kind) {
      'literal' => const {'literalType', 'value'},
      'reference' => const {'objectId'},
      'operator' => const {'operator', 'arguments'},
      'function' => const {'name', 'arguments'},
      _ => const <String>{},
    };
    _record(
      expression,
      'schema expression',
      required: {'formatVersion', 'kind', ...specific},
    );
    if (kind == 'literal') {
      final literalType = _oneOf(
        expression['literalType'],
        const {'null', 'boolean', 'decimal', 'string'},
        'schema literal type',
      );
      final value = expression['value'];
      if ((literalType == 'null' && value != null) ||
          (literalType == 'boolean' && value is! bool) ||
          ((literalType == 'decimal' || literalType == 'string') && value is! String)) {
        throw const FormatException('schema literal value does not match its type.');
      }
    } else if (kind == 'reference') {
      _id(expression['objectId'], 'schema reference objectId');
    } else {
      _nonemptyString(
        expression[kind == 'operator' ? 'operator' : 'name'],
        'schema expression operation',
      );
      for (final rawArgument in _list(expression['arguments'], 'schema expression arguments')) {
        _validateExpressionRecord(_map(rawArgument, 'schema expression argument'));
      }
    }
  }

  void _validateStorageReferences(Map<String, Object?> storage, Set<String> enumIds) {
    if (storage['kind'] == 'enum' && !enumIds.contains(storage['enumId'])) {
      throw const FormatException('Enum storage references an unknown type.');
    }
    if (storage['element'] case final Map<String, Object?> element) {
      _validateStorageReferences(element, enumIds);
    }
  }

  void _validateExpressionReferences(
    Map<String, Object?> expression,
    String tableId,
    Map<String, String> columnOwners,
  ) {
    if (expression['formatVersion'] != 1) {
      throw const FormatException('Schema expression has an unknown format version.');
    }
    if (expression['kind'] == 'reference' && columnOwners[expression['objectId']] != tableId) {
      throw const FormatException('Schema expression references a column outside its table.');
    }
    if (expression['arguments'] case final List<Object?> arguments) {
      for (final argument in arguments) {
        _validateExpressionReferences(_map(argument, 'expression argument'), tableId, columnOwners);
      }
    }
  }

  void _validatePhases(
    Map<String, Object?> migration,
    Map<String, Object?> snapshot,
    String sql,
  ) {
    final bytes = utf8.encode(sql);
    final parsedRanges = parseVoxelSqlStatements(sql);
    final schemaNames = <String, String>{
      for (final rawSchema in _list(snapshot['schemas'], 'snapshot schemas'))
        (_map(rawSchema, 'snapshot schema')['id']! as String):
            _map(rawSchema, 'snapshot schema')['name']! as String,
    };
    var parsedIndex = 0;
    final phaseIds = <String>{};
    var previousEnd = -1;
    for (final (phaseIndex, rawPhase) in _list(migration['phases'], 'migration phases').indexed) {
      final phase = _map(rawPhase, 'phase $phaseIndex');
      final phaseId = phase['id'];
      if (phaseId != '$phaseIndex' || !phaseIds.add(phaseId! as String)) {
        throw const FormatException(
          'Migration phase IDs must be unique zero-based decimal strings.',
        );
      }
      if (phase['mode'] != 'transactional' && phase['mode'] != 'nontransactional') {
        throw FormatException('Phase $phaseId has an unknown execution mode.');
      }
      final scopeName = schemaNames[phase['scopeId']];
      if (scopeName == null) {
        throw FormatException('Phase $phaseId references an unknown file scope.');
      }
      final platforms = _list(phase['platforms'], 'phase platforms');
      if (platforms.isEmpty ||
          platforms.any((value) => value != 'native' && value != 'browser') ||
          platforms.toSet().length != platforms.length) {
        throw FormatException('Phase $phaseId has invalid or duplicate platforms.');
      }
      if (phase['mode'] == 'transactional' && phase['recovery'] != null) {
        throw FormatException('Transactional phase $phaseId cannot have recovery metadata.');
      }
      _validateRebuild(phase, snapshot);
      final phaseSql = <String>[];
      for (final rawStatement in _list(phase['statements'], 'phase statements')) {
        final statement = _map(rawStatement, 'statement range');
        final start = statement['startByte'];
        final end = statement['endByte'];
        if (start is! int ||
            end is! int ||
            start < 0 ||
            start <= previousEnd ||
            end <= start ||
            end > bytes.length) {
          throw FormatException('Phase $phaseId contains an invalid statement byte range.');
        }
        if (parsedIndex >= parsedRanges.length ||
            parsedRanges[parsedIndex]['startByte'] != start ||
            parsedRanges[parsedIndex]['endByte'] != end) {
          throw FormatException('Phase $phaseId byte range is not one complete statement.');
        }
        parsedIndex++;
        phaseSql.add(utf8.decode(bytes.sublist(start, end)));
        previousEnd = end;
      }
      validateVoxelRecovery(phase, phaseSql, scopeName: scopeName);
    }
    if (parsedIndex != parsedRanges.length) {
      throw const FormatException('Migration phases do not cover every SQL statement.');
    }
  }

  void _validateRebuild(
    Map<String, Object?> phase,
    Map<String, Object?> snapshot,
  ) {
    final rawRebuild = phase['rebuild'];
    if (rawRebuild == null) return;
    final rebuild = _map(rawRebuild, 'phase rebuild');
    if (phase['mode'] != 'transactional' || rebuild['foreignKeys'] != 'offOutsideTransaction') {
      throw const FormatException(
        'A rebuild must be transactional and restore foreign keys outside its transaction.',
      );
    }
    final tables = <String, Map<String, Object?>>{
      for (final rawTable in _list(snapshot['tables'], 'snapshot tables'))
        (_map(rawTable, 'snapshot table')['id']! as String): _map(rawTable, 'snapshot table'),
    };
    for (final rawValidation in _list(rebuild['validations'], 'rebuild validations')) {
      final validation = _map(rawValidation, 'rebuild validation');
      if (validation['kind'] != 'foreignKeyAntiJoin' && validation['kind'] != 'enumArrayLabels') {
        throw const FormatException('A rebuild contains an unknown validation kind.');
      }
      final table = tables[validation['tableId']];
      if (table == null || table['schemaId'] != phase['scopeId']) {
        throw const FormatException('A rebuild validation references a table outside its scope.');
      }
      if (validation['kind'] == 'foreignKeyAntiJoin') {
        final constraints = _list(
          table['constraints'],
          'table constraints',
        ).map((value) => _map(value, 'table constraint'));
        if (!constraints.any(
          (constraint) =>
              constraint['id'] == validation['constraintId'] && constraint['kind'] == 'foreignKey',
        )) {
          throw const FormatException('A rebuild validation references an unknown foreign key.');
        }
      } else {
        final columns = _list(
          table['columns'],
          'table columns',
        ).map((value) => _map(value, 'table column'));
        if (!columns.any((column) {
          if (column['id'] != validation['columnId']) return false;
          final storage = column['storage']! as Map<String, Object?>;
          return storage['kind'] == 'array' &&
              storage['element'] is Map<String, Object?> &&
              (storage['element']! as Map<String, Object?>)['kind'] == 'enum';
        })) {
          throw const FormatException('A rebuild validation references an unknown enum array.');
        }
      }
      final validationSql = validation['sql'];
      if (validationSql is! String ||
          !RegExp(r'^\s*SELECT\b', caseSensitive: false).hasMatch(validationSql) ||
          parseVoxelSqlStatements(validationSql).length != 1) {
        throw const FormatException('A rebuild validation must be one read-only SELECT statement.');
      }
    }
  }

  Map<String, Object?> _physicalSnapshot(Map<String, Object?> snapshot) {
    final schemaNames = <String, String>{
      for (final raw in _list(snapshot['schemas'], 'snapshot schemas'))
        (_map(raw, 'schema')['id']! as String): _map(raw, 'schema')['name']! as String,
    };
    final snapshotTables = [
      for (final raw in _list(snapshot['tables'], 'snapshot tables')) _map(raw, 'snapshot table'),
    ];
    final tablesById = {
      for (final table in snapshotTables) table['id']! as String: table,
    };
    final columnNames = <String, String>{};
    for (final table in snapshotTables) {
      for (final raw in _list(table['columns'], 'table columns')) {
        final column = _map(raw, 'table column');
        columnNames[column['id']! as String] = column['name']! as String;
      }
    }
    final enumNames = <String, ({String schema, String name})>{};
    final physicalEnums = <Map<String, Object?>>[];
    for (final raw in _list(snapshot['enums'], 'snapshot enums')) {
      final value = _map(raw, 'snapshot enum');
      final physical = <String, Object?>{
        'schema': schemaNames[value['schemaId']],
        'name': value['name'],
        'values': [
          for (final rawValue in _list(value['values'], 'enum values'))
            {'label': _map(rawValue, 'enum value')['label']},
        ],
      };
      enumNames[value['id']! as String] = (
        schema: physical['schema']! as String,
        name: physical['name']! as String,
      );
      physicalEnums.add(physical);
    }
    physicalEnums.sort(_byPhysicalName);
    final tables = [
      for (final table in snapshotTables)
        _stripSnapshotTable(table, schemaNames, tablesById, columnNames, enumNames),
    ]..sort(_byPhysicalName);
    return {
      'formatVersion': 1,
      'dialect': 'voxel',
      'name': null,
      'tables': tables,
      'enums': physicalEnums,
      'requirements': _list(snapshot['requirements'], 'snapshot requirements'),
    };
  }

  Map<String, Object?> _physicalDeclaration(Map<String, Object?> declaration) {
    final normalized = normalizeDeclaration(declaration);
    final tables = [
      for (final raw in _list(normalized['tables'], 'declaration tables'))
        _sortDeclarationTable(
          _withoutRenameHints(_map(raw, 'declaration table'))! as Map<String, Object?>,
        ),
    ]..sort(_byPhysicalName);
    return {
      'formatVersion': 1,
      'dialect': 'voxel',
      'name': null,
      'tables': tables,
      'enums': _physicalDeclarationEnums(
        _list(normalized['enums'], 'declaration enums'),
      ),
      'requirements': _list(normalized['requirements'], 'declaration requirements'),
    };
  }

  Map<String, Object?> _stripSnapshotTable(
    Map<String, Object?> table,
    Map<String, String> schemaNames,
    Map<String, Map<String, Object?>> tablesById,
    Map<String, String> columnNames,
    Map<String, ({String schema, String name})> enumNames,
  ) => {
    'schema': schemaNames[table['schemaId']],
    'name': table['name'],
    'columns': [
      for (final raw in _list(table['columns'], 'table columns'))
        _stripSnapshotColumn(_map(raw, 'table column'), enumNames),
    ],
    'indexes': ([
      for (final raw in _list(table['indexes'], 'table indexes'))
        _stripSnapshotIndex(_map(raw, 'table index'), columnNames),
    ]..sort(_byName)),
    'constraints': ([
      for (final raw in _list(table['constraints'], 'table constraints'))
        if (!_isImplicitPrimaryKey(_map(raw, 'table constraint'), table, columnNames))
          _stripSnapshotConstraint(
            _map(raw, 'table constraint'),
            schemaNames,
            tablesById,
            columnNames,
          ),
    ]..sort(_byName)),
  };

  Map<String, Object?> _stripSnapshotColumn(
    Map<String, Object?> column,
    Map<String, ({String schema, String name})> enumNames,
  ) => {
    ..._withoutKeys(column, {'id', 'tableId'}),
    'storage': _storageNames(column['storage']! as Map<String, Object?>, enumNames),
  };

  Map<String, Object?> _sortDeclarationTable(Map<String, Object?> table) => {
    ...table,
    'indexes': ([
      for (final raw in _list(table['indexes'], 'declaration indexes'))
        _map(raw, 'declaration index'),
    ]..sort(_byName)),
    'constraints': ([
      for (final raw in _list(table['constraints'], 'declaration constraints'))
        _map(raw, 'declaration constraint'),
    ]..sort(_byName)),
  };

  Map<String, Object?> _storageNames(
    Map<String, Object?> storage,
    Map<String, ({String schema, String name})> enumNames,
  ) {
    if (storage['kind'] == 'enum') {
      final value = enumNames[storage['enumId']];
      return {
        ..._withoutKeys(storage, {'enumId'}),
        'enum': {'schema': value?.schema, 'name': value?.name},
      };
    }
    return {
      ...storage,
      if (storage['element'] case final Map<String, Object?> element)
        'element': _storageNames(element, enumNames),
    };
  }

  List<Object?> _physicalDeclarationEnums(List<Object?> values) {
    final enums = [
      for (final raw in values)
        {
          'schema': _map(raw, 'declaration enum')['schema'],
          'name': _map(raw, 'declaration enum')['name'],
          'values': [
            for (final rawValue in _list(
              _map(raw, 'declaration enum')['values'],
              'declaration enum values',
            ))
              {'label': _map(rawValue, 'declaration enum value')['label']},
          ],
        },
    ]..sort(_byPhysicalName);
    return enums;
  }

  Map<String, Object?> _stripSnapshotIndex(
    Map<String, Object?> index,
    Map<String, String> columnNames,
  ) => {
    'name': index['name'],
    'unique': index['unique'],
    'terms': [
      for (final raw in _list(index['terms'], 'index terms'))
        {
          'column': columnNames[_map(raw, 'index term')['columnId']],
          'descending': _map(raw, 'index term')['descending'],
        },
    ],
    if (index['predicate'] case final Map<String, Object?> expression)
      'predicate': _expressionNames(expression, columnNames),
    'options': index['options'],
    'platforms': index['platforms'],
  };

  Map<String, Object?> _stripSnapshotConstraint(
    Map<String, Object?> constraint,
    Map<String, String> schemaNames,
    Map<String, Map<String, Object?>> tablesById,
    Map<String, String> columnNames,
  ) {
    final result = <String, Object?>{
      'name': constraint['name'],
      'kind': constraint['kind'],
      'columns': [
        for (final id in _list(constraint['columnIds'], 'constraint columns')) columnNames[id],
      ],
      if (constraint['expression'] case final Map<String, Object?> expression)
        'expression': _expressionNames(expression, columnNames),
    };
    if (constraint['kind'] == 'foreignKey') {
      final target = tablesById[constraint['referenceTableId']]!;
      result
        ..['references'] = {
          'schema': schemaNames[target['schemaId']],
          'table': target['name'],
          'columns': [
            for (final id in _list(constraint['referenceColumnIds'], 'foreign key columns'))
              columnNames[id],
          ],
        }
        ..['onDelete'] = constraint['onDelete']
        ..['onUpdate'] = constraint['onUpdate'];
    }
    return result;
  }

  bool _isImplicitPrimaryKey(
    Map<String, Object?> constraint,
    Map<String, Object?> table,
    Map<String, String> columnNames,
  ) {
    if (constraint['kind'] != 'primaryKey' || constraint['name'] != '${table['name']}_pkey') {
      return false;
    }
    final primaryColumns = [
      for (final raw in _list(table['columns'], 'table columns'))
        if (_map(raw, 'table column')['primaryKey'] == true) _map(raw, 'table column')['name'],
    ];
    return canonicalJson(primaryColumns) ==
        canonicalJson([
          for (final id in _list(constraint['columnIds'], 'constraint columns')) columnNames[id],
        ]);
  }

  Map<String, Object?> _expressionNames(
    Map<String, Object?> expression,
    Map<String, String> columnNames,
  ) => expression['kind'] == 'reference'
      ? {
          'formatVersion': 1,
          'kind': 'reference',
          'objectName': columnNames[expression['objectId']],
        }
      : {
          ...expression,
          if (expression['arguments'] case final List<Object?> arguments)
            'arguments': [
              for (final argument in arguments)
                _expressionNames(_map(argument, 'expression argument'), columnNames),
            ],
        };

  int _byPhysicalName(Map<String, Object?> left, Map<String, Object?> right) =>
      '${left['schema']}.${left['name']}'.compareTo('${right['schema']}.${right['name']}');

  int _byName(Map<String, Object?> left, Map<String, Object?> right) =>
      (left['name']! as String).compareTo(right['name']! as String);

  Map<String, Object?> _withoutKeys(Map<String, Object?> value, Set<String> keys) => {
    for (final entry in value.entries)
      if (!keys.contains(entry.key)) entry.key: entry.value,
  };

  Object? _withoutRenameHints(Object? value) => switch (value) {
    final Map<String, Object?> map => {
      for (final entry in map.entries)
        if (entry.key != 'renamedFrom') entry.key: _withoutRenameHints(entry.value),
    },
    final List<Object?> list => [for (final item in list) _withoutRenameHints(item)],
    _ => value,
  };

  String _checksum(
    Map<String, Object?> migration,
    Map<String, Object?> snapshot,
    String sql,
  ) {
    final metadata = Map<String, Object?>.from(migration)..remove('checksum');
    return sha256
        .convert(
          utf8.encode(
            canonicalJson({'metadata': metadata, 'snapshot': snapshot, 'sql': sql}),
          ),
        )
        .toString();
  }

  Map<String, Object?> _readJson(File file) {
    final source = _readUtf8(file);
    _JsonKeyChecker(source).check();
    final value = jsonDecode(source);
    _validateJsonValues(value);
    return _map(value, file.path);
  }

  void _validateJsonValues(Object? value) {
    switch (value) {
      case final int number when number > 9007199254740991 || number < -9007199254740991:
        throw const FormatException('JSON integer exceeds the interoperable numeric range.');
      case final double number when !number.isFinite:
        throw const FormatException('JSON numbers must be finite.');
      case final String string:
        for (var index = 0; index < string.length; index++) {
          final unit = string.codeUnitAt(index);
          if (unit >= 0xd800 && unit <= 0xdbff) {
            if (++index >= string.length ||
                string.codeUnitAt(index) < 0xdc00 ||
                string.codeUnitAt(index) > 0xdfff) {
              throw const FormatException('JSON contains malformed Unicode.');
            }
          } else if (unit >= 0xdc00 && unit <= 0xdfff) {
            throw const FormatException('JSON contains malformed Unicode.');
          }
        }
      case final List<Object?> list:
        list.forEach(_validateJsonValues);
      case final Map<String, Object?> map:
        for (final entry in map.entries) {
          _validateJsonValues(entry.key);
          _validateJsonValues(entry.value);
        }
    }
  }

  String _readUtf8(File file) {
    if (!file.existsSync()) throw FormatException('Missing artifact ${file.path}.');
    final bytes = file.readAsBytesSync();
    if (bytes.length >= 3 && bytes[0] == 0xef && bytes[1] == 0xbb && bytes[2] == 0xbf) {
      throw FormatException('Artifact ${file.path} must not contain a UTF-8 BOM.');
    }
    try {
      return utf8.decode(bytes);
    } on FormatException {
      throw FormatException('Artifact ${file.path} is not valid UTF-8.');
    }
  }

  String _safeDirectory(Object? value) {
    if (value is! String ||
        value.isEmpty ||
        value.startsWith('/') ||
        value.contains(r'\') ||
        value.split('/').any((segment) => segment.isEmpty || segment == '.' || segment == '..')) {
      throw const FormatException('Journal contains an unsafe migration directory.');
    }
    return value;
  }

  void _record(
    Map<String, Object?> value,
    String field, {
    required Set<String> required,
    Set<String> optional = const {},
  }) {
    final missing = required.difference(value.keys.toSet());
    if (missing.isNotEmpty) {
      throw FormatException('$field is missing required fields: ${missing.toList()..sort()}.');
    }
    final unknown = value.keys.toSet().difference({...required, ...optional});
    if (unknown.isNotEmpty) {
      throw FormatException('$field contains unknown fields: ${unknown.toList()..sort()}.');
    }
  }

  String _nonemptyString(Object? value, String field) {
    if (value is! String || value.isEmpty) {
      throw FormatException('$field must be a non-empty string.');
    }
    return value;
  }

  String _oneOf(Object? value, Set<String> allowed, String field) {
    if (value is! String || !allowed.contains(value)) {
      throw FormatException('$field has an unsupported value.');
    }
    return value;
  }

  void _positiveInt(Object? value, String field, {bool allowZero = false}) {
    if (value is! int || (allowZero ? value < 0 : value < 1)) {
      throw FormatException(
        '$field must be ${allowZero ? 'a non-negative' : 'a positive'} integer.',
      );
    }
  }

  List<String> _stringList(Object? value, String field) {
    final list = _list(value, field);
    if (list.any((entry) => entry is! String)) {
      throw FormatException('$field must contain only strings.');
    }
    return list.cast<String>();
  }

  String _hex(Object? value, int length, String field) {
    if (value is! String || !RegExp('^[0-9a-f]{$length}\$').hasMatch(value)) {
      throw FormatException('$field must be $length lowercase hexadecimal characters.');
    }
    return value;
  }

  String _id(Object? value, String field) {
    return _hex(value, 32, field);
  }

  List<Object?> _list(Object? value, String field) {
    if (value is! List<Object?>) throw FormatException('$field must be a JSON array.');
    return value;
  }

  Map<String, Object?> _map(Object? value, String field) {
    if (value is! Map<String, Object?>) throw FormatException('$field must be a JSON object.');
    return value;
  }
}

final class _JsonKeyChecker {
  _JsonKeyChecker(this.source);

  final String source;
  var _offset = 0;

  void check() {
    _value();
    _space();
    if (_offset != source.length) throw const FormatException('Malformed JSON input.');
  }

  void _value() {
    _space();
    if (_offset >= source.length) throw const FormatException('Malformed JSON input.');
    switch (source.codeUnitAt(_offset)) {
      case 0x7b:
        _object();
      case 0x5b:
        _array();
      case 0x22:
        _string();
      default:
        _scalar();
    }
  }

  void _object() {
    _offset++;
    _space();
    final keys = <String>{};
    if (_take(0x7d)) return;
    while (true) {
      _space();
      final key = _string();
      if (!keys.add(key)) throw FormatException('Duplicate JSON key `$key`.');
      _space();
      _expect(0x3a);
      _value();
      _space();
      if (_take(0x7d)) return;
      _expect(0x2c);
    }
  }

  void _array() {
    _offset++;
    _space();
    if (_take(0x5d)) return;
    while (true) {
      _value();
      _space();
      if (_take(0x5d)) return;
      _expect(0x2c);
    }
  }

  String _string() {
    final start = _offset;
    _expect(0x22);
    var escaped = false;
    while (_offset < source.length) {
      final unit = source.codeUnitAt(_offset++);
      if (escaped) {
        escaped = false;
      } else if (unit == 0x5c) {
        escaped = true;
      } else if (unit == 0x22) {
        return jsonDecode(source.substring(start, _offset)) as String;
      }
    }
    throw const FormatException('Malformed JSON string.');
  }

  void _scalar() {
    final start = _offset;
    while (_offset < source.length &&
        !const {0x20, 0x09, 0x0a, 0x0d, 0x2c, 0x5d, 0x7d}.contains(source.codeUnitAt(_offset))) {
      _offset++;
    }
    if (start == _offset) throw const FormatException('Malformed JSON value.');
  }

  void _space() {
    while (_offset < source.length &&
        const {0x20, 0x09, 0x0a, 0x0d}.contains(source.codeUnitAt(_offset))) {
      _offset++;
    }
  }

  bool _take(int unit) {
    if (_offset >= source.length || source.codeUnitAt(_offset) != unit) return false;
    _offset++;
    return true;
  }

  void _expect(int unit) {
    if (!_take(unit)) throw const FormatException('Malformed JSON input.');
  }
}
