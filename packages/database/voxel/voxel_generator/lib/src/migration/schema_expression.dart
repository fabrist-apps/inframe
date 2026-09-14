// These helpers are shared by snapshot generation and current-schema checks.
// ignore_for_file: public_member_api_docs

Map<String, Object?> normalizeDeclaration(Map<String, Object?> declaration) {
  final result = Map<String, Object?>.from(declaration);
  result['tables'] = [
    for (final rawTable in declaration['tables']! as List<Object?>)
      _normalizeTable(rawTable! as Map<String, Object?>),
  ];
  return result;
}

Map<String, Object?> _normalizeTable(Map<String, Object?> table) => {
  ...table,
  'columns': [
    for (final rawColumn in table['columns']! as List<Object?>)
      _normalizeColumn(rawColumn! as Map<String, Object?>),
  ],
  'indexes': [
    for (final rawIndex in table['indexes']! as List<Object?>)
      _normalizeIndex(rawIndex! as Map<String, Object?>),
  ],
  'constraints': [
    for (final rawConstraint in table['constraints']! as List<Object?>)
      _normalizeConstraint(rawConstraint! as Map<String, Object?>),
  ],
};

Map<String, Object?> _normalizeIndex(Map<String, Object?> index) => {
  ...index,
  if (index['predicate'] case final Map<String, Object?> predicate)
    'predicate': _normalizeExpression(predicate),
};

Map<String, Object?> _normalizeConstraint(Map<String, Object?> constraint) => {
  ...constraint,
  if (constraint['expression'] case final Map<String, Object?> expression)
    'expression': _normalizeExpression(expression),
};

Map<String, Object?> _normalizeColumn(Map<String, Object?> column) {
  final expression = column['default'];
  return {
    ...column,
    if (expression is Map<String, Object?> && expression['kind'] == 'sql')
      'default': parseSchemaExpression(expression['sql']! as String),
  };
}

Map<String, Object?> _normalizeExpression(Map<String, Object?> expression) =>
    expression['kind'] == 'sql'
    ? parseSchemaExpression(expression['sql']! as String)
    : {
        ...expression,
        if (expression['arguments'] case final List<Object?> arguments)
          'arguments': [
            for (final argument in arguments)
              _normalizeExpression(argument! as Map<String, Object?>),
          ],
      };

Map<String, Object?> parseSchemaExpression(String source) {
  final sql = source.trim();
  if (sql == 'true' || sql == 'false') {
    return {
      'formatVersion': 1,
      'kind': 'literal',
      'literalType': 'boolean',
      'value': sql == 'true',
    };
  }
  if (sql == 'null') {
    return {'formatVersion': 1, 'kind': 'literal', 'literalType': 'null', 'value': null};
  }
  if (RegExp(r'^-?(0|[1-9][0-9]*)(\.[0-9]+)?$').hasMatch(sql)) {
    return {
      'formatVersion': 1,
      'kind': 'literal',
      'literalType': 'decimal',
      'value': sql,
    };
  }
  if (sql.length >= 2 && sql.startsWith("'") && sql.endsWith("'")) {
    return {
      'formatVersion': 1,
      'kind': 'literal',
      'literalType': 'string',
      'value': sql.substring(1, sql.length - 1).replaceAll("''", "'"),
    };
  }
  final function = RegExp(r'^([a-z_][a-z0-9_]*)\((.*)\)$').firstMatch(sql);
  if (function != null && const {'now', 'gen_random_uuid', 'nextval'}.contains(function[1])) {
    final arguments = function[2]!.trim();
    return {
      'formatVersion': 1,
      'kind': 'function',
      'name': function[1],
      'arguments': arguments.isEmpty ? <Object?>[] : [parseSchemaExpression(arguments)],
    };
  }
  throw UnsupportedError('Unsupported Voxel schema expression `$source`.');
}

String renderSchemaExpression(
  Map<String, Object?> expression, {
  String Function(String objectId)? resolveReference,
}) => switch (expression['kind']) {
  'literal' => switch (expression['literalType']) {
    'boolean' => expression['value'] == true ? 'true' : 'false',
    'null' => 'null',
    'decimal' => expression['value']! as String,
    'string' => "'${(expression['value']! as String).replaceAll("'", "''")}'",
    _ => throw const FormatException('Unknown Voxel schema literal type.'),
  },
  'function' =>
    '${expression['name']}(${(expression['arguments']! as List<Object?>).map((value) => renderSchemaExpression(value! as Map<String, Object?>, resolveReference: resolveReference)).join(', ')})',
  'reference' => _quoteReference(
    (resolveReference ??
        (String _) => throw const FormatException('A schema reference resolver is required.'))(
      expression['objectId']! as String,
    ),
  ),
  'operator' => _renderOperator(expression, resolveReference),
  _ => throw const FormatException('Unknown Voxel schema expression kind.'),
};

String _renderOperator(
  Map<String, Object?> expression,
  String Function(String objectId)? resolveReference,
) {
  final operator = expression['operator']! as String;
  final arguments = (expression['arguments']! as List<Object?>)
      .cast<Map<String, Object?>>()
      .map((argument) => renderSchemaExpression(argument, resolveReference: resolveReference))
      .toList(growable: false);
  return switch (operator) {
    'NOT' when arguments.length == 1 => 'NOT (${arguments.single})',
    'IS NULL' when arguments.length == 1 => '${arguments.single} IS NULL',
    '=' ||
    '<' ||
    '+' ||
    'AND' ||
    'OR' when arguments.length == 2 => '(${arguments.first} $operator ${arguments.last})',
    _ => throw FormatException('Unsupported Voxel schema operator `$operator`.'),
  };
}

String _quoteReference(String value) => '"${value.replaceAll('"', '""')}"';
