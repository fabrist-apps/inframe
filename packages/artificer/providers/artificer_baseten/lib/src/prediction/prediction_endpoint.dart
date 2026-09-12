import 'dart:typed_data';

import 'package:artificer_core/artificer_core.dart';
import 'package:artificer_core/json.dart';
import 'package:artificer_core/transport.dart';
import 'package:conflux/conflux.dart';

const _providerId = 'baseten';
const _api = 'prediction';

/// A caller-typed binding to one exact Baseten prediction URL.
final class BasetenPredictionEndpoint<I, O> {
  /// Creates a binding over a provider-owned client.
  ///
  /// Prefer `BasetenProvider.predictionEndpoint`. The callbacks must be pure:
  /// each execution invokes them independently and may run concurrently.
  const BasetenPredictionEndpoint(
    this._client,
    this._path,
    this._encode,
    this._decode,
    this._decodedChunkCapacity,
  );

  final ProviderHttpClient _client;
  final String _path;
  final JsonValue Function(I input) _encode;
  final O Function(JsonValue json) _decode;
  final int _decodedChunkCapacity;

  /// Encodes, posts, and decodes one prediction when the effect executes.
  Effect<NativeResponse<O>, AiError> predict(I input) => Effect.defer(() {
    final body = _encode(input);
    return _client
        .sendJsonValue(
          ProviderHttpRequest(method: 'POST', path: _path, body: body),
          providerId: _providerId,
          api: _api,
          modelId: _api,
        )
        .flatMap((response) {
          try {
            return Effect.succeed(
              NativeResponse(
                value: _decode(response.value),
                payload: response.payload,
                metadata: response.metadata,
              ),
            );
          } on FormatException catch (error) {
            return Effect.fail(
              ProtocolError(error.message, partialOutput: response.value),
            );
          }
        });
  });

  /// Streams raw response bytes until normal HTTP EOF.
  ///
  /// The encoder selects any provider-specific stream fields. No response
  /// framing, sentinel, or terminal event is inferred, and [_decode] is not
  /// invoked.
  Flow<Uint8List, AiError> predictRawStream(I input) => Flow.defer(() {
    final body = _encode(input);
    return _client
        .sendBytes(
          ProviderHttpRequest(method: 'POST', path: _path, body: body),
          decodedChunkCapacity: _decodedChunkCapacity,
        )
        .map(
          (bytes) => bytes is Uint8List ? bytes : Uint8List.fromList(bytes).asUnmodifiableView(),
        );
  });
}
