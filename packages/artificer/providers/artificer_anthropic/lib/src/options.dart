import 'package:artificer_core/json.dart';

/// An Anthropic API version sent explicitly with every request.
final class AnthropicApiVersion {
  /// Creates a version from its documented header value.
  const AnthropicApiVersion(this.headerValue);

  /// The stable Messages API version used by default.
  static const v20230601 = AnthropicApiVersion('2023-06-01');

  /// Value sent in the `anthropic-version` header.
  final String headerValue;
}

/// A documented Anthropic beta feature header value.
final class AnthropicBeta {
  /// Creates a beta selector from its documented header value.
  const AnthropicBeta(this.headerValue);

  /// Structured output configuration for Messages.
  static const structuredOutputs20251113 = AnthropicBeta(
    'structured-outputs-2025-11-13',
  );

  /// Value sent in the `anthropic-beta` header.
  final String headerValue;
}

/// Immutable Anthropic model defaults or per-call overrides.
final class AnthropicModelOptions {
  /// Creates provider options.
  AnthropicModelOptions({JsonObject? extraBody}) : extraBody = extraBody ?? JsonObject({});

  /// Forward-compatible native fields that do not collide with typed fields.
  final JsonObject extraBody;

  /// Merges forward-compatible fields with per-call fields taking precedence.
  JsonObject resolveExtraBody(AnthropicModelOptions? call) => JsonObject({
    ...extraBody.toDart(),
    ...?call?.extraBody.toDart(),
  });
}
