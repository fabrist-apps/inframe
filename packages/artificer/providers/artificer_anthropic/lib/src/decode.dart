import 'package:artificer_core/artificer_core.dart';
import 'package:artificer_core/json.dart';
import 'package:conflux/conflux.dart';

/// Decodes one successful native response and maps wire-shape failures into the
/// provider error channel while preserving payload and HTTP metadata.
Effect<NativeResponse<T>, AiError> decodeNativeResponse<T>(
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
    return Effect.fail(ProtocolError(error.message));
  }
}
