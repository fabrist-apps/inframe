// Internal artifact model shared by runtime migration operations.
// ignore_for_file: public_member_api_docs, prefer_constructors_over_static_methods

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'package:rivet/src/migration/canonical_json.dart';
import 'package:rivet/src/migration/recovery.dart';
import 'package:rivet/src/migration/sql_parser.dart';

final class RivetMigrationArtifacts {
  const RivetMigrationArtifacts({
    required this.databaseId,
    required this.migrations,
    required this.requirements,
  });

  final String databaseId;
  final List<RivetMigrationArtifact> migrations;
  final List<RivetExtensionRequirement> requirements;

  static RivetMigrationArtifacts read(Directory directory) {
    final journal = _readJson(File('${directory.path}/journal.json'));
    _expectVersion(journal, 'journal.json');
    final databaseId = _id(journal['databaseId'], 'journal databaseId');
    final migrations = <RivetMigrationArtifact>[];
    final migrationIds = <String>{};
    String? parentId;
    var requirements = const <RivetExtensionRequirement>[];
    for (final (ordinal, rawEntry) in _list(journal['entries'], 'journal entries').indexed) {
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
      _expectVersion(migration, '$relativeDirectory/migration.json');
      _expectVersion(snapshot, '$relativeDirectory/snapshot.json');
      if (migration['databaseId'] != databaseId || snapshot['databaseId'] != databaseId) {
        throw FormatException('Migration $migrationId has a different database ID.');
      }
      if (migration['id'] != migrationId || snapshot['migrationId'] != migrationId) {
        throw FormatException('Migration $migrationId has inconsistent artifact identities.');
      }
      if (migration['parentId'] != parentId) {
        throw FormatException('Migration $migrationId has a broken parent chain.');
      }
      final checksum = _checksum(migration, snapshot, sql);
      if (migration['checksum'] != checksum || entry['checksum'] != checksum) {
        throw FormatException('Migration $migrationId checksum does not match its artifacts.');
      }
      _validateSnapshot(snapshot);
      requirements = _readRequirements(snapshot);
      final phases = _readPhases(migration, sql);
      migrations.add(
        RivetMigrationArtifact(
          id: migrationId,
          parentId: parentId,
          checksum: checksum,
          ordinal: ordinal,
          phases: phases,
        ),
      );
      parentId = migrationId;
    }
    if (migrations.isEmpty) {
      throw const FormatException('A Rivet journal must contain at least one migration.');
    }
    return RivetMigrationArtifacts(
      databaseId: databaseId,
      migrations: List.unmodifiable(migrations),
      requirements: requirements,
    );
  }
}

final class RivetExtensionRequirement {
  const RivetExtensionRequirement({
    required this.name,
    required this.minimumVersion,
    required this.operatorClasses,
  });

  final String name;
  final String minimumVersion;
  final List<String> operatorClasses;
}

List<RivetExtensionRequirement> _readRequirements(Map<String, Object?> snapshot) => [
  for (final raw in _list(snapshot['requirements'], 'snapshot requirements'))
    switch (_map(raw, 'extension requirement')) {
      {
        'kind': 'extension',
        'name': final String name,
        'minimumVersion': final String version,
        'operatorClasses': final List<Object?> operatorClasses,
      } =>
        RivetExtensionRequirement(
          name: name,
          minimumVersion: version,
          operatorClasses: [
            for (final operatorClass in operatorClasses)
              if (operatorClass case final String value)
                value
              else
                throw const FormatException('Extension operator classes must be strings.'),
          ],
        ),
      _ => throw const FormatException('Snapshot contains an unsupported backend requirement.'),
    },
];

final class RivetMigrationArtifact {
  const RivetMigrationArtifact({
    required this.id,
    required this.parentId,
    required this.checksum,
    required this.ordinal,
    required this.phases,
  });

  final String id;
  final String? parentId;
  final String checksum;
  final int ordinal;
  final List<RivetMigrationPhase> phases;
}

final class RivetMigrationPhase {
  const RivetMigrationPhase({
    required this.id,
    required this.scopeId,
    required this.mode,
    required this.statements,
    required this.recovery,
  });

  final String id;
  final String scopeId;
  final RivetMigrationPhaseMode mode;
  final List<String> statements;
  final Map<String, Object?>? recovery;
}

enum RivetMigrationPhaseMode { transactional, nontransactional }

List<RivetMigrationPhase> _readPhases(Map<String, Object?> migration, String sql) {
  final sqlBytes = utf8.encode(sql);
  final parsedRanges = parseRivetSqlStatements(sql);
  final result = <RivetMigrationPhase>[];
  var parsedIndex = 0;
  var previousEnd = -1;
  for (final (phaseIndex, rawPhase) in _list(migration['phases'], 'migration phases').indexed) {
    final phase = _map(rawPhase, 'phase $phaseIndex');
    final phaseId = phase['id'];
    if (phaseId != '$phaseIndex') {
      throw const FormatException('Migration phase IDs must be unique zero-based decimal strings.');
    }
    final mode = switch (phase['mode']) {
      'transactional' => RivetMigrationPhaseMode.transactional,
      'nontransactional' => RivetMigrationPhaseMode.nontransactional,
      _ => throw FormatException('Phase $phaseId has an unknown execution mode.'),
    };
    final recovery = phase['recovery'];
    if (mode == RivetMigrationPhaseMode.transactional && recovery != null) {
      throw FormatException('Transactional phase $phaseId cannot have recovery metadata.');
    }
    if (mode == RivetMigrationPhaseMode.nontransactional && recovery is! Map<String, Object?>) {
      throw FormatException('Nontransactional phase $phaseId requires recovery metadata.');
    }
    final platforms = _list(phase['platforms'], 'phase platforms');
    if (platforms.any((value) => value is! String) || !platforms.contains('postgresql')) {
      throw FormatException('Phase $phaseId does not support PostgreSQL.');
    }
    final statements = <String>[];
    for (final rawStatement in _list(phase['statements'], 'phase statements')) {
      final statement = _map(rawStatement, 'statement range');
      final start = statement['startByte'];
      final end = statement['endByte'];
      if (start is! int ||
          end is! int ||
          start < 0 ||
          start <= previousEnd ||
          end <= start ||
          end > sqlBytes.length ||
          parsedIndex >= parsedRanges.length ||
          parsedRanges[parsedIndex]['startByte'] != start ||
          parsedRanges[parsedIndex]['endByte'] != end) {
        throw FormatException('Phase $phaseId contains an invalid complete-statement byte range.');
      }
      final sqlStatement = utf8.decode(sqlBytes.sublist(start, end));
      if (_isTransactionControl(sqlStatement)) {
        throw FormatException(
          'Phase $phaseId contains transaction-control SQL; Rivet owns transaction boundaries.',
        );
      }
      statements.add(sqlStatement);
      previousEnd = end;
      parsedIndex++;
    }
    if (mode == RivetMigrationPhaseMode.nontransactional) {
      validateRivetRecovery(phase, statements);
    }
    result.add(
      RivetMigrationPhase(
        id: phaseId! as String,
        scopeId: _id(phase['scopeId'], 'phase scopeId'),
        mode: mode,
        statements: List.unmodifiable(statements),
        recovery: recovery as Map<String, Object?>?,
      ),
    );
  }
  if (parsedIndex != parsedRanges.length) {
    throw const FormatException('Migration phases do not cover every SQL statement.');
  }
  return List.unmodifiable(result);
}

bool _isTransactionControl(String statement) {
  final first = _nextSqlWord(statement, 0);
  if (first.word == null) return false;
  if (const {
    'begin',
    'commit',
    'end',
    'rollback',
    'abort',
    'savepoint',
  }.contains(first.word)) {
    return true;
  }
  final second = _nextSqlWord(statement, first.end);
  if ((first.word == 'start' || first.word == 'prepare') && second.word == 'transaction') {
    return true;
  }
  if (first.word == 'release' && second.word == 'savepoint') return true;
  if (first.word != 'set') return false;
  if (second.word == 'transaction') return true;
  if (second.word == 'local') {
    return _nextSqlWord(statement, second.end).word == 'transaction';
  }
  if (second.word != 'session') return false;
  final characteristics = _nextSqlWord(statement, second.end);
  if (characteristics.word != 'characteristics') return false;
  final as = _nextSqlWord(statement, characteristics.end);
  return as.word == 'as' && _nextSqlWord(statement, as.end).word == 'transaction';
}

({String? word, int end}) _nextSqlWord(String statement, int start) {
  var index = start;
  while (index < statement.length) {
    while (index < statement.length && RegExp(r'\s').hasMatch(statement[index])) {
      index++;
    }
    if (statement.startsWith('--', index)) {
      final newline = statement.indexOf('\n', index + 2);
      index = newline < 0 ? statement.length : newline + 1;
      continue;
    }
    if (statement.startsWith('/*', index)) {
      var depth = 1;
      index += 2;
      while (index < statement.length && depth > 0) {
        if (statement.startsWith('/*', index)) {
          depth++;
          index += 2;
        } else if (statement.startsWith('*/', index)) {
          depth--;
          index += 2;
        } else {
          index++;
        }
      }
      continue;
    }
    break;
  }
  final match = RegExp('^[A-Za-z]+').firstMatch(statement.substring(index));
  return (
    word: match?[0]?.toLowerCase(),
    end: match == null ? statement.length : index + match.end,
  );
}

void _validateSnapshot(Map<String, Object?> snapshot) {
  final ids = <String>{};
  final schemaIds = <String>{};
  final tableIds = <String>{};
  final columnOwners = <String, String>{};
  final enumIds = <String>{};
  for (final raw in _list(snapshot['schemas'], 'snapshot schemas')) {
    final id = _id(_map(raw, 'snapshot schema')['id'], 'schema identity');
    if (!ids.add(id)) throw FormatException('Duplicate snapshot identity `$id`.');
    schemaIds.add(id);
  }
  for (final group in ['tables', 'enums']) {
    for (final raw in _list(snapshot[group], 'snapshot $group')) {
      final value = _map(raw, 'snapshot $group entry');
      final id = _id(value['id'], '$group identity');
      if (!ids.add(id)) throw FormatException('Duplicate snapshot identity `$id`.');
      if (!schemaIds.contains(value['schemaId'])) {
        throw FormatException('$group entry $id references an unknown schema.');
      }
      if (group == 'tables') {
        tableIds.add(id);
      } else {
        enumIds.add(id);
      }
      for (final childGroup in ['columns', 'values', 'indexes', 'constraints']) {
        final children = value[childGroup];
        if (children == null) continue;
        for (final rawChild in _list(children, '$group $childGroup')) {
          final child = _map(rawChild, '$childGroup entry');
          final childValue = child['id'];
          if (childValue == null) continue;
          final childId = _id(childValue, '$childGroup identity');
          if (!ids.add(childId)) throw FormatException('Duplicate snapshot identity `$childId`.');
          if (const {'columns', 'indexes', 'constraints'}.contains(childGroup) &&
              child['tableId'] != id) {
            throw FormatException('$childGroup entry $childId references the wrong table.');
          }
          if (childGroup == 'columns') columnOwners[childId] = id;
          if (childGroup == 'values' && child['enumId'] != id) {
            throw FormatException('Enum value $childId references the wrong enum.');
          }
        }
      }
    }
  }
  for (final rawTable in _list(snapshot['tables'], 'snapshot tables')) {
    final table = _map(rawTable, 'snapshot table');
    final tableId = table['id']! as String;
    for (final rawColumn in _list(table['columns'], 'table columns')) {
      _validateStorage(_map(rawColumn, 'table column')['storage'], enumIds);
    }
    for (final rawIndex in _list(table['indexes'], 'table indexes')) {
      final index = _map(rawIndex, 'table index');
      for (final rawTerm in _list(index['terms'], 'index terms')) {
        if (columnOwners[_map(rawTerm, 'index term')['columnId']] != tableId) {
          throw const FormatException('Index term references a column outside its table.');
        }
      }
      if (index['predicate'] case final Map<String, Object?> expression) {
        _validateExpression(expression, tableId, columnOwners);
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
        _validateExpression(expression, tableId, columnOwners);
      }
      if (constraint['kind'] == 'foreignKey') {
        final target = constraint['referenceTableId'];
        if (!tableIds.contains(target)) {
          throw const FormatException('Foreign key references an unknown table.');
        }
        for (final columnId in _list(constraint['referenceColumnIds'], 'foreign key columns')) {
          if (columnOwners[columnId] != target) {
            throw const FormatException('Foreign key references a column outside its target.');
          }
        }
      }
    }
  }
  _list(snapshot['requirements'], 'snapshot requirements');
}

void _validateStorage(Object? rawStorage, Set<String> enumIds) {
  final storage = _map(rawStorage, 'column storage');
  if (storage['kind'] == 'enum' && !enumIds.contains(storage['enumId'])) {
    throw const FormatException('Enum storage references an unknown type.');
  }
  if (storage['element'] case final Map<String, Object?> element) {
    _validateStorage(element, enumIds);
  }
}

void _validateExpression(
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
      _validateExpression(_map(argument, 'expression argument'), tableId, columnOwners);
    }
  }
}

String _checksum(Map<String, Object?> migration, Map<String, Object?> snapshot, String sql) {
  final metadata = Map<String, Object?>.from(migration)..remove('checksum');
  return sha256
      .convert(
        utf8.encode(
          canonicalRivetJson({'metadata': metadata, 'snapshot': snapshot, 'sql': sql}),
        ),
      )
      .toString();
}

void _expectVersion(Map<String, Object?> value, String source) {
  if (value['formatVersion'] != 1 || value['dialect'] != 'rivet') {
    throw FormatException('$source has an unknown format version or dialect.');
  }
}

Map<String, Object?> _readJson(File file) {
  final source = _readUtf8(file);
  _JsonKeyChecker(source).check();
  final value = jsonDecode(source);
  _validateJsonValues(value);
  return _map(value, file.path);
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

void _validateJsonValues(Object? value) {
  switch (value) {
    case final int number when number.abs() > 9007199254740991:
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

String _id(Object? value, String field) {
  if (value is! String || !RegExp(r'^[0-9a-f]{32}$').hasMatch(value)) {
    throw FormatException('$field must be 32 lowercase hexadecimal characters.');
  }
  return value;
}

List<Object?> _list(Object? value, String field) {
  if (value is! List<Object?>) throw FormatException('$field must be a JSON array.');
  return value;
}

Map<String, Object?> _map(Object? value, String field) {
  if (value is! Map<String, Object?>) throw FormatException('$field must be a JSON object.');
  return value;
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
