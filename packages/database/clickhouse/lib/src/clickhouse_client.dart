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
    final validatedMaxRequestBytes = _requirePositiveInt(maxRequestBytes, 'maxRequestBytes');
    final validatedMaxResponseBytes = _requirePositiveInt(maxResponseBytes, 'maxResponseBytes');
    final httpClient = HttpClient()..autoUncompress = true;
    return ClickHouseClient._(
      endpoint: parsedEndpoint,
      database: database,
      username: username,
      password: password,
      timeout: validatedTimeout,
      maxRequestBytes: validatedMaxRequestBytes,
      maxResponseBytes: validatedMaxResponseBytes,
      httpClient: httpClient,
    );
  }

  ClickHouseClient._({
    required this._endpoint,
    required this._database,
    required this._username,
    required this._password,
    required this._timeout,
    required this._maxRequestBytes,
    required this._maxResponseBytes,
    required this._httpClient,
  });

  final Uri _endpoint;
  final String _database;
  final String _username;
  final String _password;
  final Duration _timeout;
  final int _maxRequestBytes;
  final int _maxResponseBytes;
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
    _ensureRequestWithinLimit(body);

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
    }
  }

  /// Executes [sql] that does not return rows.
  Future<void> command(
    String sql, {
    Map<String, String> parameters = const {},
    Duration? timeout,
  }) async {
    _ensureOpen();
    final operationTimeout = _operationTimeout(timeout);
    final body = utf8.encode(sql);
    _ensureRequestWithinLimit(body);
    await _runVoidOperation(
      uri: _requestUri(parameters),
      body: body,
      timeout: operationTimeout,
      operation: 'command',
    );
  }

  /// Inserts a completely validated [rows] batch into [table].
  Future<void> insert({
    required String table,
    required List<Map<String, Object?>> rows,
    String? deduplicationToken,
    Duration? timeout,
  }) async {
    _ensureOpen();
    final operationTimeout = _operationTimeout(timeout);
    final quotedTable = _quoteIdentifier(table);
    final encodedRows = _encodeRows(rows);
    if (rows.isEmpty) {
      return;
    }

    final body = utf8.encode('INSERT INTO $quotedTable FORMAT JSONEachRow\n$encodedRows');
    _ensureRequestWithinLimit(body);
    await _runVoidOperation(
      uri: _requestUri(
        const {},
        settings: {
          'async_insert': '0',
          'insert_deduplication_token': ?deduplicationToken,
        },
      ),
      body: body,
      timeout: operationTimeout,
      operation: 'insert',
    );
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
    final response = await _send(uri, body);
    if (response.statusCode != HttpStatus.ok) {
      throw _serverException(response.statusCode, response.body, response.queryId);
    }

    late final String responseText;
    try {
      responseText = utf8.decode(response.body);
      return _decodeQueryResult(responseText);
    } on FormatException catch (error) {
      final responseTextForError = utf8.decode(response.body, allowMalformed: true);
      final errorCode = _clickHouseErrorCode(responseTextForError);
      if (errorCode != null) {
        throw ClickHouseServerException(
          message: responseTextForError.trim(),
          requestState: ClickHouseRequestState.mayHaveReachedServer,
          queryId: response.queryId,
          statusCode: response.statusCode,
          clickHouseCode: errorCode,
        );
      }
      throw ClickHouseProtocolException(
        message: 'ClickHouse returned a malformed query result: $error',
        requestState: ClickHouseRequestState.mayHaveReachedServer,
        queryId: response.queryId,
      );
    }
  }

  Future<void> _runVoidOperation({
    required Uri uri,
    required List<int> body,
    required Duration timeout,
    required String operation,
  }) async {
    try {
      final response = await _send(uri, body).timeout(timeout);
      if (response.statusCode != HttpStatus.ok) {
        throw _serverException(response.statusCode, response.body, response.queryId);
      }
      final responseText = utf8.decode(response.body, allowMalformed: true).trim();
      final errorCode = _clickHouseErrorCode(responseText);
      if (errorCode != null) {
        throw ClickHouseServerException(
          message: responseText,
          requestState: ClickHouseRequestState.mayHaveReachedServer,
          queryId: response.queryId,
          statusCode: response.statusCode,
          clickHouseCode: errorCode,
        );
      }
      if (responseText.isNotEmpty) {
        throw ClickHouseProtocolException(
          message: 'ClickHouse returned unexpected output for a $operation.',
          requestState: ClickHouseRequestState.mayHaveReachedServer,
          queryId: response.queryId,
        );
      }
    } on ClickHouseException {
      rethrow;
    } on TimeoutException {
      throw ClickHouseTimeoutException(
        message:
            'ClickHouse $operation exceeded its ${timeout.inMicroseconds} microsecond deadline.',
        requestState: ClickHouseRequestState.mayHaveReachedServer,
      );
    }
  }

  Future<_HttpResponse> _send(Uri uri, List<int> body) async {
    HttpClientRequest? request;
    var requestState = ClickHouseRequestState.notSent;
    String? queryId;
    try {
      request = await _httpClient.postUrl(uri);
      request.headers
        ..set('x-clickhouse-user', _username)
        ..set('x-clickhouse-key', _password)
        ..set('x-clickhouse-format', 'JSON')
        ..contentType = ContentType.text;
      request
        ..contentLength = body.length
        ..add(body);

      requestState = ClickHouseRequestState.mayHaveReachedServer;
      final response = await request.close();
      queryId = response.headers.value('x-clickhouse-query-id');
      final responseBody = <int>[];
      await for (final chunk in response) {
        responseBody.addAll(chunk);
        if (responseBody.length > _maxResponseBytes) {
          throw ClickHouseSizeLimitException(
            message: 'ClickHouse response exceeded the $_maxResponseBytes byte limit.',
            requestState: requestState,
            queryId: queryId,
            direction: ClickHouseSizeLimitDirection.response,
            limit: _maxResponseBytes,
          );
        }
      }
      return _HttpResponse(
        statusCode: response.statusCode,
        body: responseBody,
        queryId: queryId,
      );
    } on ClickHouseException catch (error) {
      request?.abort(error);
      rethrow;
    } on IOException catch (error) {
      request?.abort(error);
      throw ClickHouseTransportException(
        message: 'ClickHouse HTTP transport failed: $error',
        requestState: requestState,
        queryId: queryId,
        cause: error,
      );
    }
  }

  Uri _requestUri(
    Map<String, String> parameters, {
    Map<String, String> settings = const {},
  }) => _endpoint.replace(
    queryParameters: <String, String>{
      'database': _database,
      ...settings,
      for (final entry in parameters.entries)
        'param_${entry.key}': _escapeParameterValue(entry.value),
    },
  );

  Duration _operationTimeout(Duration? timeout) =>
      timeout == null ? _timeout : _requirePositiveDuration(timeout, 'timeout');

  void _ensureRequestWithinLimit(List<int> body) {
    if (body.length > _maxRequestBytes) {
      throw ClickHouseSizeLimitException(
        message: 'ClickHouse request exceeded the $_maxRequestBytes byte limit.',
        requestState: ClickHouseRequestState.notSent,
        direction: ClickHouseSizeLimitDirection.request,
        limit: _maxRequestBytes,
      );
    }
  }

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

ClickHouseQueryResult _decodeQueryResult(String responseBody) {
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

String _quoteIdentifier(String identifier) {
  if (identifier.isEmpty || identifier.contains('\u0000')) {
    throw ArgumentError.value(identifier, 'table', 'Must be a non-empty identifier without NUL.');
  }
  final escaped = identifier.replaceAll(r'\', r'\\').replaceAll('`', r'\`');
  return '`$escaped`';
}

String _encodeRows(List<Map<String, Object?>> rows) {
  for (final row in rows) {
    _validateJsonValue(row, 'rows');
  }
  return rows.map(jsonEncode).map((row) => '$row\n').join();
}

void _validateJsonValue(Object? value, String path) {
  switch (value) {
    case null || bool() || String():
      return;
    case final num number when number.isFinite:
      return;
    case final List<Object?> values:
      for (var index = 0; index < values.length; index += 1) {
        _validateJsonValue(values[index], '$path[$index]');
      }
    case final Map<Object?, Object?> map:
      for (final entry in map.entries) {
        if (entry.key is! String) {
          throw ArgumentError.value(value, path, 'JSON object keys must be strings.');
        }
        _validateJsonValue(entry.value, '$path.${entry.key}');
      }
    default:
      throw ArgumentError.value(value, path, 'Must contain only JSON-compatible values.');
  }
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

final class _HttpResponse {
  const _HttpResponse({required this.statusCode, required this.body, required this.queryId});

  final int statusCode;
  final List<int> body;
  final String? queryId;
}
