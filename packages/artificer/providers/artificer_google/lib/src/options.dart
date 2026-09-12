import 'package:artificer_core/artificer_core.dart';
import 'package:artificer_core/json.dart';
import 'package:artificer_google/src/generate_content/generate_content_models.dart';
import 'package:artificer_google/src/generate_content/tool_models.dart';

/// Immutable Google language-model defaults or per-call overrides.
final class GoogleModelOptions {
  /// Creates native settings using explicit inherit/set/clear semantics.
  GoogleModelOptions({
    Setting<GoogleThinkingConfig> thinkingConfig = const Setting<GoogleThinkingConfig>.inherit(),
    Setting<List<GoogleSafetySetting>> safetySettings =
        const Setting<List<GoogleSafetySetting>>.inherit(),
    Setting<String> cachedContent = const Setting<String>.inherit(),
    Setting<List<GoogleToolDefinition>> tools = const Setting<List<GoogleToolDefinition>>.inherit(),
    Setting<GoogleToolConfig> toolConfig = const Setting<GoogleToolConfig>.inherit(),
    JsonObject? extraBody,
  }) : thinkingConfig = _normalizeSetting(thinkingConfig),
       safetySettings = _freezeListSetting(_normalizeSetting(safetySettings)),
       cachedContent = _normalizeSetting(cachedContent),
       tools = _freezeListSetting(_normalizeSetting(tools)),
       toolConfig = _normalizeSetting(toolConfig),
       extraBody = extraBody ?? JsonObject({});

  /// Native thinking configuration nested in `generationConfig`.
  final Setting<GoogleThinkingConfig> thinkingConfig;

  /// Native safety policy, replacing the inherited list when set.
  final Setting<List<GoogleSafetySetting>> safetySettings;

  /// An explicit `cachedContents/{id}` resource name.
  final Setting<String> cachedContent;

  /// Provider-defined native tools, replacing the inherited list when set.
  final Setting<List<GoogleToolDefinition>> tools;

  /// Native tool configuration.
  final Setting<GoogleToolConfig> toolConfig;

  /// Forward-compatible top-level fields that do not collide with typed fields.
  final JsonObject extraBody;

  /// Resolves thinking configuration against model defaults.
  GoogleThinkingConfig? resolveThinkingConfig(GoogleModelOptions? call) => call == null
      ? thinkingConfig.resolve(null)
      : call.thinkingConfig.resolve(thinkingConfig.resolve(null));

  /// Resolves safety settings against model defaults.
  List<GoogleSafetySetting>? resolveSafetySettings(GoogleModelOptions? call) => call == null
      ? safetySettings.resolve(null)
      : call.safetySettings.resolve(safetySettings.resolve(null));

  /// Resolves the cache resource name against model defaults.
  String? resolveCachedContent(GoogleModelOptions? call) => call == null
      ? cachedContent.resolve(null)
      : call.cachedContent.resolve(cachedContent.resolve(null));

  /// Resolves native tools, replacing the inherited collection when set.
  List<GoogleToolDefinition>? resolveTools(GoogleModelOptions? call) =>
      call == null ? tools.resolve(null) : call.tools.resolve(tools.resolve(null));

  /// Resolves native tool configuration.
  GoogleToolConfig? resolveToolConfig(GoogleModelOptions? call) =>
      call == null ? toolConfig.resolve(null) : call.toolConfig.resolve(toolConfig.resolve(null));

  /// Merges forward-compatible fields with per-call fields taking precedence.
  JsonObject resolveExtraBody(GoogleModelOptions? call) => JsonObject({
    ...extraBody.toDart(),
    ...?call?.extraBody.toDart(),
  });
}

Setting<List<T>> _freezeListSetting<T>(Setting<List<T>> setting) => switch (setting) {
  SetSetting<List<T>>(:final value) => Setting.set(List.unmodifiable(value)),
  InheritSetting<List<T>>() => Setting<List<T>>.inherit(),
  ClearSetting<List<T>>() => Setting<List<T>>.clear(),
};

Setting<T> _normalizeSetting<T>(Setting<T> setting) => switch (setting) {
  InheritSetting() => Setting<T>.inherit(),
  ClearSetting() => Setting<T>.clear(),
  SetSetting(:final value) => Setting<T>.set(value),
};
