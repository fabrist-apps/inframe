import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:artificer_core/src/errors.dart';
import 'package:artificer_core/src/json/json_value.dart';
import 'package:artificer_core/src/native.dart';
import 'package:artificer_core/src/protocols/sse.dart';
import 'package:artificer_core/src/transport/upload_source.dart';
import 'package:conflux/conflux.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

part 'sse_transport.dart';

/// One immutable HTTP request issued by a provider operation.
final class ProviderHttpRequest {
  /// Creates a [ProviderHttpRequest].
  ProviderHttpRequest({
    required this.method,
    required this.path,
    Map<String, String> headers = const {},
    this.body,
  }) : headers = Map.unmodifiable(headers);

  /// The HTTP method.
  final String method;

  /// The path resolved against the provider base URI.
  final String path;

  /// The immutable response headers.
  final Map<String, String> headers;

  /// The immutable encoded request body.
  final JsonObject? body;
}

/// One native file upload request.
final class ProviderUploadRequest {
  /// Creates a [ProviderUploadRequest].
  ProviderUploadRequest({
    required this.path,
    this.method = 'POST',
    Map<String, String> headers = const {},
    this.remoteResourceId,
  }) : headers = Map.unmodifiable(headers);

  /// The path resolved against the provider base URI.
  final String path;

  /// The HTTP method.
  final String method;

  /// The immutable response headers.
  final Map<String, String> headers;

  /// The remote resource allocated before the failure, when known.
  final String? remoteResourceId;
}

enum _ClientState { open, closing, closed }

sealed class _SseSignal {
  const _SseSignal();
}

final class _SseExpected extends _SseSignal {
  const _SseExpected(this.error);

  final AiError error;
}

final class _SseTerminal extends _SseSignal {
  const _SseTerminal(this.cause);

  final Cause<_SseSignal> cause;
}

/// A one-attempt HTTP client shared by one provider's models and endpoints.
final class ProviderHttpClient {
  /// Creates a [ProviderHttpClient].
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

  /// The base url.
  final Uri baseUrl;

  /// The immutable response headers.
  final Map<String, String> headers;

  /// The maximum byte size accumulated for one response.
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
    return _execute(
      (lifetime) => _sendJson(
        lifetime,
        request,
        providerId: providerId,
        api: api,
        modelId: modelId,
      ),
    );
  }

  /// Uploads one repeatable source without retry, polling, or remote deletion.
  Effect<NativeResponse<JsonObject>, AiError> sendUpload(
    ProviderUploadRequest request,
    UploadSource source, {
    required String providerId,
    required String api,
    String modelId = 'files',
  }) {
    return _execute(
      (lifetime) => _sendUpload(
        lifetime,
        request,
        source,
        providerId: providerId,
        api: api,
        modelId: modelId,
      ),
    );
  }

  /// Sends one cold SSE request through a fresh protocol decoder per consumption.
  Flow<A, AiError> sendSse<A>(
    ProviderHttpRequest request, {
    required SseProtocol<A> Function() createProtocol,
    int decodedEventCapacity = 16,
    int maxEventBytes = 8 * 1024 * 1024,
    int? maxStreamBytes,
  }) {
    if (decodedEventCapacity <= 0) {
      throw ArgumentError.value(
        decodedEventCapacity,
        'decodedEventCapacity',
        'must be positive',
      );
    }
    if (maxEventBytes <= 0) {
      throw ArgumentError.value(maxEventBytes, 'maxEventBytes', 'must be positive');
    }
    final responseLimit = maxStreamBytes ?? maxResponseBytes;
    if (responseLimit <= 0) {
      throw ArgumentError.value(responseLimit, 'maxStreamBytes', 'must be positive');
    }
    return Flow.fromStream<A, _SseSignal>(
          () => _openSseStream(
            request,
            protocol: createProtocol(),
            maxEventBytes: maxEventBytes,
            maxStreamBytes: responseLimit,
          ),
          onError: (error, stackTrace) => switch (error) {
            _SseSignal() => error,
            AiError() => _SseExpected(error),
            _ => _SseTerminal(Defect(error, stackTrace)),
          },
          capacity: decodedEventCapacity,
        )
        .catchError(
          (signal) => switch (signal) {
            _SseExpected() => Flow.fail<A, _SseSignal>(signal),
            _SseTerminal(:final cause) => Effect.failCause<A, _SseSignal>(cause).asFlow(),
          },
        )
        .mapError(
          (signal) => switch (signal) {
            _SseExpected(:final error) => error,
            _SseTerminal() => throw StateError('An SSE terminal cause was not expanded.'),
          },
        );
  }

  Stream<A> _openSseStream<A>(
    ProviderHttpRequest request, {
    required SseProtocol<A> protocol,
    required int maxEventBytes,
    required int maxStreamBytes,
  }) {
    if (_state != _ClientState.open) {
      return Stream<A>.error(const ClientClosedError());
    }
    final lifetime = _RequestLifetime();
    _active.add(lifetime);
    return _SsePump<A>(
      client: _client,
      url: baseUrl.resolve(request.path),
      request: request,
      headers: headers,
      lifetime: lifetime,
      protocol: protocol,
      maxEventBytes: maxEventBytes,
      maxStreamBytes: maxStreamBytes,
      release: () {
        _active.remove(lifetime);
        lifetime.complete();
      },
    ).stream;
  }

  Effect<A, AiError> _execute<A>(
    Effect<A, AiError> Function(_RequestLifetime lifetime) operation,
  ) {
    return Effect.defer(() {
      if (_state != _ClientState.open) return Effect.fail(const ClientClosedError());
      final lifetime = _RequestLifetime();
      _active.add(lifetime);
      return operation(lifetime).ensuring(
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
      lifetime._acquisition = acquisition;
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
        return $(Effect.failCause(Interrupted(reason)));
      }
      final response = (acquired as _WaitValue<http.StreamedResponse>).value;
      lifetime._response = response;
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
        return $(Effect.failCause(Interrupted(reason)));
      }
      final bytes = (body as _WaitValue<List<int>>).value;

      final JsonObject payload;
      try {
        payload = JsonObject.parse(utf8.decode(bytes));
      } on Object {
        return $(Effect.fail(const ProtocolError('The response was not a JSON object.')));
      }
      final requestId = response.headers['x-request-id'] ?? response.headers['request-id'];
      final metadata = ResponseMetadata(
        statusCode: response.statusCode,
        requestId: requestId,
        headers: response.headers,
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return $(Effect.fail(_providerError(response, payload, requestId)));
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

  Effect<NativeResponse<JsonObject>, AiError> _sendUpload(
    _RequestLifetime lifetime,
    ProviderUploadRequest request,
    UploadSource source, {
    required String providerId,
    required String api,
    required String modelId,
  }) {
    var deliveryState = RequestDeliveryState.notSent;
    return Effect.build(($) async {
      final sourceStream = await $(
        Effect.tryFuture<Stream<List<int>>, AiError>(
          () => Future.sync(source.openRead),
          onError: (error, _) => switch (error) {
            UploadSourceError(:final message) => InvalidRequestError(
              message,
              remoteResourceId: request.remoteResourceId,
            ),
            _ => TransportError(
              _safeForeignMessage(error),
              deliveryState: RequestDeliveryState.notSent,
              remoteResourceId: request.remoteResourceId,
            ),
          },
          onCancel: () => lifetime.cancelAndCleanup('caller interrupted'),
        ),
      );
      final nativeRequest =
          _AbortableBodyRequest(
              request.method,
              baseUrl.resolve(request.path),
              _trackedUpload(sourceStream, lifetime),
              abortTrigger: lifetime.abortTrigger,
            )
            ..followRedirects = false
            ..contentLength = source.length
            ..headers.addAll(headers)
            ..headers.addAll(request.headers)
            ..headers.putIfAbsent('content-type', () => source.mimeType)
            ..headers.putIfAbsent(
              'content-disposition',
              () => "attachment; filename*=UTF-8''${Uri.encodeComponent(source.filename)}",
            );

      deliveryState = RequestDeliveryState.mayHaveReachedProvider;
      final acquisition = _client.send(nativeRequest);
      lifetime._acquisition = acquisition;
      final acquired = await $(
        Effect.tryFuture<_WaitResult<http.StreamedResponse>, AiError>(
          () => lifetime.waitFor(acquisition),
          onError: (error, _) => switch (error) {
            UploadSourceError(:final message) => InvalidRequestError(
              message,
              remoteResourceId: request.remoteResourceId,
            ),
            _ => TransportError(
              _safeForeignMessage(error),
              deliveryState: deliveryState,
              remoteResourceId: request.remoteResourceId,
            ),
          },
          onCancel: () => lifetime.cancelAndCleanup('caller interrupted'),
        ),
      );
      if (acquired case _WaitClosed<http.StreamedResponse>(:final reason)) {
        return $(Effect.failCause(Interrupted(reason)));
      }
      final response = (acquired as _WaitValue<http.StreamedResponse>).value;
      lifetime._response = response;
      deliveryState = RequestDeliveryState.responseStarted;
      final body = await $(
        Effect.tryFuture<_WaitResult<List<int>>, AiError>(
          () => lifetime.waitFor(_readBody(response, lifetime, maxResponseBytes)),
          onError: (error, _) => switch (error) {
            _ResponseTooLarge(:final actual) => ResponseLimitError(
              'The response exceeded the configured byte limit.',
              limit: maxResponseBytes,
              actual: actual,
              remoteResourceId: request.remoteResourceId,
            ),
            _ => TransportError(
              _safeForeignMessage(error),
              deliveryState: deliveryState,
              remoteResourceId: request.remoteResourceId,
            ),
          },
          onCancel: () => lifetime.cancelAndCleanup('caller interrupted'),
        ),
      );
      if (body case _WaitClosed<List<int>>(:final reason)) {
        return $(Effect.failCause(Interrupted(reason)));
      }
      final bytes = (body as _WaitValue<List<int>>).value;
      final JsonObject payload;
      try {
        payload = JsonObject.parse(utf8.decode(bytes));
      } on Object {
        return $(
          Effect.fail(
            ProtocolError(
              'The response was not a JSON object.',
              remoteResourceId: request.remoteResourceId,
            ),
          ),
        );
      }
      final requestId = response.headers['x-request-id'] ?? response.headers['request-id'];
      final metadata = ResponseMetadata(
        statusCode: response.statusCode,
        requestId: requestId,
        headers: response.headers,
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return $(
          Effect.fail(
            _providerError(
              response,
              payload,
              requestId,
              remoteResourceId: request.remoteResourceId,
            ),
          ),
        );
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
  Future<void> Function()? _uploadCleanup;
  Future<void>? _cleanupFuture;

  Future<void> get abortTrigger => _abort.future;
  Future<Object?> get cancellation => _cancelled.future;
  Future<void> get done => _done.future;

  Future<_WaitResult<T>> waitFor<T extends Object>(Future<T> future) {
    return Future.any([
      future.then<_WaitResult<T>>(_WaitValue.new),
      _cancelled.future.then<_WaitResult<T>>(_WaitClosed.new),
    ]);
  }

  void trackUpload(Future<void> Function() cleanup) {
    _uploadCleanup = cleanup;
    if (_cancelled.isCompleted) unawaited(cleanup());
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
    await _uploadCleanup?.call();
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
    } else {
      final response = _response;
      if (response != null) await response.stream.listen(null).cancel();
    }
  }

  void complete() {
    if (!_done.isCompleted) _done.complete();
  }
}

final class _AbortableBodyRequest extends http.BaseRequest with http.Abortable {
  _AbortableBodyRequest(
    super.method,
    super.url,
    this.body, {
    this.abortTrigger,
  });

  final Stream<List<int>> body;

  @override
  final Future<void>? abortTrigger;

  @override
  http.ByteStream finalize() {
    super.finalize();
    return http.ByteStream(body);
  }
}

Stream<List<int>> _trackedUpload(Stream<List<int>> source, _RequestLifetime lifetime) {
  late final StreamController<List<int>> controller;
  StreamSubscription<List<int>>? subscription;
  Future<void>? cleanupFuture;

  Future<void> cleanup() => cleanupFuture ??= () async {
    await subscription?.cancel();
    if (!controller.isClosed) unawaited(controller.close());
  }();

  controller = StreamController<List<int>>(
    sync: true,
    onListen: () {
      subscription = source.listen(
        controller.add,
        onError: controller.addError,
        onDone: controller.close,
      );
      lifetime.trackUpload(cleanup);
    },
    onPause: () => subscription?.pause(),
    onResume: () => subscription?.resume(),
    onCancel: cleanup,
  );
  return controller.stream;
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
  lifetime._bodySubscription = subscription;
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
  String? requestId, {
  String? remoteResourceId,
}) {
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
    remoteResourceId: remoteResourceId,
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
