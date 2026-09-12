import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:conflux/conflux.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import '../errors.dart';
import '../json/json_value.dart';
import '../native.dart';

/// One immutable HTTP request issued by a provider operation.
final class ProviderHttpRequest {
  ProviderHttpRequest({
    required this.method,
    required this.path,
    Map<String, String> headers = const {},
    this.body,
  }) : headers = Map.unmodifiable(headers);

  final String method;
  final String path;
  final Map<String, String> headers;
  final JsonObject? body;
}

enum _ClientState { open, closing, closed }

/// A one-attempt HTTP client shared by one provider's models and endpoints.
final class ProviderHttpClient {
  ProviderHttpClient({
    required this.baseUrl,
    Map<String, String> headers = const {},
    http.Client? client,
    Duration connectionTimeout = const Duration(seconds: 30),
    this.maxResponseBytes = 64 * 1024 * 1024,
  }) : headers = Map.unmodifiable(headers),
       _ownsClient = client == null,
       _client = client ?? _ownedClient(connectionTimeout) {
    if (!baseUrl.isAbsolute || (baseUrl.scheme != 'http' && baseUrl.scheme != 'https')) {
      throw ArgumentError.value(baseUrl, 'baseUrl', 'must be an absolute HTTP(S) URL');
    }
    if (connectionTimeout <= Duration.zero) {
      throw ArgumentError.value(connectionTimeout, 'connectionTimeout', 'must be positive');
    }
    if (maxResponseBytes <= 0) {
      throw ArgumentError.value(maxResponseBytes, 'maxResponseBytes', 'must be positive');
    }
  }

  final Uri baseUrl;
  final Map<String, String> headers;
  final int maxResponseBytes;
  final http.Client _client;
  final bool _ownsClient;
  final Set<_RequestLifetime> _active = {};
  _ClientState _state = _ClientState.open;
  Future<void>? _closeFuture;

  /// Sends and decodes one JSON-object response without retry or redirect.
  Effect<NativeResponse<JsonObject>, AiError> sendJson(
    ProviderHttpRequest request, {
    required String providerId,
    required String api,
    required String modelId,
  }) {
    return Effect.defer(() {
      if (_state != _ClientState.open) return Effect.fail(const ClientClosedError());
      final lifetime = _RequestLifetime();
      _active.add(lifetime);
      return _sendJson(
        lifetime,
        request,
        providerId: providerId,
        api: api,
        modelId: modelId,
      ).ensuring(
        Effect.build<void, Never>((_) async {
          try {
            await lifetime.cleanup();
          } finally {
            _active.remove(lifetime);
            lifetime.complete();
          }
        }),
      );
    });
  }

  Effect<NativeResponse<JsonObject>, AiError> _sendJson(
    _RequestLifetime lifetime,
    ProviderHttpRequest request, {
    required String providerId,
    required String api,
    required String modelId,
  }) {
    var deliveryState = RequestDeliveryState.notSent;
    return Effect.build(($) async {
      final url = baseUrl.resolve(request.path);
      final nativeRequest =
          http.AbortableRequest(
              request.method,
              url,
              abortTrigger: lifetime.abortTrigger,
            )
            ..followRedirects = false
            ..headers.addAll(headers)
            ..headers.addAll(request.headers);
      if (request.body case final body?) {
        nativeRequest
          ..headers.putIfAbsent('content-type', () => 'application/json')
          ..body = body.encode();
      }

      deliveryState = RequestDeliveryState.mayHaveReachedProvider;
      final acquisition = _client.send(nativeRequest);
      lifetime.trackAcquisition(acquisition);
      final acquired = await $(
        Effect.tryFuture<_WaitResult<http.StreamedResponse>, AiError>(
          () => lifetime.waitFor(acquisition),
          onError: (error, _) => TransportError(
            _safeForeignMessage(error),
            deliveryState: deliveryState,
          ),
          onCancel: () => lifetime.cancelAndCleanup('caller interrupted'),
        ),
      );
      if (acquired case _WaitClosed<http.StreamedResponse>(:final reason)) {
        return await $(Effect.failCause(Interrupted(reason)));
      }
      final response = (acquired as _WaitValue<http.StreamedResponse>).value;
      lifetime.trackResponse(response);
      deliveryState = RequestDeliveryState.responseStarted;

      final read = _readBody(response, lifetime, maxResponseBytes);
      final body = await $(
        Effect.tryFuture<_WaitResult<List<int>>, AiError>(
          () => lifetime.waitFor(read),
          onError: (error, _) => switch (error) {
            _ResponseTooLarge(:final actual) => ResponseLimitError(
              'The response exceeded the configured byte limit.',
              limit: maxResponseBytes,
              actual: actual,
            ),
            _ => TransportError(
              _safeForeignMessage(error),
              deliveryState: deliveryState,
            ),
          },
          onCancel: () => lifetime.cancelAndCleanup('caller interrupted'),
        ),
      );
      if (body case _WaitClosed<List<int>>(:final reason)) {
        return await $(Effect.failCause(Interrupted(reason)));
      }
      final bytes = (body as _WaitValue<List<int>>).value;

      final JsonObject payload;
      try {
        payload = JsonObject.parse(utf8.decode(bytes));
      } on Object {
        return await $(Effect.fail(const ProtocolError('The response was not a JSON object.')));
      }
      final requestId = response.headers['x-request-id'] ?? response.headers['request-id'];
      final metadata = ResponseMetadata(
        statusCode: response.statusCode,
        requestId: requestId,
        headers: response.headers,
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return await $(Effect.fail(_providerError(response, payload, requestId)));
      }
      return NativeResponse(
        value: payload,
        payload: NativePayload(
          providerId: providerId,
          api: api,
          modelId: modelId,
          json: payload,
        ),
        metadata: metadata,
      );
    });
  }

  /// Interrupts this provider's operations and releases only owned resources.
  Future<void> close() => _closeFuture ??= _beginClose();

  Future<void> _beginClose() async {
    if (_state != _ClientState.open) return;
    _state = _ClientState.closing;
    final active = _active.toList(growable: false);
    for (final lifetime in active) {
      lifetime.cancel('provider client closed');
    }
    await Future.wait(active.map((lifetime) => lifetime.done));
    if (_ownsClient) _client.close();
    _state = _ClientState.closed;
  }
}

sealed class _WaitResult<T extends Object> {
  const _WaitResult();
}

final class _WaitValue<T extends Object> extends _WaitResult<T> {
  const _WaitValue(this.value);

  final T value;
}

final class _WaitClosed<T extends Object> extends _WaitResult<T> {
  const _WaitClosed(this.reason);

  final Object? reason;
}

final class _RequestLifetime {
  final Completer<void> _abort = Completer<void>();
  final Completer<Object?> _cancelled = Completer<Object?>();
  final Completer<void> _done = Completer<void>();
  Future<http.StreamedResponse>? _acquisition;
  http.StreamedResponse? _response;
  StreamSubscription<List<int>>? _bodySubscription;
  Future<void>? _cleanupFuture;

  Future<void> get abortTrigger => _abort.future;
  Future<void> get done => _done.future;

  Future<_WaitResult<T>> waitFor<T extends Object>(Future<T> future) {
    return Future.any([
      future.then<_WaitResult<T>>(_WaitValue.new),
      _cancelled.future.then<_WaitResult<T>>(_WaitClosed.new),
    ]);
  }

  void trackAcquisition(Future<http.StreamedResponse> acquisition) {
    _acquisition = acquisition;
  }

  void trackResponse(http.StreamedResponse response) {
    _response = response;
  }

  void trackBody(StreamSubscription<List<int>> subscription) {
    _bodySubscription = subscription;
  }

  void cancel(Object? reason) {
    if (!_cancelled.isCompleted) _cancelled.complete(reason);
    if (!_abort.isCompleted) _abort.complete();
  }

  Future<void> cancelAndCleanup(Object? reason) {
    cancel(reason);
    return cleanup();
  }

  Future<void> cleanup() => _cleanupFuture ??= _cleanUp();

  Future<void> _cleanUp() async {
    if (_cancelled.isCompleted && _response == null) {
      try {
        _response = await _acquisition;
      } on Object {
        // Awaiting observes a late foreign failure after cancellation.
      }
    }
    final subscription = _bodySubscription;
    if (subscription != null) {
      await subscription.cancel();
    } else if (_cancelled.isCompleted) {
      final response = _response;
      if (response != null) await response.stream.listen(null).cancel();
    }
  }

  void complete() {
    if (!_done.isCompleted) _done.complete();
  }
}

Future<List<int>> _readBody(
  http.StreamedResponse response,
  _RequestLifetime lifetime,
  int limit,
) {
  final completion = Completer<List<int>>();
  final bytes = <int>[];
  late final StreamSubscription<List<int>> subscription;
  subscription = response.stream.listen(
    (chunk) {
      bytes.addAll(chunk);
      if (bytes.length > limit && !completion.isCompleted) {
        completion.completeError(_ResponseTooLarge(bytes.length), StackTrace.current);
        unawaited(subscription.cancel());
      }
    },
    onError: (Object error, StackTrace stackTrace) {
      if (!completion.isCompleted) completion.completeError(error, stackTrace);
    },
    onDone: () {
      if (!completion.isCompleted) completion.complete(List.unmodifiable(bytes));
    },
    cancelOnError: false,
  );
  lifetime.trackBody(subscription);
  return completion.future;
}

final class _ResponseTooLarge implements Exception {
  const _ResponseTooLarge(this.actual);

  final int actual;
}

IOClient _ownedClient(Duration connectionTimeout) {
  final ioClient = HttpClient()..connectionTimeout = connectionTimeout;
  return IOClient(ioClient);
}

ProviderError _providerError(
  http.StreamedResponse response,
  JsonObject payload,
  String? requestId,
) {
  final dart = payload.toDart();
  final error = dart['error'];
  final errorObject = error is Map<String, Object?> ? error : dart;
  final nativeMessage = errorObject['message'];
  final nativeCode = errorObject['code'];
  final rawRetryAfter = response.headers['retry-after'];
  return ProviderError(
    nativeMessage is String ? nativeMessage : 'The provider rejected the request.',
    statusCode: response.statusCode,
    code: nativeCode is String ? nativeCode : null,
    details: payload,
    requestId: requestId,
    retryAfter: _parseRetryAfter(rawRetryAfter),
    rawRetryAfter: rawRetryAfter,
  );
}

Duration? _parseRetryAfter(String? value) {
  if (value == null) return null;
  final seconds = int.tryParse(value);
  if (seconds != null && seconds >= 0) return Duration(seconds: seconds);
  try {
    final difference = HttpDate.parse(value).difference(DateTime.now().toUtc());
    return difference.isNegative ? Duration.zero : difference;
  } on FormatException {
    return null;
  }
}

String _safeForeignMessage(Object error) => switch (error) {
  SocketException(:final message) => message,
  http.ClientException(:final message) => message,
  _ => 'The HTTP operation failed.',
};
