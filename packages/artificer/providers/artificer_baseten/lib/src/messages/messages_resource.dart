import 'package:artificer_baseten/src/messages/message_events.dart';
import 'package:artificer_baseten/src/messages/message_models.dart';
import 'package:artificer_core/artificer_core.dart';
import 'package:artificer_core/json.dart';
import 'package:artificer_core/protocols.dart';
import 'package:artificer_core/transport.dart';
import 'package:conflux/conflux.dart';

const _providerId = 'baseten';
const _api = 'messages.beta';

/// Typed native access to Baseten's beta Messages endpoint.
final class BasetenMessagesResource {
  /// Creates the resource over a provider-owned catalog client.
  const BasetenMessagesResource(this._client);

  final ProviderHttpClient _client;

  /// Creates one beta native Message.
  Effect<NativeResponse<BasetenMessageResponse>, AiError> create(
    BasetenMessageRequest request,
  ) => _client
      .sendJson(
        ProviderHttpRequest(
          method: 'POST',
          path: 'messages',
          body: request.toJson(stream: false),
        ),
        providerId: _providerId,
        api: _api,
        modelId: request.model,
      )
      .flatMap((response, _) => _decodeResponse(response));

  /// Streams typed native beta Messages events.
  Flow<BasetenMessageEvent, AiError> stream(
    BasetenMessageRequest request, {
    int decodedEventCapacity = 16,
    int maxEventBytes = 8 * 1024 * 1024,
    int? maxStreamBytes,
  }) => _client.sendSse(
    ProviderHttpRequest(
      method: 'POST',
      path: 'messages',
      body: request.toJson(stream: true),
    ),
    createProtocol: _BasetenMessagesProtocol.new,
    decodedEventCapacity: decodedEventCapacity,
    maxEventBytes: maxEventBytes,
    maxStreamBytes: maxStreamBytes,
  );

  Effect<NativeResponse<BasetenMessageResponse>, AiError> _decodeResponse(
    NativeResponse<JsonObject> response,
  ) {
    try {
      return Effect.succeed(
        NativeResponse(
          value: BasetenMessageResponse.fromJson(response.value),
          payload: response.payload,
          metadata: response.metadata,
        ),
      );
    } on FormatException catch (error) {
      return Effect.fail(
        ProtocolError(error.message, partialOutput: response.value),
      );
    }
  }
}

final class _BasetenMessagesProtocol implements SseProtocol<BasetenMessageEvent> {
  var _terminal = false;
  ResponseMetadata? _metadata;

  @override
  bool get isTerminal => _terminal;

  @override
  Object? get partialOutput => null;

  @override
  Iterable<BasetenMessageEvent> start(ResponseMetadata metadata) {
    _metadata = metadata;
    return const [];
  }

  @override
  Iterable<BasetenMessageEvent> decode(SseEvent event) {
    try {
      final raw = JsonObject.parse(event.data);
      final value = raw.toDart();
      final type = value['type'];
      if (type is! String || type.isEmpty) {
        throw const FormatException('Messages event type must be a string.');
      }
      if (type == 'error') {
        final error = value['error'];
        final details = error is Map<String, Object?> ? JsonObject(error) : raw;
        final message = error is Map<String, Object?> && error['message'] is String
            ? error['message']! as String
            : 'Baseten returned a streamed Messages error.';
        final code = error is Map<String, Object?> && error['type'] is String
            ? error['type']! as String
            : null;
        throw ProviderError(
          message,
          code: code,
          details: details,
          requestId: _metadata?.requestId,
        );
      }
      if (type == 'message_stop') {
        _terminal = true;
        return [BasetenMessageStopEvent(raw)];
      }
      if (_knownEvents.contains(type)) {
        return [BasetenKnownMessageEvent(type, raw)];
      }
      return [BasetenUnknownMessageEvent(type, raw)];
    } on AiError {
      rethrow;
    } on FormatException catch (error) {
      throw ProtocolError('Malformed Baseten Messages event: ${error.message}');
    }
  }

  @override
  Iterable<BasetenMessageEvent> finish() {
    if (!_terminal) {
      throw const ProtocolError('Baseten Messages stream ended before message_stop.');
    }
    return const [];
  }
}

const _knownEvents = {
  'message_start',
  'content_block_start',
  'content_block_delta',
  'content_block_stop',
  'message_delta',
  'ping',
};
