part of 'clickhouse_client.dart';

extension on ClickHouseClient {
  Future<_HttpResponse> _send(Uri uri, List<int> body, _Deadline deadline) async {
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
      return _HttpResponse(
        statusCode: response.statusCode,
        body: responseBody,
        queryId: queryId,
        clickHouseCode: int.tryParse(response.headers.value('x-clickhouse-exception-code') ?? ''),
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

  Future<List<int>> _consumeResponse(
    HttpClientResponse response,
    HttpClientRequest request,
    _Deadline deadline,
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
        deadline.exception(
          ClickHouseRequestState.mayHaveReachedServer,
          queryId: queryId,
        ),
      ),
    );
    return completer.future;
  }
}
