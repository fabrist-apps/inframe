import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:clickhouse/src/deadline.dart';
import 'package:clickhouse/src/exception.dart';
import 'package:clickhouse/src/response.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';

/// Owns the HTTP connection pool and transport details for a ClickHouse client.
final class ClickHouseHttpTransport {
  /// Creates a transport with fixed credentials and a response limit.
  ClickHouseHttpTransport({
    required String username,
    required String password,
    required this._maxResponseBytes,
  }) : _dio = DioForNative(
         BaseOptions(
           headers: {
             'x-clickhouse-user': username,
             'x-clickhouse-key': password,
             'x-clickhouse-format': 'JSON',
           },
           contentType: 'text/plain; charset=utf-8',
           responseType: ResponseType.stream,
           validateStatus: (_) => true,
         ),
       );

  final int _maxResponseBytes;
  final Dio _dio;

  /// Sends one request and returns its completely buffered response.
  Future<ClickHouseResponse> send(Uri uri, List<int> body, ClickHouseDeadline deadline) async {
    final cancellation = CancelToken();
    var requestState = ClickHouseRequestState.notSent;
    String? queryId;

    // The native adapter consumes this only after opening the connection.
    // Mark the outcome uncertain before handing it any request bytes.
    Stream<Uint8List> requestBody() async* {
      deadline.check(requestState);
      requestState = ClickHouseRequestState.mayHaveReachedServer;
      yield Uint8List.fromList(body);
    }

    try {
      deadline.check(requestState);
      final response = await deadline.wait(
        _dio.postUri<ResponseBody>(
          uri,
          data: requestBody(),
          options: Options(headers: {Headers.contentLengthHeader: body.length}),
          cancelToken: cancellation,
        ),
        requestState,
        onTimeout: cancellation.cancel,
        onLateValue: (_) => cancellation.cancel(),
      );
      final responseBody = response.data!;
      queryId = response.headers.value('x-clickhouse-query-id');
      final bytes = await _consumeResponse(responseBody, cancellation, deadline, queryId);

      return ClickHouseResponse(
        statusCode: responseBody.statusCode,
        body: bytes,
        queryId: queryId,
        clickHouseCode: int.tryParse(
          response.headers.value('x-clickhouse-exception-code') ?? '',
        ),
      );
    } on ClickHouseTimeoutException {
      cancellation.cancel();
      throw deadline.timeoutException(requestState, queryId: queryId);
    } on ClickHouseException {
      cancellation.cancel();
      rethrow;
    } on DioException catch (error) {
      cancellation.cancel();
      final cause = error.error ?? error;
      if (cause is ClickHouseException) {
        Error.throwWithStackTrace(cause, error.stackTrace);
      }
      throw ClickHouseTransportException(
        message: 'ClickHouse HTTP transport failed: $cause',
        requestState: requestState,
        queryId: queryId,
        cause: cause,
      );
    } on IOException catch (error) {
      cancellation.cancel();
      throw ClickHouseTransportException(
        message: 'ClickHouse HTTP transport failed: $error',
        requestState: requestState,
        queryId: queryId,
        cause: error,
      );
    }
  }

  /// Releases every connection owned by this transport.
  void close() => _dio.close();

  Future<List<int>> _consumeResponse(
    ResponseBody response,
    CancelToken cancellation,
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
      cancellation.cancel();
      completer.completeError(error, stackTrace);
    }

    subscription = response.stream.listen(
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
