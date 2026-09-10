import 'dart:async';
import 'dart:io';

import 'package:clickhouse/src/clickhouse_deadline.dart';
import 'package:clickhouse/src/clickhouse_exception.dart';

/// Owns the HTTP connection pool and transport details for a ClickHouse client.
final class ClickHouseHttpTransport {
  /// Creates a transport with fixed credentials and a response limit.
  factory ClickHouseHttpTransport({
    required String username,
    required String password,
    required int maxResponseBytes,
  }) => ClickHouseHttpTransport._(
    username,
    password,
    maxResponseBytes,
    HttpClient()..autoUncompress = true,
  );

  ClickHouseHttpTransport._(
    this._username,
    this._password,
    this._maxResponseBytes,
    this._httpClient,
  );

  final String _username;
  final String _password;
  final int _maxResponseBytes;
  final HttpClient _httpClient;

  /// Sends one request and returns its completely buffered response.
  Future<({int statusCode, List<int> body, String? queryId, int? clickHouseCode})> send(
    Uri uri,
    List<int> body,
    ClickHouseDeadline deadline,
  ) async {
    HttpClientRequest? request;
    var requestState = ClickHouseRequestState.notSent;
    String? queryId;
    try {
      final openRequest = _httpClient.postUrl(uri);
      final openedRequest = await deadline.wait(
        openRequest,
        requestState,
        onLateValue: (lateRequest) => lateRequest.abort(),
      );
      request = openedRequest;
      openedRequest.headers
        ..set('x-clickhouse-user', _username)
        ..set('x-clickhouse-key', _password)
        ..set('x-clickhouse-format', 'JSON')
        ..contentType = ContentType.text;
      deadline.check(requestState);
      requestState = ClickHouseRequestState.mayHaveReachedServer;
      openedRequest
        ..contentLength = body.length
        ..add(body);

      final response = await deadline.wait(
        openedRequest.close(),
        requestState,
        onTimeout: openedRequest.abort,
      );
      queryId = response.headers.value('x-clickhouse-query-id');
      final responseBody = await _consumeResponse(
        response,
        openedRequest,
        deadline,
        queryId,
      );
      return (
        statusCode: response.statusCode,
        body: responseBody,
        queryId: queryId,
        clickHouseCode: int.tryParse(
          response.headers.value('x-clickhouse-exception-code') ?? '',
        ),
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

  /// Releases every connection owned by this transport.
  void close() => _httpClient.close();

  Future<List<int>> _consumeResponse(
    HttpClientResponse response,
    HttpClientRequest request,
    ClickHouseDeadline deadline,
    String? queryId,
  ) {
    final remaining = deadline.remaining(
      ClickHouseRequestState.mayHaveReachedServer,
      queryId: queryId,
    );
    final completer = Completer<List<int>>();
    final responseBody = <int>[];
    late final StreamSubscription<List<int>> subscription;
    late final Timer timer;

    void fail(Object error, [StackTrace? stackTrace]) {
      if (completer.isCompleted) {
        return;
      }
      timer.cancel();
      unawaited(subscription.cancel());
      request.abort(error);
      completer.completeError(error, stackTrace);
    }

    subscription = response.listen(
      (chunk) {
        responseBody.addAll(chunk);
        if (responseBody.length > _maxResponseBytes) {
          fail(
            ClickHouseSizeLimitException(
              message: 'ClickHouse response exceeded the $_maxResponseBytes byte limit.',
              requestState: ClickHouseRequestState.mayHaveReachedServer,
              queryId: queryId,
              direction: ClickHouseSizeLimitDirection.response,
              limit: _maxResponseBytes,
            ),
          );
        }
      },
      onError: fail,
      onDone: () {
        if (completer.isCompleted) {
          return;
        }
        timer.cancel();
        try {
          deadline.check(
            ClickHouseRequestState.mayHaveReachedServer,
            queryId: queryId,
          );
          completer.complete(responseBody);
        } on Object catch (error, stackTrace) {
          fail(error, stackTrace);
        }
      },
      cancelOnError: true,
    );
    timer = Timer(
      remaining,
      () => fail(
        deadline.timeoutException(
          ClickHouseRequestState.mayHaveReachedServer,
          queryId: queryId,
        ),
      ),
    );
    return completer.future;
  }
}
