import 'package:artificer_core/artificer_core.dart';
import 'package:artificer_core/json.dart';
import 'package:artificer_openai/src/responses/response_models.dart';

/// Native reasoning configuration for the Responses API.
final class OpenAIReasoningOptions {
  /// Creates reasoning configuration from documented native values.
  const OpenAIReasoningOptions({this.effort, this.summary});

  /// Requested reasoning effort.
  final String? effort;

  /// Requested reasoning-summary mode.
  final String? summary;

  /// Encodes this configuration.
  JsonObject toJson() => JsonObject({'effort': ?effort, 'summary': ?summary});
}

/// OpenAI inference service tier.
enum OpenAIServiceTier {
  /// Let OpenAI choose the tier.
  auto('auto'),

  /// Standard processing.
  defaultTier('default'),

  /// Fast processing for supported models.
  fast('fast'),

  /// Scale-tier processing.
  flex('flex'),

  /// Priority processing.
  priority('priority');

  const OpenAIServiceTier(this.wireValue);

  /// Value sent on the wire.
  final String wireValue;
}

/// Additional native response data requested by the caller.
enum OpenAIResponseInclude {
  /// Encrypted reasoning content needed for stateless replay.
  reasoningEncryptedContent('reasoning.encrypted_content'),

  /// Sources returned by web search.
  webSearchSources('web_search_call.action.sources'),

  /// File-search result records.
  fileSearchResults('file_search_call.results'),

  /// Code-interpreter execution outputs.
  codeInterpreterOutputs('code_interpreter_call.outputs');

  const OpenAIResponseInclude(this.wireValue);

  /// Value sent on the wire.
  final String wireValue;
}

/// Immutable OpenAI language-model defaults or per-call overrides.
final class OpenAIModelOptions {
  /// Creates provider settings using explicit inherit/set/clear semantics.
  OpenAIModelOptions({
    Setting<OpenAIReasoningOptions> reasoning = const Setting<OpenAIReasoningOptions>.inherit(),
    Setting<String> promptCacheKey = const Setting<String>.inherit(),
    Setting<String> promptCacheRetention = const Setting<String>.inherit(),
    Setting<OpenAIServiceTier> serviceTier = const Setting<OpenAIServiceTier>.inherit(),
    Setting<List<OpenAIResponseInclude>> include =
        const Setting<List<OpenAIResponseInclude>>.inherit(),
    Setting<List<OpenAIToolDefinition>> tools = const Setting<List<OpenAIToolDefinition>>.inherit(),
    JsonObject? extraBody,
  }) : reasoning = _normalizeSetting(reasoning),
       promptCacheKey = _normalizeSetting(promptCacheKey),
       promptCacheRetention = _normalizeSetting(promptCacheRetention),
       serviceTier = _normalizeSetting(serviceTier),
       include = _freezeListSetting(_normalizeSetting(include)),
       tools = _freezeListSetting(_normalizeSetting(tools)),
       extraBody = extraBody ?? JsonObject({});

  /// Reasoning configuration.
  final Setting<OpenAIReasoningOptions> reasoning;

  /// Stable provider cache identifier.
  final Setting<String> promptCacheKey;

  /// Native cache-retention policy.
  final Setting<String> promptCacheRetention;

  /// Requested service tier.
  final Setting<OpenAIServiceTier> serviceTier;

  /// Additional native response fields to return.
  final Setting<List<OpenAIResponseInclude>> include;

  /// Provider-defined native tools.
  final Setting<List<OpenAIToolDefinition>> tools;

  /// Forward-compatible native fields that do not collide with typed fields.
  final JsonObject extraBody;

  /// Resolves reasoning against model defaults.
  OpenAIReasoningOptions? resolveReasoning(OpenAIModelOptions? call) =>
      call == null ? reasoning.resolve(null) : call.reasoning.resolve(reasoning.resolve(null));

  /// Resolves the cache key against model defaults.
  String? resolvePromptCacheKey(OpenAIModelOptions? call) => call == null
      ? promptCacheKey.resolve(null)
      : call.promptCacheKey.resolve(promptCacheKey.resolve(null));

  /// Resolves cache retention against model defaults.
  String? resolvePromptCacheRetention(OpenAIModelOptions? call) => call == null
      ? promptCacheRetention.resolve(null)
      : call.promptCacheRetention.resolve(promptCacheRetention.resolve(null));

  /// Resolves the service tier against model defaults.
  OpenAIServiceTier? resolveServiceTier(OpenAIModelOptions? call) => call == null
      ? serviceTier.resolve(null)
      : call.serviceTier.resolve(serviceTier.resolve(null));

  /// Resolves include selectors, replacing the inherited collection when set.
  List<OpenAIResponseInclude>? resolveInclude(OpenAIModelOptions? call) =>
      call == null ? include.resolve(null) : call.include.resolve(include.resolve(null));

  /// Resolves native tools, replacing the inherited collection when set.
  List<OpenAIToolDefinition>? resolveTools(OpenAIModelOptions? call) =>
      call == null ? tools.resolve(null) : call.tools.resolve(tools.resolve(null));

  /// Merges forward-compatible fields with per-call fields taking precedence.
  JsonObject resolveExtraBody(OpenAIModelOptions? call) => JsonObject({
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
