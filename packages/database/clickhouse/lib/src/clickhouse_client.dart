import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:clickhouse/src/clickhouse_exception.dart';
import 'package:clickhouse/src/clickhouse_query_result.dart';

part 'clickhouse_deadline.dart';
part 'clickhouse_http_transport.dart';
part 'clickhouse_protocol.dart';

/// A reusable HTTP client for bounded ClickHouse operations.
final class ClickHouseClient {
  /// Creates a client that owns one HTTP connection pool.
  ///
  /// [endpoint] must use HTTP or HTTPS, include a host, and contain no
  /// credentials, query, or fragment. Its path is preserved for reverse
  /// proxies. [timeout], [maxRequestBytes], and [maxResponseBytes] must be
  /// positive. An empty [password] is allowed.
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
  var _closing = false;
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
    final quotedTable = _quoteIdentifier(table);
    final encodedRows = _encodeRows(rows);
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
  Future<void> close() {
    final existing = _closeFuture;
    if (existing != null) {
      return existing;
    }
    _closing = true;
    final shutdown = _closeWhenIdle();
    _closeFuture = shutdown;
    return shutdown;
  }

  Future<void> _closeWhenIdle() async {
    if (_activeOperations > 0) {
      _becameIdle = Completer<void>();
      await _becameIdle!.future;
    }
    _httpClient.close();
  }

  Future<ClickHouseQueryResult> _query(Uri uri, List<int> body, _Deadline deadline) async {
    final response = await _send(uri, body, deadline);
    if (response.statusCode != HttpStatus.ok) {
      throw _serverException(
        response.statusCode,
        response.body,
        response.queryId,
        response.clickHouseCode,
      );
    }

    late final String responseText;
    try {
      responseText = utf8.decode(response.body);
      final result = _decodeQueryResult(responseText);
      deadline.check(
        ClickHouseRequestState.mayHaveReachedServer,
        queryId: response.queryId,
      );
      return result;
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
    required String operation,
    required _Deadline deadline,
  }) async {
    final response = await _send(uri, body, deadline);
    if (response.statusCode != HttpStatus.ok) {
      throw _serverException(
        response.statusCode,
        response.body,
        response.queryId,
        response.clickHouseCode,
      );
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

  Duration _operationTimeout(Duration? timeout) =>
      timeout == null ? _timeout : _requirePositiveDuration(timeout, 'timeout');

  Future<T> _runOperation<T>(
    Duration? timeout,
    String operation,
    Future<T> Function(_Deadline deadline) run,
  ) {
    late final _Deadline deadline;
    try {
      _ensureOpen();
      deadline = _Deadline(operation, _operationTimeout(timeout));
    } on Object catch (error, stackTrace) {
      return Future<T>.error(error, stackTrace);
    }
    _activeOperations += 1;
    final result = Future<T>.sync(() => run(deadline));
    return result.whenComplete(_finishOperation);
  }

  void _finishOperation() {
    _activeOperations -= 1;
    if (_activeOperations == 0) {
      _becameIdle?.complete();
      _becameIdle = null;
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

  void _ensureOpen() {
    if (_closing) {
      throw StateError('The ClickHouse client is closing or closed.');
    }
  }
}
