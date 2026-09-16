import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:artificer_core/src/errors.dart';
import 'package:artificer_core/src/json/json_value.dart';
import 'package:artificer_core/src/native.dart';
import 'package:artificer_core/src/transport/provider_dio_adapter.dart';
import 'package:conflux/effect.dart';
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
  }) => Effect.defer((_) {
    if (_closing != null) return Effect.fail(const ClientClosedError());
    if (!url.hasScheme || !url.hasAuthority || !['http', 'https'].contains(url.scheme)) {
      return Effect.fail(const InvalidRequestError('An absolute HTTP endpoint is required.'));
    }
    try {
      JsonValues.validate(body);
    } on FormatException {
      return Effect.fail(const InvalidRequestError('Request body must contain JSON values.'));
    }
    return Effect.using(
      Effect.build<ProviderJsonResponse, AiError>(($) async {
        final handle = await $.acquireRelease(
          Effect.defer<RequestLifetime, AiError>((_) {
            if (_closing != null) return Effect.fail(const ClientClosedError());
            final handle = RequestLifetime();
            _active.add(handle);
            return Effect.succeed(handle);
          }),
          release: (handle, _) => Effect.tryFuture<void, Never>((_) async {
            try {
              await handle.dispose();
            } finally {
              _active.remove(handle);
            }
          }, onError: (error, stack, _) => Error.throwWithStackTrace(error, stack)),
        );
        return $(
          Effect.tryFuture<ProviderJsonResponse, AiError>(
            (_) => _request(handle, url, method, headers, body),
            onCancel: (_) => handle.dispose(interrupt: true),
            onError: (error, stack, _) => _mapError(error, stack),
          ).catchError(
            (error, _) => handle.interrupted
                ? Effect.failCause(const Interrupted('Provider closed'))
                : Effect.fail(error),
          ),
        );
      }),
    );
  });

  Future<ProviderJsonResponse> _request(
    RequestLifetime handle,
    Uri url,
    String method,
    Map<String, Object?> headers,
    Object? body,
  ) async {
    final response = await _dio.fetch<ResponseBody>(
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
    );
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
    final metadata = ResponseMetadata(
      statusCode: response.statusCode!,
      headers: response.headers.map,
      requestId: response.headers.value('x-request-id') ?? response.headers.value('request-id'),
    );
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

  AiError _mapError(Object error, StackTrace stack) {
    if (error is AiError) return error;
    if (error is DioException) {
      if (error.type == DioExceptionType.unknown &&
          error.error is! SocketException &&
          error.error is! HttpException &&
          error.error is! HandshakeException) {
        Error.throwWithStackTrace(error.error ?? error, stack);
      }
      return const TransportError('HTTP transport failed.');
    }
    if (error is SocketException || error is HttpException || error is HandshakeException) {
      return const TransportError('HTTP transport failed.');
    }
    Error.throwWithStackTrace(error, stack);
  }

  /// Interrupts this provider's active requests and awaits owned cleanup.
  /// A borrowed Dio remains usable by its other callers.
  Future<void> close() => _closing ??= _close();
  Future<void> _close() async {
    try {
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
