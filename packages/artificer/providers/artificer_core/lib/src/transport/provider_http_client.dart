import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:artificer_core/src/errors.dart';
import 'package:artificer_core/src/json/json_value.dart';
import 'package:artificer_core/src/native.dart';
import 'package:artificer_core/src/protocols/sse.dart';
import 'package:artificer_core/src/transport/provider_dio_adapter.dart';
import 'package:conflux/effect.dart';
import 'package:conflux/flow.dart';
import 'package:dio/dio.dart';

/// A decoded native JSON value together with its HTTP metadata.
class ProviderJsonResponse {
  /// Creates a native response envelope without copying its values.
  const ProviderJsonResponse({required this.data, required this.metadata});

  /// Complete decoded JSON, including unknown fields.
  final Object? data;

  /// HTTP status, headers, and request identity.
  final ResponseMetadata metadata;
  @override
  String toString() => 'ProviderJsonResponse(status: ${metadata.statusCode})';
}

/// Owns one provider's requests and optionally its Dio connection pool.
/// Operations are cold and allocate one independent request lifetime per run.
class ProviderHttpClient {
  /// Borrows a compatible supplied Dio, or creates an owned Dio.
  ProviderHttpClient({
    Dio? dio,
    this.connectTimeout = const Duration(seconds: 30),
    this.maxResponseBytes = 64 * 1024 * 1024,
  }) : _ownsDio = dio == null,
       _dio = dio ?? (Dio()..httpClientAdapter = ProviderDioAdapter()) {
    if (_dio.httpClientAdapter is! ProviderDioAdapter) {
      throw ArgumentError('Borrowed Dio must use ProviderDioAdapter.');
    }
    if (connectTimeout.isNegative) throw ArgumentError.value(connectTimeout, 'connectTimeout');
    if (maxResponseBytes <= 0) throw ArgumentError.value(maxResponseBytes, 'maxResponseBytes');
  }
  final Dio _dio;
  final bool _ownsDio;

  /// Native connection establishment limit; zero disables the SDK limit.
  final Duration connectTimeout;

  /// Maximum decoded response body bytes retained by JSON operations.
  final int maxResponseBytes;
  final Set<RequestLifetime> _active = {};
  Future<void>? _closing;

  /// Sends one absolute HTTP request and reads at most [maxResponseBytes].
  /// Native error JSON is retained on [ProviderError.details].
  Effect<ProviderJsonResponse, AiError> requestJson({
    required Uri url,
    String method = 'POST',
    Map<String, Object?> headers = const {},
    Object? body,
  }) => Effect.using(
    _openRequest(
      url,
      method,
      headers,
      body,
    ).flatMap((opened, _) => _io(opened.handle, () => _decodeJson(opened.response))),
  );

  /// Consumes one bounded SSE response within this provider's request scope.
  ///
  /// [consume] may classify native events using their HTTP [ResponseMetadata].
  /// Append final-result emission after this entire Flow: it completes transport
  /// cleanup before normal completion, early take, cancellation, or failure.
  /// Each consumption allocates a fresh request, parser, and bounded event queue.
  Flow<T, AiError> withSse<T>({
    required Uri url,
    required Flow<T, AiError> Function(ResponseMetadata metadata, Flow<SseEvent, AiError> events)
    consume,
    String method = 'POST',
    Map<String, Object?> headers = const {},
    Object? body,
    int eventCapacity = 16,
    int maxEventBytes = 8 * 1024 * 1024,
  }) {
    if (eventCapacity <= 0) throw ArgumentError.value(eventCapacity, 'eventCapacity');
    final parser = SseParser(maxEventBytes: maxEventBytes);
    return _openRequest(url, method, headers, body).asFlow().concatMap((opened, _) {
      final response = opened.response;
      if (response.statusCode! < 200 || response.statusCode! >= 300) {
        return _io(opened.handle, () => _decodeJson(response)).asFlow().concatMap<T>(
          (_, _) => Flow.fail(const ProtocolError('Expected an SSE response.')),
        );
      }
      final responseBody = response.data;
      if (responseBody == null) return Flow.fail(const ProtocolError('Missing response body.'));
      final events =
          Flow.fromStream<SseEvent, AiError>(
            (_) => parser.decode(responseBody.stream),
            capacity: eventCapacity,
            onError: (error, stack, _) => _mapError(error, stack, opened.handle),
          ).catchError(
            (error, _) => opened.handle.interrupted
                ? Effect.failCause<SseEvent, AiError>(const Interrupted('Provider closed')).asFlow()
                : Flow.fail(error),
          );
      // Abort reads before closing the async generator's subscription. This
      // unblocks a parser waiting for the next chunk when the consumer stops.
      return consume(_metadata(response), events).ensuring(_dispose(opened.handle));
    });
  }

  Effect<_OpenedResponse, AiError> _openRequest(
    Uri url,
    String method,
    Map<String, Object?> headers,
    Object? body,
  ) => Effect.defer((_) {
    if (_closing != null) return Effect.fail(const ClientClosedError());
    if (!url.hasScheme || !url.hasAuthority || !['http', 'https'].contains(url.scheme)) {
      return Effect.fail(const InvalidRequestError('An absolute HTTP endpoint is required.'));
    }
    try {
      JsonValues.validate(body);
    } on FormatException {
      return Effect.fail(const InvalidRequestError('Request body must contain JSON values.'));
    }
    return Effect.build<_OpenedResponse, AiError>(($) async {
      final handle = await $.acquireRelease(
        Effect.defer<RequestLifetime, AiError>((_) {
          if (_closing != null) return Effect.fail(const ClientClosedError());
          final handle = RequestLifetime();
          _active.add(handle);
          return Effect.succeed(handle);
        }),
        release: (handle, _) => _release(handle),
      );
      final response = await $(
        _io(
          handle,
          () => _dio.fetch<ResponseBody>(
            RequestOptions(
              path: url.toString(),
              method: method,
              headers: headers,
              data: body == null ? null : jsonEncode(body),
              contentType: Headers.jsonContentType,
              responseType: ResponseType.stream,
              connectTimeout: connectTimeout,
              sendTimeout: Duration.zero,
              receiveTimeout: Duration.zero,
              followRedirects: false,
              maxRedirects: 0,
              validateStatus: (_) => true,
              cancelToken: handle.token,
              extra: {ProviderDioAdapter.lifetimeKey: handle},
            ),
          ),
        ),
      );
      return _OpenedResponse(handle, response);
    });
  });

  Effect<T, AiError> _io<T>(RequestLifetime handle, Future<T> Function() operation) =>
      Effect.tryFuture<T, AiError>(
        (_) => operation(),
        onCancel: (_) => handle.dispose(interrupt: true),
        onError: (error, stack, _) => _mapError(error, stack, handle),
      ).catchError(
        (error, _) => handle.interrupted
            ? Effect.failCause(const Interrupted('Provider closed'))
            : Effect.fail(error),
      );

  Effect<void, Never> _dispose(RequestLifetime handle) => Effect.tryFuture(
    (_) => handle.dispose(),
    onError: (error, stack, _) => Error.throwWithStackTrace(error, stack),
  );

  Effect<void, Never> _release(RequestLifetime handle) => Effect.tryFuture((_) async {
    try {
      await handle.dispose();
    } finally {
      _active.remove(handle);
    }
  }, onError: (error, stack, _) => Error.throwWithStackTrace(error, stack));

  ResponseMetadata _metadata(Response<ResponseBody> response) => ResponseMetadata(
    statusCode: response.statusCode!,
    headers: response.headers.map,
    requestId: response.headers.value('x-request-id') ?? response.headers.value('request-id'),
  );

  Future<ProviderJsonResponse> _decodeJson(Response<ResponseBody> response) async {
    final bytes = BytesBuilder(copy: false);
    final responseBody = response.data;
    if (responseBody == null) throw const ProtocolError('Missing response body.');
    await for (final chunk in responseBody.stream) {
      if (bytes.length + chunk.length > maxResponseBytes) {
        throw ResponseLimitError('Response exceeds byte limit.', limit: maxResponseBytes);
      }
      bytes.add(chunk);
    }
    Object? data;
    try {
      data = jsonDecode(utf8.decode(bytes.takeBytes()));
      JsonValues.validate(data);
    } on FormatException {
      throw const ProtocolError('Response is not valid UTF-8 JSON.');
    }
    final metadata = _metadata(response);
    if (metadata.statusCode < 200 || metadata.statusCode >= 300) {
      throw ProviderError(
        'Provider returned an unsuccessful HTTP status.',
        statusCode: metadata.statusCode,
        details: data,
        requestId: metadata.requestId,
        retryAfter: response.headers.value('retry-after'),
      );
    }
    return ProviderJsonResponse(data: data, metadata: metadata);
  }

  AiError _mapError(Object error, StackTrace stack, RequestLifetime handle) {
    if (error is AiError) return error;
    if (error is DioException) {
      if (error.type == DioExceptionType.unknown &&
          error.error is! SocketException &&
          error.error is! HttpException &&
          error.error is! HandshakeException) {
        Error.throwWithStackTrace(error.error ?? error, stack);
      }
      return TransportError('HTTP transport failed.', deliveryState: handle.deliveryState);
    }
    if (error is SocketException || error is HttpException || error is HandshakeException) {
      return TransportError('HTTP transport failed.', deliveryState: handle.deliveryState);
    }
    Error.throwWithStackTrace(error, stack);
  }

  /// Interrupts this provider's active requests and awaits owned cleanup.
  /// A borrowed Dio remains usable by its other callers.
  Future<void> close() {
    if (_closing case final closing?) return closing;
    final completion = Completer<void>();
    _closing = completion.future;
    completion.complete(_close());
    return completion.future;
  }

  Future<void> _close() async {
    try {
      // Caller Flow callbacks are outside this client's ownership. Joining the
      // transport fence, rather than their cursor scopes, also permits callers
      // to close a provider from inside a response observer without self-waiting.
      await Future.wait(_active.toList().map((handle) => handle.dispose(interrupt: true)));
    } finally {
      if (_ownsDio) _dio.close(force: true);
    }
  }

  /// Lazy scoped counterpart to [close], preserving cleanup defects.
  Effect<void, Never> closeEffect() => Effect.tryFuture(
    (_) => close(),
    onError: (error, stack, _) => Error.throwWithStackTrace(error, stack),
  );
}

class _OpenedResponse {
  _OpenedResponse(this.handle, this.response);
  final RequestLifetime handle;
  final Response<ResponseBody> response;
}
