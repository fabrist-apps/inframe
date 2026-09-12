import 'package:artificer_anthropic/src/messages/message_models.dart';
import 'package:artificer_anthropic/src/messages/tool_models.dart';
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

  /// Remote MCP servers in beta Messages requests.
  static const mcpClient20251120 = AnthropicBeta('mcp-client-2025-11-20');

  /// Caller-executed computer use tools.
  static const computerUse20250124 = AnthropicBeta('computer-use-2025-01-24');

  /// Provider-hosted code execution.
  static const codeExecution20250522 = AnthropicBeta('code-execution-2025-05-22');

  /// Thinking interleaved with tool use.
  static const interleavedThinking20250514 = AnthropicBeta(
    'interleaved-thinking-2025-05-14',
  );

  /// Value sent in the `anthropic-beta` header.
  final String headerValue;
}

/// Immutable Anthropic model defaults or per-call overrides.
final class AnthropicModelOptions {
  /// Creates provider options.
  AnthropicModelOptions({
    Setting<AnthropicCacheControl> cacheControl = const Setting<AnthropicCacheControl>.inherit(),
    Setting<AnthropicThinkingConfig> thinking = const Setting<AnthropicThinkingConfig>.inherit(),
    Setting<AnthropicEffort> effort = const Setting<AnthropicEffort>.inherit(),
    Setting<AnthropicServiceTier> serviceTier = const Setting<AnthropicServiceTier>.inherit(),
    Setting<List<AnthropicBeta>> betaFeatures = const Setting<List<AnthropicBeta>>.inherit(),
    Setting<List<AnthropicNativeTool>> nativeTools =
        const Setting<List<AnthropicNativeTool>>.inherit(),
    Setting<List<AnthropicRemoteMcpServer>> remoteMcpServers =
        const Setting<List<AnthropicRemoteMcpServer>>.inherit(),
    JsonObject? extraBody,
  }) : cacheControl = _copySetting(cacheControl),
       thinking = _copySetting(thinking),
       effort = _copySetting(effort),
       serviceTier = _copySetting(serviceTier),
       betaFeatures = _copyListSetting(betaFeatures),
       nativeTools = _copyListSetting(nativeTools),
       remoteMcpServers = _copyListSetting(remoteMcpServers),
       extraBody = extraBody ?? JsonObject({});

  /// Top-level cache breakpoint.
  final Setting<AnthropicCacheControl> cacheControl;

  /// Native thinking configuration.
  final Setting<AnthropicThinkingConfig> thinking;

  /// Requested model effort.
  final Setting<AnthropicEffort> effort;

  /// Requested service capacity.
  final Setting<AnthropicServiceTier> serviceTier;

  /// Per-request beta feature header values.
  final Setting<List<AnthropicBeta>> betaFeatures;

  /// Native tool definitions merged with common function declarations.
  final Setting<List<AnthropicNativeTool>> nativeTools;

  /// Remote MCP servers forwarded to Anthropic.
  final Setting<List<AnthropicRemoteMcpServer>> remoteMcpServers;

  /// Forward-compatible native fields that do not collide with typed fields.
  final JsonObject extraBody;

  /// Resolves a top-level cache breakpoint against model defaults.
  AnthropicCacheControl? resolveCacheControl(AnthropicModelOptions? call) => call == null
      ? cacheControl.resolve(null)
      : call.cacheControl.resolve(cacheControl.resolve(null));

  /// Resolves thinking configuration against model defaults.
  AnthropicThinkingConfig? resolveThinking(AnthropicModelOptions? call) =>
      _resolve(thinking, call?.thinking);

  /// Resolves effort against model defaults.
  AnthropicEffort? resolveEffort(AnthropicModelOptions? call) => _resolve(effort, call?.effort);

  /// Resolves service tier against model defaults.
  AnthropicServiceTier? resolveServiceTier(AnthropicModelOptions? call) =>
      _resolve(serviceTier, call?.serviceTier);

  /// Resolves beta features against model defaults.
  List<AnthropicBeta> resolveBetaFeatures(AnthropicModelOptions? call) =>
      _resolve(betaFeatures, call?.betaFeatures) ?? const [];

  /// Resolves native tools against model defaults.
  List<AnthropicNativeTool> resolveNativeTools(AnthropicModelOptions? call) =>
      _resolve(nativeTools, call?.nativeTools) ?? const [];

  /// Resolves remote MCP servers against model defaults.
  List<AnthropicRemoteMcpServer> resolveRemoteMcpServers(AnthropicModelOptions? call) =>
      _resolve(remoteMcpServers, call?.remoteMcpServers) ?? const [];

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

Setting<List<T>> _copyListSetting<T>(Setting<List<T>> setting) => switch (setting) {
  InheritSetting() => Setting<List<T>>.inherit(),
  ClearSetting() => Setting<List<T>>.clear(),
  SetSetting(:final value) => Setting<List<T>>.set(List.unmodifiable(value)),
};

T? _resolve<T>(Setting<T> model, Setting<T>? call) =>
    call == null ? model.resolve(null) : call.resolve(model.resolve(null));
