import 'dart:async';
import 'dart:convert';

import 'package:clickhouse/src/deadline.dart';
import 'package:clickhouse/src/exception.dart';
import 'package:clickhouse/src/insert.dart' as insertion;
import 'package:clickhouse/src/query_result.dart';
import 'package:clickhouse/src/transport.dart';

/// A reusable HTTP client for bounded ClickHouse operations.
final class ClickHouseClient {
  /// Creates a client that owns one HTTP connection pool.
  ///
  /// [endpoint] must use HTTPS, include a host, and contain no credentials,
  /// query, or fragment. Its path is preserved for reverse proxies. Set
  /// [allowInsecureHttp] only for isolated environments that require plaintext
  /// HTTP. [timeout], [maxRequestBytes], and [maxResponseBytes] must be
  /// positive. An empty [password] is allowed.
  factory ClickHouseClient({
    required String endpoint,
    required String database,
    required String username,
    required String password,
    Duration timeout = const Duration(seconds: 30),
    int maxRequestBytes = 16 * 1024 * 1024,
    int maxResponseBytes = 16 * 1024 * 1024,
    bool allowInsecureHttp = false,
  }) {
    final parsedEndpoint = _parseEndpoint(
      endpoint,
      allowInsecureHttp: allowInsecureHttp,
    );
    final validatedTimeout = _requirePositiveDuration(timeout, 'timeout');
    final validatedMaxRequestBytes = _requirePositiveInt(maxRequestBytes, 'maxRequestBytes');
    final validatedMaxResponseBytes = _requirePositiveInt(maxResponseBytes, 'maxResponseBytes');
    return ClickHouseClient._(
      endpoint: parsedEndpoint,
      database: database,
      timeout: validatedTimeout,
      maxRequestBytes: validatedMaxRequestBytes,
      transport: ClickHouseHttpTransport(
        username: username,
        password: password,
        maxResponseBytes: validatedMaxResponseBytes,
      ),
    );
  }

  ClickHouseClient._({
    required this._endpoint,
    required this._database,
    required this._timeout,
    required this._maxRequestBytes,
    required this._transport,
  });

  final Uri _endpoint;
  final String _database;
  final Duration _timeout;
  final int _maxRequestBytes;
  final ClickHouseHttpTransport _transport;
  var _activeOperations = 0;
  Completer<void>? _becameIdle;
  Future<void>? _closeFuture;

  /// Runs [sql] and returns the complete validated result.
  ///
  /// [parameters] contains unquoted ClickHouse textual values for placeholders
  /// declared in [sql] as `{name:Type}`. The server validates their types. A
  /// positive [timeout] overrides the client default for this operation.
  Future<ClickHouseQueryResult> query(
    String sql, {
    Map<String, String> parameters = const {},
    Duration? timeout,
  }) => _runOperation(timeout, 'query', (deadline) async {
    final requestUri = _requestUri(parameters);
    final body = utf8.encode(sql);
    deadline.check(ClickHouseRequestState.notSent);
    _ensureRequestWithinLimit(body);
    return _query(requestUri, body, deadline);
  });

  /// Executes [sql] that does not return rows.
  ///
  /// Completion means ClickHouse acknowledged the command. A failed command
  /// whose exception is marked [ClickHouseRequestState.mayHaveReachedServer]
  /// can have an unknown outcome.
  Future<void> command(
    String sql, {
    Map<String, String> parameters = const {},
    Duration? timeout,
  }) => _runOperation(timeout, 'command', (deadline) async {
    final body = utf8.encode(sql);
    deadline.check(ClickHouseRequestState.notSent);
    _ensureRequestWithinLimit(body);
    await _runVoidOperation(
      uri: _requestUri(parameters),
      body: body,
      operation: 'command',
      deadline: deadline,
    );
  });

  /// Inserts a completely validated [rows] batch into [table].
  ///
  /// [table] is quoted as one identifier in the configured database. Rows must
  /// contain recursively JSON-compatible values. An empty batch succeeds
  /// without a request after validation. [deduplicationToken] is passed to
  /// ClickHouse without providing an exactly-once guarantee.
  Future<void> insert({
    required String table,
    required List<Map<String, Object?>> rows,
    String? deduplicationToken,
    Duration? timeout,
  }) => _runOperation(timeout, 'insert', (deadline) async {
    final quotedTable = insertion.quoteIdentifier(table);
    final encodedRows = insertion.encodeRows(rows);
    deadline.check(ClickHouseRequestState.notSent);
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
      operation: 'insert',
      deadline: deadline,
    );
  });

  /// Stops accepting operations, waits for active work, and closes connections.
  ///
  /// New work fails with [StateError] as soon as shutdown begins. Accepted
  /// operations keep their existing deadlines. Repeated calls return the same
  /// shutdown future.
  Future<void> close() => _closeFuture ??= _closeWhenIdle();

  Future<void> _closeWhenIdle() async {
    if (_activeOperations > 0) {
      _becameIdle = Completer<void>();
      await _becameIdle!.future;
    }
    _transport.close();
  }

  Future<ClickHouseQueryResult> _query(Uri uri, List<int> body, ClickHouseDeadline deadline) async {
    final response = await _transport.send(uri, body, deadline);
    final result = response.decodeQuery();
    deadline.check(
      ClickHouseRequestState.mayHaveReachedServer,
      queryId: response.queryId,
    );
    return result;
  }

  Future<void> _runVoidOperation({
    required Uri uri,
    required List<int> body,
    required String operation,
    required ClickHouseDeadline deadline,
  }) async {
    final response = await _transport.send(uri, body, deadline);
    response.expectEmpty(operation);
    deadline.check(
      ClickHouseRequestState.mayHaveReachedServer,
      queryId: response.queryId,
    );
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

  Future<T> _runOperation<T>(
    Duration? timeout,
    String operation,
    Future<T> Function(ClickHouseDeadline deadline) run,
  ) async {
    if (_closeFuture != null) {
      throw StateError('The ClickHouse client is closing or closed.');
    }
    final deadline = ClickHouseDeadline(
      operation,
      timeout == null ? _timeout : _requirePositiveDuration(timeout, 'timeout'),
    );
    _activeOperations += 1;
    try {
      return await run(deadline);
    } finally {
      _activeOperations -= 1;
      if (_activeOperations == 0) {
        _becameIdle?.complete();
        _becameIdle = null;
      }
    }
  }

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
}

/// Parses and validates a ClickHouse HTTPS endpoint.
Uri _parseEndpoint(String endpoint, {required bool allowInsecureHttp}) {
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
Duration _requirePositiveDuration(Duration value, String name) {
  if (value <= Duration.zero) {
    throw ArgumentError.value(value, name, 'Must be positive.');
  }
  return value;
}

/// Validates a positive integer and returns it unchanged.
int _requirePositiveInt(int value, String name) {
  if (value <= 0) {
    throw ArgumentError.value(value, name, 'Must be positive.');
  }
  return value;
}

/// Applies ClickHouse's HTTP query-parameter escaping to one textual value.
String _escapeParameterValue(String value) =>
    value.replaceAll(r'\', r'\\').replaceAll('\t', r'\t').replaceAll('\n', r'\n');
