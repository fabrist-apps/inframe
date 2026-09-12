import 'package:artificer_anthropic/src/messages/message_models.dart';
import 'package:artificer_core/artificer_core.dart';
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
  AnthropicModelOptions({
    Setting<AnthropicCacheControl> cacheControl = const Setting<AnthropicCacheControl>.inherit(),
    JsonObject? extraBody,
  }) : cacheControl = _copySetting(cacheControl),
       extraBody = extraBody ?? JsonObject({});

  /// Top-level cache breakpoint.
  final Setting<AnthropicCacheControl> cacheControl;

  /// Forward-compatible native fields that do not collide with typed fields.
  final JsonObject extraBody;

  /// Resolves a top-level cache breakpoint against model defaults.
  AnthropicCacheControl? resolveCacheControl(AnthropicModelOptions? call) => call == null
      ? cacheControl.resolve(null)
      : call.cacheControl.resolve(cacheControl.resolve(null));

  /// Merges forward-compatible fields with per-call fields taking precedence.
  JsonObject resolveExtraBody(AnthropicModelOptions? call) => JsonObject({
    ...extraBody.toDart(),
    ...?call?.extraBody.toDart(),
  });
}

Setting<T> _copySetting<T>(Setting<T> setting) => switch (setting) {
  InheritSetting() => Setting<T>.inherit(),
  ClearSetting() => Setting<T>.clear(),
  SetSetting(:final value) => Setting<T>.set(value),
};
