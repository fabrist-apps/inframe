import 'dart:collection';

import 'package:artificer_core/artificer_core.dart';
import 'package:artificer_core/json.dart';
import 'package:artificer_core/protocols.dart';
import 'package:artificer_core/transport.dart';
import 'package:artificer_google/src/interactions/interaction_events.dart';
import 'package:artificer_google/src/interactions/interaction_models.dart';
import 'package:conflux/conflux.dart';

const _providerId = 'google';
const _api = 'interactions';
const _modelId = 'interactions';
const _diagnosticEventCapacity = 16;

/// Explicit lifecycle operations for the stable Google Interactions v1 API.
final class GoogleInteractionsResource {
  /// Creates interaction operations over one provider-owned client.
  const GoogleInteractionsResource(this._client);

  final ProviderHttpClient _client;

  /// Creates one interaction without polling for a terminal status.
  Effect<NativeResponse<GoogleInteraction>, AiError> create(
    GoogleInteractionRequest request,
  ) {
    if (request.stream == true) {
      return Effect.fail(
        const UnsupportedFeatureError(
          'Use the interaction streaming operation for stream: true.',
          feature: 'streaming',
        ),
      );
    }
    return _client
        .sendJson(
          ProviderHttpRequest(
            method: 'POST',
            path: '/v1/interactions',
            body: request.toJson(),
          ),
          providerId: _providerId,
          api: _api,
          modelId: request.model,
        )
        .flatMap((response, _) => _decode(response, GoogleInteraction.fromJson));
  }

  /// Creates and streams one interaction without reconnecting or polling.
  Flow<GoogleInteractionEvent, AiError> stream(
    GoogleInteractionRequest request, {
    int decodedEventCapacity = 16,
    int maxEventBytes = 8 * 1024 * 1024,
    int? maxStreamBytes,
  }) => _client.sendSse(
    ProviderHttpRequest(
      method: 'POST',
      path: '/v1/interactions',
      headers: const {'accept': 'text/event-stream'},
      body: request.toJson(stream: true),
    ),
    createProtocol: _GoogleInteractionsProtocol.new,
    decodedEventCapacity: decodedEventCapacity,
    maxEventBytes: maxEventBytes,
    maxStreamBytes: maxStreamBytes,
  );

  /// Retrieves one stored interaction without polling or following links.
  Effect<NativeResponse<GoogleInteraction>, AiError> retrieve(String id) {
    final encodedId = _id(id);
    return _client
        .sendJson(
          ProviderHttpRequest(
            method: 'GET',
            path: '/v1/interactions/$encodedId',
          ),
          providerId: _providerId,
          api: _api,
          modelId: _modelId,
        )
        .flatMap((response, _) => _decode(response, GoogleInteraction.fromJson));
  }

  /// Streams one stored interaction from an optional caller-supplied cursor.
  ///
  /// [lastEventId] resumes from the event after that provider cursor. The SDK
  /// retains no cursor and never reconnects this stream automatically.
  Flow<GoogleInteractionEvent, AiError> streamRetrieve(
    String id, {
    String? lastEventId,
    int decodedEventCapacity = 16,
    int maxEventBytes = 8 * 1024 * 1024,
    int? maxStreamBytes,
  }) {
    final encodedId = _id(id);
    if (lastEventId != null && lastEventId.isEmpty) {
      throw ArgumentError.value(lastEventId, 'lastEventId', 'must not be empty');
    }
    final path = Uri(
      path: '/v1/interactions/$encodedId',
      queryParameters: {
        'stream': 'true',
        'last_event_id': ?lastEventId,
      },
    ).toString();
    return _client.sendSse(
      ProviderHttpRequest(
        method: 'GET',
        path: path,
        headers: const {'accept': 'text/event-stream'},
      ),
      createProtocol: _GoogleInteractionsProtocol.new,
      decodedEventCapacity: decodedEventCapacity,
      maxEventBytes: maxEventBytes,
      maxStreamBytes: maxStreamBytes,
    );
  }

  /// Requests cancellation and returns the interaction state from that exchange.
  Effect<NativeResponse<GoogleInteraction>, AiError> cancel(String id) {
    final encodedId = _id(id);
    return _client
        .sendJson(
          ProviderHttpRequest(
            method: 'POST',
            path: '/v1/interactions/$encodedId/cancel',
          ),
          providerId: _providerId,
          api: _api,
          modelId: _modelId,
        )
        .flatMap((response, _) => _decode(response, GoogleInteraction.fromJson));
  }

  /// Deletes one stored interaction and accepts the stable v1 empty success body.
  Effect<NativeResponse<GoogleInteractionDeleteResult>, AiError> delete(String id) {
    final encodedId = _id(id);
    return _client
        .sendJson(
          ProviderHttpRequest(
            method: 'DELETE',
            path: '/v1/interactions/$encodedId',
          ),
          providerId: _providerId,
          api: _api,
          modelId: _modelId,
          allowEmptySuccess: true,
        )
        .map(
          (response, _) => NativeResponse(
            value: GoogleInteractionDeleteResult(response.value),
            payload: response.payload,
            metadata: response.metadata,
          ),
        );
  }
}

final class _GoogleInteractionsProtocol implements SseProtocol<GoogleInteractionEvent> {
  final ListQueue<GoogleInteractionEvent> _events = ListQueue(_diagnosticEventCapacity);
  late ResponseMetadata _metadata;
  var _terminal = false;
  var _done = false;

  @override
  bool get isTerminal => _done;

  @override
  Object? get partialOutput => List<GoogleInteractionEvent>.unmodifiable(_events);

  @override
  Iterable<GoogleInteractionEvent> start(ResponseMetadata metadata) {
    _metadata = metadata;
    return const [];
  }

  @override
  Iterable<GoogleInteractionEvent> decode(SseEvent event) {
    if (event.data.trim() == '[DONE]') {
      _done = true;
      return const [];
    }
    final GoogleInteractionEvent decoded;
    try {
      decoded = GoogleInteractionEvent.fromJson(
        JsonObject.parse(event.data),
        sseId: event.id,
        sseEvent: event.event,
        retry: event.retry,
      );
    } on FormatException catch (error) {
      throw ProtocolError(error.message, partialOutput: partialOutput);
    }
    _events.add(decoded);
    if (_events.length > _diagnosticEventCapacity) _events.removeFirst();
    if (decoded case GoogleInteractionErrorEvent(:final error)) {
      throw ProviderError(
        error?.message ?? 'Google reported an interaction streaming error.',
        statusCode: _metadata.statusCode,
        code: error?.code,
        details: decoded.raw,
        requestId: _metadata.requestId,
        retryAfter: decoded.retry,
        partialOutput: partialOutput,
      );
    }
    switch (decoded) {
      case GoogleInteractionCompletedEvent():
        _terminal = true;
      case GoogleInteractionStatusEvent(:final status) when _isTerminalStatus(status):
        _terminal = true;
      default:
    }
    return [decoded];
  }

  @override
  Iterable<GoogleInteractionEvent> finish() {
    if (!_done) {
      throw ProtocolError(
        'Google interaction stream ended before the documented [DONE] sentinel.',
        partialOutput: partialOutput,
      );
    }
    if (!_terminal) {
      throw ProtocolError(
        'Google interaction stream ended before a terminal status.',
        partialOutput: partialOutput,
      );
    }
    return const [];
  }
}

bool _isTerminalStatus(GoogleInteractionStatus status) => switch (status) {
  GoogleInteractionStatus.requiresAction ||
  GoogleInteractionStatus.completed ||
  GoogleInteractionStatus.failed ||
  GoogleInteractionStatus.cancelled ||
  GoogleInteractionStatus.incomplete => true,
  GoogleInteractionStatus.inProgress || GoogleInteractionStatus.unknown => false,
};

Effect<NativeResponse<T>, AiError> _decode<T>(
  NativeResponse<JsonObject> response,
  T Function(JsonObject) decode,
) {
  try {
    return Effect.succeed(
      NativeResponse(
        value: decode(response.value),
        payload: response.payload,
        metadata: response.metadata,
      ),
    );
  } on FormatException catch (error) {
    return Effect.fail(
      ProtocolError(
        error.message,
        partialOutput: response.payload.json,
      ),
    );
  }
}

String _id(String value) {
  if (value.isEmpty) {
    throw ArgumentError.value(value, 'id', 'must not be empty');
  }
  return Uri.encodeComponent(value);
}
