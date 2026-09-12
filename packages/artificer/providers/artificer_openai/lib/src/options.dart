import 'package:artificer_core/json.dart';

/// Immutable OpenAI language-model defaults or per-call overrides.
final class OpenAIModelOptions {
  /// Creates [OpenAIModelOptions].
  OpenAIModelOptions({JsonObject? extraBody}) : extraBody = extraBody ?? JsonObject({});

  /// Forward-compatible native fields that do not collide with typed fields.
  final JsonObject extraBody;
}
