// The checker is internal to RivetMigrationChecker's documented operation.
// ignore_for_file: public_member_api_docs

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:rivet_generator/src/migration/canonical_json.dart';
import 'package:rivet_generator/src/migration/schema_expression.dart';

final class RivetArtifactChecker {
  Future<void> check({
    required Directory directory,
    Map<String, Object?>? declaration,
  }) async {
    final journal = _readJson(File('${directory.path}/journal.json'));
    _expectVersion(journal, 'journal.json');
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
      final expectedChecksum = _checksum(migration, snapshot, sql);
      final recordedChecksum = entry['checksum'];
      if (migration['checksum'] != expectedChecksum || recordedChecksum != expectedChecksum) {
        throw FormatException('Migration $migrationId checksum does not match its artifacts.');
      }
      _validateSnapshot(snapshot);
      _validatePhases(migration, sql);
      parentId = migrationId;
      finalSnapshot = snapshot;
    }
    if (finalSnapshot == null) {
      throw const FormatException('A Rivet journal must contain at least one migration.');
    }
    if (declaration != null &&
        canonicalJson(_physicalSnapshot(finalSnapshot)) !=
            canonicalJson(_physicalDeclaration(declaration))) {
      throw const FormatException(
        'The current composed Rivet schema does not match the final migration snapshot.',
      );
    }
  }

  void _expectVersion(Map<String, Object?> value, String source) {
    if (value['formatVersion'] != 1 || value['dialect'] != 'rivet') {
      throw FormatException('$source has an unknown format version or dialect.');
    }
  }

  void _validateSnapshot(Map<String, Object?> snapshot) {
    final ids = <String>{};
    final schemaIds = <String>{};
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
            if (childGroup == 'columns' && child['tableId'] != value['id']) {
              throw FormatException('Column $id references the wrong table.');
            }
          }
        }
      }
    }
    _list(snapshot['requirements'], 'snapshot requirements');
  }

  void _validatePhases(Map<String, Object?> migration, String sql) {
    final bytes = utf8.encode(sql);
    final phaseIds = <String>{};
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
      if (phase['mode'] == 'transactional' && phase['recovery'] != null) {
        throw FormatException('Transactional phase $phaseId cannot have recovery metadata.');
      }
      var previousEnd = -1;
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
        final statementSql = utf8.decode(bytes.sublist(start, end)).trim();
        if (!statementSql.endsWith(';') ||
            statementSql.substring(0, statementSql.length - 1).contains(';')) {
          throw FormatException('Phase $phaseId byte range is not one complete statement.');
        }
        previousEnd = end;
      }
    }
  }

  Map<String, Object?> _physicalSnapshot(Map<String, Object?> snapshot) {
    final schemaNames = <String, String>{
      for (final raw in _list(snapshot['schemas'], 'snapshot schemas'))
        (_map(raw, 'schema')['id']! as String): _map(raw, 'schema')['name']! as String,
    };
    final tables = [
      for (final raw in _list(snapshot['tables'], 'snapshot tables'))
        _stripSnapshotTable(_map(raw, 'snapshot table'), schemaNames),
    ]..sort(_byPhysicalName);
    return {
      'formatVersion': 1,
      'dialect': 'rivet',
      'name': null,
      'tables': tables,
      'enums': _list(snapshot['enums'], 'snapshot enums'),
      'requirements': _list(snapshot['requirements'], 'snapshot requirements'),
    };
  }

  Map<String, Object?> _physicalDeclaration(Map<String, Object?> declaration) {
    final normalized = normalizeDeclaration(declaration);
    final tables = [
      for (final raw in _list(normalized['tables'], 'declaration tables'))
        _withoutRenameHints(_map(raw, 'declaration table'))! as Map<String, Object?>,
    ]..sort(_byPhysicalName);
    return {
      'formatVersion': 1,
      'dialect': 'rivet',
      'name': null,
      'tables': tables,
      'enums': _withoutRenameHints(_list(normalized['enums'], 'declaration enums')),
      'requirements': _list(normalized['requirements'], 'declaration requirements'),
    };
  }

  Map<String, Object?> _stripSnapshotTable(
    Map<String, Object?> table,
    Map<String, String> schemaNames,
  ) => {
    'schema': schemaNames[table['schemaId']],
    'name': table['name'],
    'columns': [
      for (final raw in _list(table['columns'], 'table columns'))
        _withoutKeys(_map(raw, 'table column'), {'id', 'tableId'}),
    ],
    'indexes': table['indexes'],
    'constraints': table['constraints'],
  };

  int _byPhysicalName(Map<String, Object?> left, Map<String, Object?> right) =>
      '${left['schema']}.${left['name']}'.compareTo('${right['schema']}.${right['name']}');

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
