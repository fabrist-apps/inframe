import 'dart:convert';

/// Quotes [identifier] as one ClickHouse identifier.
String quoteIdentifier(String identifier) {
  if (identifier.isEmpty || identifier.contains('\u0000')) {
    throw ArgumentError.value(identifier, 'table', 'Must be a non-empty identifier without NUL.');
  }
  final escaped = identifier.replaceAll(r'\', r'\\').replaceAll('`', r'\`');
  return '`$escaped`';
}

/// Encodes a complete JSONEachRow batch before any request can be sent.
String encodeRows(List<Map<String, Object?>> rows) {
  final encoder = JsonEncoder((value) => throw JsonUnsupportedObjectError(value));
  final batch = StringBuffer();
  for (var index = 0; index < rows.length; index += 1) {
    try {
      batch.writeln(encoder.convert(rows[index]));
    } on JsonUnsupportedObjectError {
      throw ArgumentError.value(
        rows[index],
        'rows[$index]',
        'Must contain only JSON-compatible values without cycles.',
      );
    }
  }
  return batch.toString();
}
