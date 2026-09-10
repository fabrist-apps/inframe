import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:clickhouse/src/clickhouse_exception.dart';
import 'package:clickhouse/src/clickhouse_query_result.dart';

/// A reusable HTTP client for bounded ClickHouse operations.
final class ClickHouseClient {
  /// Creates a client that owns one HTTP connection pool.
  factory ClickHouseClient({
    required String endpoint,
    required String database,
    required String username,
    required String password,
    Duration timeout = const Duration(seconds: 30),
    int maxRequestBytes = 16 * 1024 * 1024,
    int maxResponseBytes = 16 * 1024 * 1024,
  }) {
    final parsedEndpoint = _parseEndpoint(endpoint);
    final validatedTimeout = _requirePositiveDuration(timeout, 'timeout');
    _requirePositiveInt(maxRequestBytes, 'maxRequestBytes');
    _requirePositiveInt(maxResponseBytes, 'maxResponseBytes');
    return ClickHouseClient._(
      endpoint: parsedEndpoint,
      database: database,
      username: username,
      password: password,
      timeout: validatedTimeout,
      httpClient: HttpClient(),
    );
  }

  ClickHouseClient._({
    required this._endpoint,
    required this._database,
    required this._username,
    required this._password,
    required this._timeout,
    required this._httpClient,
  });

  final Uri _endpoint;
  final String _database;
  final String _username;
  final String _password;
  final Duration _timeout;
  final HttpClient _httpClient;
  var _closed = false;

  /// Runs [sql] and returns the complete validated result.
  Future<ClickHouseQueryResult> query(
    String sql, {
    Map<String, String> parameters = const {},
    Duration? timeout,
  }) async {
    _ensureOpen();
    final operationTimeout = _operationTimeout(timeout);
    final requestUri = _requestUri(parameters);
    final body = utf8.encode(sql);

    try {
      return await _query(requestUri, body).timeout(operationTimeout);
    } on ClickHouseException {
      rethrow;
    } on TimeoutException {
      throw ClickHouseTimeoutException(
        message:
            'ClickHouse query exceeded its ${operationTimeout.inMicroseconds} microsecond deadline.',
        requestState: ClickHouseRequestState.mayHaveReachedServer,
      );
    } on FormatException catch (error) {
      throw ClickHouseProtocolException(
        message: 'ClickHouse returned malformed JSON: $error',
        requestState: ClickHouseRequestState.mayHaveReachedServer,
      );
    } on IOException catch (error) {
      throw ClickHouseTransportException(
        message: 'ClickHouse query transport failed: $error',
        requestState: ClickHouseRequestState.mayHaveReachedServer,
        cause: error,
      );
    }
  }

  /// Stops accepting operations, waits for active work, and closes connections.
  Future<void> close() {
    if (!_closed) {
      _closed = true;
      _httpClient.close();
    }
    return Future<void>.value();
  }

  Future<ClickHouseQueryResult> _query(Uri uri, List<int> body) async {
    final request = await _httpClient.postUrl(uri);
    request.headers
      ..set('x-clickhouse-user', _username)
      ..set('x-clickhouse-key', _password)
      ..set('x-clickhouse-format', 'JSON')
      ..contentType = ContentType.text;
    request.add(body);

    final response = await request.close();
    final responseBody = await response.fold<List<int>>(
      <int>[],
      (bytes, chunk) => bytes..addAll(chunk),
    );
    final queryId = response.headers.value('x-clickhouse-query-id');
    if (response.statusCode != HttpStatus.ok) {
      throw _serverException(response.statusCode, responseBody, queryId);
    }

    final responseText = utf8.decode(responseBody);
    try {
      return _decodeQueryResult(responseText, queryId);
    } on FormatException {
      final errorCode = _clickHouseErrorCode(responseText);
      if (errorCode != null) {
        throw ClickHouseServerException(
          message: responseText.trim(),
          requestState: ClickHouseRequestState.mayHaveReachedServer,
          queryId: queryId,
          statusCode: response.statusCode,
          clickHouseCode: errorCode,
        );
      }
      rethrow;
    }
  }

  Uri _requestUri(Map<String, String> parameters) => _endpoint.replace(
    queryParameters: <String, String>{
      'database': _database,
      for (final entry in parameters.entries)
        'param_${entry.key}': _escapeParameterValue(entry.value),
    },
  );

  Duration _operationTimeout(Duration? timeout) =>
      timeout == null ? _timeout : _requirePositiveDuration(timeout, 'timeout');

  void _ensureOpen() {
    if (_closed) {
      throw StateError('The ClickHouse client is closed.');
    }
  }
}

Uri _parseEndpoint(String endpoint) {
  final uri = Uri.tryParse(endpoint);
  if (uri == null ||
      (uri.scheme != 'http' && uri.scheme != 'https') ||
      !uri.hasAuthority ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment) {
    throw ArgumentError.value(
      endpoint,
      'endpoint',
      'Must be an HTTP(S) URL with a host and no credentials, query, or fragment.',
    );
  }
  return uri.path.isEmpty ? uri.replace(path: '/') : uri;
}

Duration _requirePositiveDuration(Duration value, String name) {
  if (value <= Duration.zero) {
    throw ArgumentError.value(value, name, 'Must be positive.');
  }
  return value;
}

int _requirePositiveInt(int value, String name) {
  if (value <= 0) {
    throw ArgumentError.value(value, name, 'Must be positive.');
  }
  return value;
}

ClickHouseQueryResult _decodeQueryResult(String responseBody, String? queryId) {
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

ClickHouseServerException _serverException(int statusCode, List<int> body, String? queryId) {
  final message = utf8.decode(body, allowMalformed: true).trim();
  return ClickHouseServerException(
    message: message.isEmpty ? 'ClickHouse rejected the request with HTTP $statusCode.' : message,
    requestState: ClickHouseRequestState.mayHaveReachedServer,
    queryId: queryId,
    statusCode: statusCode,
    clickHouseCode: _clickHouseErrorCode(message),
  );
}

int? _clickHouseErrorCode(String message) {
  final match = RegExp(r'Code: (\d+)').firstMatch(message);
  return match == null ? null : int.tryParse(match.group(1)!);
}

String _escapeParameterValue(String value) =>
    value.replaceAll(r'\', r'\\').replaceAll('\t', r'\t').replaceAll('\n', r'\n');
