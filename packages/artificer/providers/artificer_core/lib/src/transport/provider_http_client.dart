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
  bool _closed = false;

  Effect<NativeResponse<JsonObject>, AiError> sendJson(
    ProviderHttpRequest request, {
    required String providerId,
    required String api,
    required String modelId,
  }) {
    return Effect.defer(() {
      if (_closed) return Effect.fail(const ClientClosedError());

      final abort = Completer<void>();
      var deliveryState = RequestDeliveryState.notSent;
      return Effect.build<NativeResponse<JsonObject>, AiError>(($) async {
        final url = baseUrl.resolve(request.path);
        final nativeRequest =
            http.AbortableRequest(
                request.method,
                url,
                abortTrigger: abort.future,
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
        final response = await $(
          Effect.tryFuture<http.StreamedResponse, AiError>(
            () => _client.send(nativeRequest),
            onError: (error, _) => TransportError(
              _safeForeignMessage(error),
              deliveryState: deliveryState,
            ),
            onCancel: () {
              if (!abort.isCompleted) abort.complete();
            },
          ),
        );
        deliveryState = RequestDeliveryState.responseStarted;
        final bytes = await $(
          Effect.tryFuture<List<int>, AiError>(
            () => response.stream.toBytes(),
            onError: (error, _) => TransportError(
              _safeForeignMessage(error),
              deliveryState: deliveryState,
            ),
            onCancel: () {
              if (!abort.isCompleted) abort.complete();
            },
          ),
        );
        if (bytes.length > maxResponseBytes) {
          return await $(
            Effect.fail(
              ResponseLimitError(
                'The response exceeded the configured byte limit.',
                limit: maxResponseBytes,
                actual: bytes.length,
              ),
            ),
          );
        }

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
    });
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    if (_ownsClient) _client.close();
  }
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
