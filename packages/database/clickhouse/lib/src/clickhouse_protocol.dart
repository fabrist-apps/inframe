import 'dart:collection';
import 'dart:convert';

import 'package:clickhouse/src/clickhouse_exception.dart';
import 'package:clickhouse/src/clickhouse_query_result.dart';

/// Parses and validates a ClickHouse HTTPS endpoint.
Uri parseEndpoint(String endpoint, {required bool allowInsecureHttp}) {
  final uri = Uri.tryParse(endpoint);
  if (uri == null ||
      (uri.scheme != 'https' && !(allowInsecureHttp && uri.scheme == 'http')) ||
      !uri.hasAuthority ||
      uri.host.isEmpty ||
      _hasCredentialDelimiter(endpoint) ||
      uri.hasQuery ||
      uri.hasFragment) {
    throw ArgumentError.value(
      endpoint,
      'endpoint',
      'Must be an HTTPS URL with a host and no credentials, query, or fragment. '
          'Plaintext HTTP requires allowInsecureHttp.',
    );
  }
  return uri.path.isEmpty ? uri.replace(path: '/') : uri;
}

bool _hasCredentialDelimiter(String endpoint) =>
    RegExp('^https?://[^/?#]*@', caseSensitive: false).hasMatch(endpoint);

/// Validates a positive duration and returns it unchanged.
Duration requirePositiveDuration(Duration value, String name) {
  if (value <= Duration.zero) {
    throw ArgumentError.value(value, name, 'Must be positive.');
  }
  return value;
}

/// Validates a positive integer and returns it unchanged.
int requirePositiveInt(int value, String name) {
  if (value <= 0) {
    throw ArgumentError.value(value, name, 'Must be positive.');
  }
  return value;
}

/// Decodes and validates one buffered ClickHouse JSON query response.
ClickHouseQueryResult decodeQueryResult(String responseBody) {
  final decoded = jsonDecode(responseBody);
  if (decoded is! Map<String, Object?>) {
    throw const FormatException('The response root must be a JSON object.');
  }
  final metadata = decoded['meta'];
  final data = decoded['data'];
  final rowCount = decoded['rows'];
  if (metadata is! List<Object?> ||
      data is! List<Object?> ||
      rowCount is! int ||
      rowCount != data.length) {
    throw const FormatException('The response must contain matching meta, data, and rows fields.');
  }

  final columns = <ClickHouseColumn>[];
  final columnNames = <String>{};
  for (final value in metadata) {
    if (value is! Map<String, Object?> || value['name'] is! String || value['type'] is! String) {
      throw const FormatException('Each metadata entry must contain string name and type fields.');
    }
    final name = value['name']! as String;
    if (!columnNames.add(name)) {
      throw FormatException('ClickHouse returned duplicate column name "$name".');
    }
    columns.add(ClickHouseColumn(name: name, type: value['type']! as String));
  }

  final rows = <Map<String, Object?>>[];
  for (final value in data) {
    if (value is! Map<String, Object?> ||
        value.length != columnNames.length ||
        !value.keys.every(columnNames.contains)) {
      throw const FormatException('Each data row must match the response metadata.');
    }
    rows.add(value);
  }
  return ClickHouseQueryResult(columns: columns, rows: rows);
}

/// Quotes [identifier] as one ClickHouse identifier.
String quoteIdentifier(String identifier) {
  if (identifier.isEmpty || identifier.contains('\u0000')) {
    throw ArgumentError.value(identifier, 'table', 'Must be a non-empty identifier without NUL.');
  }
  final escaped = identifier.replaceAll(r'\', r'\\').replaceAll('`', r'\`');
  return '`$escaped`';
}

/// Validates and encodes a complete JSONEachRow batch.
String encodeRows(List<Map<String, Object?>> rows) {
  final activeContainers = HashSet<Object>.identity();
  for (final row in rows) {
    _validateJsonValue(row, 'rows', activeContainers);
  }
  return rows.map(jsonEncode).map((row) => '$row\n').join();
}

void _validateJsonValue(Object? value, String path, Set<Object> activeContainers) {
  switch (value) {
    case null || bool() || String():
      return;
    case final num number when number.isFinite:
      return;
    case final List<Object?> values:
      _validateContainer(values, path, activeContainers, () {
        for (var index = 0; index < values.length; index += 1) {
          _validateJsonValue(values[index], '$path[$index]', activeContainers);
        }
      });
    case final Map<Object?, Object?> map:
      _validateContainer(map, path, activeContainers, () {
        for (final entry in map.entries) {
          if (entry.key is! String) {
            throw ArgumentError.value(value, path, 'JSON object keys must be strings.');
          }
          _validateJsonValue(entry.value, '$path.${entry.key}', activeContainers);
        }
      });
    default:
      throw ArgumentError.value(value, path, 'Must contain only JSON-compatible values.');
  }
}

void _validateContainer(
  Object container,
  String path,
  Set<Object> activeContainers,
  void Function() validateChildren,
) {
  if (!activeContainers.add(container)) {
    throw ArgumentError.value(container, path, 'JSON containers must not contain cycles.');
  }
  try {
    validateChildren();
  } finally {
    activeContainers.remove(container);
  }
}

/// Creates a structured exception from a ClickHouse error response.
ClickHouseServerException serverException(
  int statusCode,
  List<int> body,
  String? queryId,
  int? headerCode,
) {
  final message = utf8.decode(body, allowMalformed: true).trim();
  return ClickHouseServerException(
    message: message.isEmpty ? 'ClickHouse rejected the request with HTTP $statusCode.' : message,
    requestState: ClickHouseRequestState.mayHaveReachedServer,
    queryId: queryId,
    statusCode: statusCode,
    clickHouseCode: headerCode ?? errorCode(message),
  );
}

/// Extracts a ClickHouse error code from its textual error representation.
int? errorCode(String message) {
  final match = RegExp(r'Code: (\d+)').firstMatch(message);
  return match == null ? null : int.tryParse(match.group(1)!);
}

/// Applies ClickHouse's HTTP query-parameter escaping to one textual value.
String escapeParameterValue(String value) =>
    value.replaceAll(r'\', r'\\').replaceAll('\t', r'\t').replaceAll('\n', r'\n');
