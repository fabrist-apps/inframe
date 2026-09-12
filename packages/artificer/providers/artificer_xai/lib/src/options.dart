import 'package:artificer_core/artificer_core.dart';
import 'package:artificer_core/json.dart';
import 'package:artificer_xai/src/responses/response_models.dart';

/// Native reasoning configuration for the Responses API.
final class XaiReasoningOptions {
  /// Creates reasoning configuration from documented native values.
  const XaiReasoningOptions({this.effort, this.summary});

  /// Requested reasoning effort.
  final String? effort;

  /// Requested reasoning-summary mode.
  final String? summary;

  /// Encodes this configuration.
  JsonObject toJson() => JsonObject({'effort': ?effort, 'summary': ?summary});
}

/// Xai inference service tier.
enum XaiServiceTier {
  /// Let Xai choose the tier.
  auto('auto'),

  /// Priority processing.
  priority('priority');

  const XaiServiceTier(this.wireValue);

  /// Value sent on the wire.
  final String wireValue;
}

/// Additional native response data requested by the caller.
enum XaiResponseInclude {
  /// Encrypted reasoning content needed for stateless replay.
  reasoningEncryptedContent('reasoning.encrypted_content'),

  /// Sources returned by web search.
  webSearchSources('web_search_call.action.sources'),

  /// File-search result records.
  fileSearchResults('file_search_call.results'),

  /// Code-interpreter execution outputs.
  codeInterpreterOutputs('code_interpreter_call.outputs');

  const XaiResponseInclude(this.wireValue);

  /// Value sent on the wire.
  final String wireValue;
}

/// Immutable Xai language-model defaults or per-call overrides.
final class XaiModelOptions {
  /// Creates provider settings using explicit inherit/set/clear semantics.
  XaiModelOptions({
    Setting<XaiReasoningOptions> reasoning = const Setting<XaiReasoningOptions>.inherit(),
    Setting<String> promptCacheKey = const Setting<String>.inherit(),
    Setting<XaiServiceTier> serviceTier = const Setting<XaiServiceTier>.inherit(),
    Setting<XaiInferenceOptions> inference = const Setting<XaiInferenceOptions>.inherit(),
    Setting<List<XaiResponseInclude>> include = const Setting<List<XaiResponseInclude>>.inherit(),
    Setting<List<XaiToolDefinition>> tools = const Setting<List<XaiToolDefinition>>.inherit(),
    JsonObject? extraBody,
  }) : reasoning = _normalizeSetting(reasoning),
       promptCacheKey = _normalizeSetting(promptCacheKey),
       serviceTier = _normalizeSetting(serviceTier),
       inference = _normalizeSetting(inference),
       include = _freezeListSetting(_normalizeSetting(include)),
       tools = _freezeListSetting(_normalizeSetting(tools)),
       extraBody = extraBody ?? JsonObject({});

  /// Reasoning configuration.
  final Setting<XaiReasoningOptions> reasoning;

  /// Stable provider cache identifier.
  final Setting<String> promptCacheKey;

  /// Requested service tier.
  final Setting<XaiServiceTier> serviceTier;

  /// xAI-specific inference controls.
  final Setting<XaiInferenceOptions> inference;

  /// Additional native response fields to return.
  final Setting<List<XaiResponseInclude>> include;

  /// Provider-defined native tools.
  final Setting<List<XaiToolDefinition>> tools;

  /// Forward-compatible native fields that do not collide with typed fields.
  final JsonObject extraBody;

  /// Resolves reasoning against model defaults.
  XaiReasoningOptions? resolveReasoning(XaiModelOptions? call) =>
      call == null ? reasoning.resolve(null) : call.reasoning.resolve(reasoning.resolve(null));

  /// Resolves the cache key against model defaults.
  String? resolvePromptCacheKey(XaiModelOptions? call) => call == null
      ? promptCacheKey.resolve(null)
      : call.promptCacheKey.resolve(promptCacheKey.resolve(null));

  /// Resolves the service tier against model defaults.
  XaiServiceTier? resolveServiceTier(XaiModelOptions? call) => call == null
      ? serviceTier.resolve(null)
      : call.serviceTier.resolve(serviceTier.resolve(null));

  /// Resolves xAI inference controls against model defaults.
  XaiInferenceOptions? resolveInference(XaiModelOptions? call) =>
      call == null ? inference.resolve(null) : call.inference.resolve(inference.resolve(null));

  /// Resolves include selectors, replacing the inherited collection when set.
  List<XaiResponseInclude>? resolveInclude(XaiModelOptions? call) =>
      call == null ? include.resolve(null) : call.include.resolve(include.resolve(null));

  /// Resolves native tools, replacing the inherited collection when set.
  List<XaiToolDefinition>? resolveTools(XaiModelOptions? call) =>
      call == null ? tools.resolve(null) : call.tools.resolve(tools.resolve(null));

  /// Merges forward-compatible fields with per-call fields taking precedence.
  JsonObject resolveExtraBody(XaiModelOptions? call) => JsonObject({
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
