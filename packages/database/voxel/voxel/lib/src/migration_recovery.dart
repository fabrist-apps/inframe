/// The safely established state of an interrupted nontransactional phase.
enum VoxelRecoveryClassification {
  /// Every observation equals its declared postcondition.
  completed,

  /// Every observation equals the exact complement of its postcondition.
  notStarted,

  /// Observations are mixed, incomplete, or malformed.
  uncertain,
}

/// One validated, read-only catalog query used to recover a migration phase.
final class VoxelRecoveryCheck {
  VoxelRecoveryCheck._({
    required this.sql,
    required List<Object?> parameters,
    required this.expected,
    required this._kind,
  }) : parameters = List.unmodifiable(parameters);

  final _CatalogCheckKind _kind;

  /// The single read-only statement to execute.
  final String sql;

  /// Driver-ready values decoded from the artifact's typed literals.
  final List<Object?> parameters;

  /// The scalar boolean value that proves the postcondition.
  final bool expected;
}

/// Validated recovery checks and their exact-state classifier.
final class VoxelRecoveryCheckPlan {
  /// Parses catalog checks for one attached database scope.
  ///
  /// Version 1 accepts an identity-absence `SELECT` and a structural-match
  /// `SELECT` over the target scope's `sqlite_schema`. Together they compare
  /// object type, qualified ownership, name, and stored SQL so existence alone
  /// cannot certify completion and a conflicting object cannot authorize retry.
  factory VoxelRecoveryCheckPlan.parse(
    Object? value, {
    required String scopeName,
  }) {
    if (scopeName.isEmpty) {
      throw const FormatException('Recovery check scope must not be empty.');
    }
    if (value is! List<Object?> || value.isEmpty) {
      throw const FormatException('Recovery checks must be a nonempty array.');
    }
    final checks = [
      for (final raw in value) _parseCheck(raw, scopeName: scopeName),
    ];
    if (checks.length != 2 ||
        checks.where((check) => check._kind == _CatalogCheckKind.identityAbsent).length != 1 ||
        checks.where((check) => check._kind == _CatalogCheckKind.structureMatches).length != 1) {
      throw const FormatException(
        'Recovery requires one identity-absence check and one structural-match check.',
      );
    }
    return VoxelRecoveryCheckPlan._(checks);
  }

  VoxelRecoveryCheckPlan._(List<VoxelRecoveryCheck> checks) : checks = List.unmodifiable(checks);

  /// The checks in artifact order.
  final List<VoxelRecoveryCheck> checks;

  /// Classifies scalar observations without treating ambiguity as retry proof.
  VoxelRecoveryClassification classify(Iterable<Object?> results) {
    final values = results.toList(growable: false);
    if (values.length != checks.length) {
      return VoxelRecoveryClassification.uncertain;
    }
    final observations = <bool>[];
    for (final value in values) {
      final observation = _scalarBoolean(value);
      if (observation == null) return VoxelRecoveryClassification.uncertain;
      observations.add(observation);
    }
    if (_matches(observations, complement: false)) {
      return VoxelRecoveryClassification.completed;
    }
    if (_matches(observations, complement: true)) {
      return VoxelRecoveryClassification.notStarted;
    }
    return VoxelRecoveryClassification.uncertain;
  }

  bool _matches(List<bool> observations, {required bool complement}) {
    for (var index = 0; index < checks.length; index++) {
      final expected = complement ? !checks[index].expected : checks[index].expected;
      if (observations[index] != expected) return false;
    }
    return true;
  }
}

VoxelRecoveryCheck _parseCheck(Object? raw, {required String scopeName}) {
  if (raw is! Map<String, Object?> ||
      raw.keys.toSet().difference(const {'sql', 'parameters', 'expected'}).isNotEmpty ||
      raw.length != 3 ||
      raw['sql'] is! String ||
      raw['parameters'] is! List<Object?> ||
      raw['expected'] is! bool) {
    throw const FormatException(
      'Recovery checks require only SQL, parameters, and a boolean result.',
    );
  }
  final sql = raw['sql']! as String;
  final tokens = _tokenize(sql);
  final kind = _validateSql(tokens, scopeName: scopeName);
  final expected = raw['expected']! as bool;
  if ((kind == _CatalogCheckKind.identityAbsent && expected) ||
      (kind == _CatalogCheckKind.structureMatches && !expected)) {
    throw const FormatException(
      'Recovery postconditions require absence=false and structural match=true.',
    );
  }
  final parameters = [
    for (final parameter in raw['parameters']! as List<Object?>) _parseParameter(parameter),
  ];
  if (tokens.where((token) => token.kind == _TokenKind.parameter).length != parameters.length) {
    throw const FormatException('Recovery check parameter count does not match its SQL.');
  }
  return VoxelRecoveryCheck._(
    sql: sql,
    parameters: parameters,
    expected: expected,
    kind: kind,
  );
}

Object? _parseParameter(Object? raw) {
  if (raw is! Map<String, Object?> ||
      raw.keys.toSet().difference(const {'type', 'value'}).isNotEmpty ||
      raw.length != 2 ||
      raw['type'] is! String ||
      !raw.containsKey('value')) {
    throw const FormatException('Recovery check parameters must be typed literals.');
  }
  final value = raw['value'];
  return switch (raw['type']) {
    'null' when value == null => null,
    'boolean' when value is bool => value ? BigInt.one : BigInt.zero,
    'decimal' when value is String => _parseDecimal(value),
    'string' when value is String => value,
    _ => throw const FormatException('Recovery check parameter value does not match its type.'),
  };
}

Object _parseDecimal(String value) {
  if (!RegExp(r'^-?(0|[1-9][0-9]*)(\.[0-9]+)?$').hasMatch(value)) {
    throw const FormatException('Recovery decimal parameters must be canonical finite decimals.');
  }
  if (!value.contains('.')) return BigInt.parse(value);
  final parsed = double.parse(value);
  if (!parsed.isFinite) {
    throw const FormatException('Recovery decimal parameters must be finite.');
  }
  return parsed;
}

bool? _scalarBoolean(Object? value) => switch (value) {
  bool() => value,
  int() when value == 0 => false,
  int() when value == 1 => true,
  BigInt() when value == BigInt.zero => false,
  BigInt() when value == BigInt.one => true,
  _ => null,
};

const _forbiddenWords = {
  'alter',
  'analyze',
  'attach',
  'begin',
  'commit',
  'create',
  'delete',
  'detach',
  'drop',
  'insert',
  'load_extension',
  'pragma',
  'reindex',
  'release',
  'replace',
  'rollback',
  'savepoint',
  'update',
  'vacuum',
};

_CatalogCheckKind _validateSql(List<_Token> tokens, {required String scopeName}) {
  if (tokens.isEmpty || !tokens.first.isWord('select')) {
    throw const FormatException('Recovery checks must be one read-only SELECT statement.');
  }
  final semicolons = [
    for (var index = 0; index < tokens.length; index++)
      if (tokens[index].text == ';') index,
  ];
  if (semicolons.length > 1 || (semicolons.isNotEmpty && semicolons.single != tokens.length - 1)) {
    throw const FormatException('Recovery checks must contain exactly one SQL statement.');
  }
  for (final token in tokens) {
    if (token.kind == _TokenKind.word && _forbiddenWords.contains(token.text)) {
      throw const FormatException('Recovery checks must be read-only SQL.');
    }
  }
  for (var index = 0; index + 1 < tokens.length; index++) {
    if (tokens[index].kind == _TokenKind.word && tokens[index + 1].text == '(') {
      if (!tokens[index].isWord('exists')) {
        throw const FormatException('Recovery checks may not call SQL functions.');
      }
    }
  }

  var catalogReferences = 0;
  for (var index = 0; index + 2 < tokens.length; index++) {
    if (tokens[index + 1].text != '.' ||
        tokens[index].kind != _TokenKind.word ||
        tokens[index + 2].kind != _TokenKind.word) {
      continue;
    }
    if (!tokens[index + 2].isWord('sqlite_schema')) {
      throw const FormatException('Recovery checks may inspect only their target file scope.');
    }
    catalogReferences++;
    if (tokens[index].text != scopeName.toLowerCase()) {
      throw const FormatException('Recovery checks may inspect only their target file scope.');
    }
  }
  final schemaTokens = tokens.where((token) => token.isWord('sqlite_schema')).length;
  if (catalogReferences != 1 || schemaTokens != 1) {
    throw const FormatException(
      'Recovery checks must inspect one qualified target sqlite_schema catalog.',
    );
  }
  final whereIndex = tokens.indexWhere((token) => token.isWord('where'));
  if (whereIndex < 0) {
    throw const FormatException('Recovery checks must compare catalog structure.');
  }
  final predicates = tokens.sublist(whereIndex + 1);
  for (final column in const ['type', 'name', 'tbl_name']) {
    if (!_hasEqualityPredicate(predicates, column)) {
      throw const FormatException(
        'Recovery checks must compare object type, name, and owning table.',
      );
    }
  }
  final notExists = tokens.length > 2 && tokens[1].isWord('not') && tokens[2].isWord('exists');
  final exists = tokens.length > 1 && tokens[1].isWord('exists');
  if (notExists && !_hasEqualityPredicate(predicates, 'sql')) {
    return _CatalogCheckKind.identityAbsent;
  }
  if (exists && _hasEqualityPredicate(predicates, 'sql')) {
    return _CatalogCheckKind.structureMatches;
  }
  throw const FormatException(
    'Recovery checks must prove identity absence or exact structural presence.',
  );
}

bool _hasEqualityPredicate(List<_Token> tokens, String column) {
  for (var index = 0; index + 2 < tokens.length; index++) {
    if (tokens[index].isWord(column) &&
        tokens[index + 1].text == '=' &&
        tokens[index + 2].kind == _TokenKind.parameter) {
      return true;
    }
    if (tokens[index].kind == _TokenKind.parameter &&
        tokens[index + 1].text == '=' &&
        tokens[index + 2].isWord(column)) {
      return true;
    }
  }
  return false;
}

enum _TokenKind { word, string, parameter, symbol }

enum _CatalogCheckKind { identityAbsent, structureMatches }

final class _Token {
  const _Token(this.text, this.kind);

  final String text;
  final _TokenKind kind;

  bool isWord(String value) => kind == _TokenKind.word && text == value;
}

List<_Token> _tokenize(String sql) {
  final tokens = <_Token>[];
  var index = 0;
  while (index < sql.length) {
    final code = sql.codeUnitAt(index);
    if (_isWhitespace(code)) {
      index++;
      continue;
    }
    if (sql.startsWith('--', index)) {
      final newline = sql.indexOf('\n', index + 2);
      index = newline < 0 ? sql.length : newline + 1;
      continue;
    }
    if (sql.startsWith('/*', index)) {
      final end = sql.indexOf('*/', index + 2);
      if (end < 0) throw const FormatException('Recovery check contains an unterminated comment.');
      index = end + 2;
      continue;
    }
    if (code == 0x27) {
      index = _consumeQuoted(sql, index, 0x27);
      tokens.add(const _Token('', _TokenKind.string));
      continue;
    }
    if (code == 0x22) {
      final parsed = _quotedIdentifier(sql, index);
      tokens.add(_Token(parsed.value.toLowerCase(), _TokenKind.word));
      index = parsed.end;
      continue;
    }
    if (_isWordStart(code)) {
      final start = index++;
      while (index < sql.length && _isWordPart(sql.codeUnitAt(index))) {
        index++;
      }
      tokens.add(_Token(sql.substring(start, index).toLowerCase(), _TokenKind.word));
      continue;
    }
    if (code == 0x3f) {
      tokens.add(const _Token('?', _TokenKind.parameter));
      index++;
      continue;
    }
    tokens.add(_Token(sql[index], _TokenKind.symbol));
    index++;
  }
  return tokens;
}

int _consumeQuoted(String sql, int start, int quote) {
  var index = start + 1;
  while (index < sql.length) {
    if (sql.codeUnitAt(index) != quote) {
      index++;
      continue;
    }
    index++;
    if (index < sql.length && sql.codeUnitAt(index) == quote) {
      index++;
      continue;
    }
    return index;
  }
  throw const FormatException('Recovery check contains an unterminated quoted value.');
}

({String value, int end}) _quotedIdentifier(String sql, int start) {
  final value = StringBuffer();
  var index = start + 1;
  while (index < sql.length) {
    if (sql.codeUnitAt(index) != 0x22) {
      value.write(sql[index++]);
      continue;
    }
    index++;
    if (index < sql.length && sql.codeUnitAt(index) == 0x22) {
      value.write('"');
      index++;
      continue;
    }
    return (value: value.toString(), end: index);
  }
  throw const FormatException('Recovery check contains an unterminated identifier.');
}

bool _isWhitespace(int code) => code == 0x20 || (code >= 0x09 && code <= 0x0d);

bool _isWordStart(int code) =>
    (code >= 0x41 && code <= 0x5a) || (code >= 0x61 && code <= 0x7a) || code == 0x5f;

bool _isWordPart(int code) => _isWordStart(code) || (code >= 0x30 && code <= 0x39);
