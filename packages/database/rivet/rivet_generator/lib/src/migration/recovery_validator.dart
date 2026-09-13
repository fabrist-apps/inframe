// Recovery metadata is data consumed by the later migration runner.
// ignore_for_file: public_member_api_docs

void validateRivetRecovery(Map<String, Object?> phase, List<String> statements) {
  final mode = phase['mode'];
  final recovery = phase['recovery'];
  final concurrent = statements.any(
    (sql) => RegExp(
      r'^\s*create\s+(unique\s+)?index\s+concurrently\b',
      caseSensitive: false,
    ).hasMatch(sql),
  );
  if (mode == 'transactional') {
    if (recovery != null) {
      throw const FormatException('Transactional phases must have null recovery metadata.');
    }
    if (concurrent) {
      throw const FormatException('CREATE INDEX CONCURRENTLY requires a nontransactional phase.');
    }
    return;
  }
  if (mode != 'nontransactional' || recovery is! Map<String, Object?>) {
    throw const FormatException('Nontransactional phases require recovery metadata.');
  }
  final operationId = recovery['operationId'];
  if (operationId is! String || !RegExp(r'^[0-9a-f]{32}$').hasMatch(operationId)) {
    throw const FormatException('Recovery operationId must be a Rivet identity.');
  }
  if (recovery['before'] is! Map<String, Object?> || recovery['after'] is! Map<String, Object?>) {
    throw const FormatException('Recovery requires before and after object descriptions.');
  }
  if (recovery['kind'] == 'manual') {
    if (recovery['checks'] != null || recovery['inspector'] != null) {
      throw const FormatException('Manual recovery cannot claim automated checks.');
    }
    return;
  }
  if (recovery['kind'] != 'catalog') {
    throw FormatException('Unsupported recovery kind `${recovery['kind']}`.');
  }
  final inspector = recovery['inspector'];
  final checks = recovery['checks'];
  if (inspector == null && checks == null) {
    throw const FormatException('Catalog recovery requires checks or an inspector.');
  }
  if (inspector != null && inspector != 'postgresql.index.v1') {
    throw FormatException('Unsupported recovery inspector `$inspector`.');
  }
  if (checks != null) _validateChecks(checks);
  if (concurrent) {
    if (inspector != 'postgresql.index.v1') {
      throw const FormatException(
        'Concurrent index recovery requires the postgresql.index.v1 inspector.',
      );
    }
    _validateIndex(recovery['after']! as Map<String, Object?>);
  }
}

void _validateChecks(Object? value) {
  if (value is! List<Object?> || value.isEmpty) {
    throw const FormatException('Recovery checks must be a nonempty array.');
  }
  for (final raw in value) {
    if (raw is! Map<String, Object?> ||
        raw['sql'] is! String ||
        raw['parameters'] is! List<Object?> ||
        raw['expected'] is! bool) {
      throw const FormatException('Recovery checks require SQL, parameters, and a boolean result.');
    }
    final sql = (raw['sql']! as String).trim().toLowerCase();
    if (!(sql.startsWith('select ') || sql.startsWith('with ')) ||
        RegExp(r'\b(insert|update|delete|alter|create|drop|copy|vacuum|call|do|set)\b')
            .hasMatch(sql) ||
        RegExp(r'\b(dblink|postgres_fdw)\b').hasMatch(sql)) {
      throw const FormatException('Recovery checks must be read-only SQL.');
    }
    for (final parameter in raw['parameters']! as List<Object?>) {
      if (parameter is! Map<String, Object?> ||
          !const {'null', 'boolean', 'decimal', 'string'}.contains(parameter['type']) ||
          !parameter.containsKey('value') ||
          !_matchesLiteralType(parameter['type']! as String, parameter['value'])) {
        throw const FormatException('Recovery check parameters must be typed literals.');
      }
    }
  }
}

bool _matchesLiteralType(String type, Object? value) => switch (type) {
  'null' => value == null,
  'boolean' => value is bool,
  'decimal' => value is String && RegExp(r'^-?(0|[1-9][0-9]*)(\.[0-9]+)?$').hasMatch(value),
  'string' => value is String,
  _ => false,
};

void _validateIndex(Map<String, Object?> after) {
  const required = {
    'schema',
    'table',
    'index',
    'method',
    'terms',
    'predicate',
    'options',
    'unique',
    'valid',
    'ready',
  };
  if (!after.keys.toSet().containsAll(required) ||
      after['schema'] is! String ||
      after['table'] is! String ||
      after['index'] is! String ||
      after['method'] != 'btree' ||
      after['terms'] is! List<Object?> ||
      after['options'] is! Map<String, Object?> ||
      after['unique'] is! bool ||
      after['valid'] != true ||
      after['ready'] != true) {
    throw const FormatException(
      'Concurrent index recovery must describe qualified structure, uniqueness, validity, and readiness.',
    );
  }
  for (final term in after['terms']! as List<Object?>) {
    if (term is! Map<String, Object?> || term['column'] is! String || term['descending'] is! bool) {
      throw const FormatException(
        'Concurrent btree index terms must be ordered column descriptors.',
      );
    }
  }
}
