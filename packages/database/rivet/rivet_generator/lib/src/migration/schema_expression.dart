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
};

Map<String, Object?> _normalizeColumn(Map<String, Object?> column) {
  final expression = column['default'];
  return {
    ...column,
    if (expression is Map<String, Object?> && expression['kind'] == 'sql')
      'default': parseSchemaExpression(expression['sql']! as String),
  };
}

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
  throw UnsupportedError('Unsupported Rivet schema expression `$source`.');
}

String renderSchemaExpression(Map<String, Object?> expression) => switch (expression['kind']) {
  'literal' => switch (expression['literalType']) {
    'boolean' => expression['value'] == true ? 'true' : 'false',
    'null' => 'null',
    'decimal' => expression['value']! as String,
    'string' => "'${(expression['value']! as String).replaceAll("'", "''")}'",
    _ => throw const FormatException('Unknown Rivet schema literal type.'),
  },
  'function' =>
    '${expression['name']}(${(expression['arguments']! as List<Object?>).map((value) => renderSchemaExpression(value! as Map<String, Object?>)).join(', ')})',
  _ => throw const FormatException('Unknown Rivet schema expression kind.'),
};
