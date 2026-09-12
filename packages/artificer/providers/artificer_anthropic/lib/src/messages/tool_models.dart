import 'package:artificer_anthropic/src/messages/message_models.dart';
import 'package:artificer_core/artificer_core.dart' show ToolExecutionOwner;
import 'package:artificer_core/json.dart';

/// A caller that Anthropic may permit to invoke another tool.
enum AnthropicToolCaller {
  /// Claude invokes the tool directly.
  direct('direct'),

  /// The `code_execution_20250825` tool may invoke the tool.
  codeExecution20250825('code_execution_20250825'),

  /// The `code_execution_20260120` tool may invoke the tool.
  codeExecution20260120('code_execution_20260120'),

  /// The `code_execution_20260521` tool may invoke the tool.
  codeExecution20260521('code_execution_20260521');

  const AnthropicToolCaller(this.wireValue);

  /// Value sent in `allowed_callers`.
  final String wireValue;
}

/// Whether nested hosted-tool results remain in a Messages response.
enum AnthropicToolResponseInclusion {
  /// Return the complete nested tool-use and result blocks.
  full('full'),

  /// Omit results consumed by a completed code-execution call in the same turn.
  excluded('excluded');

  const AnthropicToolResponseInclusion(this.wireValue);

  /// Value sent in `response_inclusion`.
  final String wireValue;
}

/// A versioned native tool definition accepted by Anthropic Messages.
sealed class AnthropicNativeTool implements AnthropicToolDefinition {
  AnthropicNativeTool({
    required this.name,
    required this.type,
    required this.executionOwner,
    Iterable<AnthropicToolCaller> allowedCallers = const [],
    this.cacheControl,
    this.deferLoading,
    this.strict,
    JsonObject? extensions,
    Set<String> reservedFields = const {},
  }) : allowedCallers = List.unmodifiable(allowedCallers),
       extensions = extensions ?? JsonObject({}) {
    final collisions = this.extensions.values.keys.toSet().intersection({
      ..._commonToolFields,
      ...reservedFields,
    });
    if (collisions.isNotEmpty) {
      throw ArgumentError.value(
        extensions,
        'extensions',
        'must not replace typed fields: ${collisions.toList()..sort()}',
      );
    }
  }

  /// Fixed name Anthropic emits for this tool family.
  @override
  final String name;

  /// Pinned versioned wire discriminator.
  final String type;

  /// Component responsible for executing calls to this definition.
  final ToolExecutionOwner executionOwner;

  /// Callers allowed to invoke this tool, when constrained.
  final List<AnthropicToolCaller> allowedCallers;

  /// Optional prompt-cache breakpoint.
  final AnthropicCacheControl? cacheControl;

  /// Whether tool search must load this definition before use.
  final bool? deferLoading;

  /// Whether Anthropic validates tool names and inputs strictly.
  final bool? strict;

  /// Immutable fields outside the pinned typed surface.
  final JsonObject extensions;

  /// Encodes this definition for `tools[]`.
  @override
  JsonObject toJson();

  JsonObject _toJson(Map<String, Object?> fields) => JsonObject({
    'name': name,
    'type': type,
    if (allowedCallers.isNotEmpty)
      'allowed_callers': allowedCallers.map((caller) => caller.wireValue).toList(),
    if (cacheControl case final value?) 'cache_control': value.toDart(),
    'defer_loading': ?deferLoading,
    'strict': ?strict,
    ...fields,
    ...extensions.toDart(),
  });
}

/// Anthropic-hosted web search pinned to the 2026-03-18 schema.
final class AnthropicWebSearchTool extends AnthropicNativeTool {
  /// Creates a web-search definition.
  AnthropicWebSearchTool({
    Iterable<String> allowedDomains = const [],
    Iterable<String> blockedDomains = const [],
    this.maxUses,
    this.responseInclusion,
    this.userLocation,
    super.allowedCallers,
    super.cacheControl,
    super.deferLoading,
    super.strict,
    super.extensions,
  }) : allowedDomains = List.unmodifiable(allowedDomains),
       blockedDomains = List.unmodifiable(blockedDomains),
       super(
         name: 'web_search',
         type: discriminator,
         executionOwner: ToolExecutionOwner.provider,
         reservedFields: _webSearchFields,
       ) {
    _validateDomains(this.allowedDomains, 'allowedDomains');
    _validateDomains(this.blockedDomains, 'blockedDomains');
    if (this.allowedDomains.isNotEmpty && this.blockedDomains.isNotEmpty) {
      throw ArgumentError(
        'allowedDomains and blockedDomains cannot both be supplied.',
      );
    }
    _validatePositive(maxUses, 'maxUses');
  }

  /// Versioned discriminator from the pinned Messages schema.
  static const discriminator = 'web_search_20260318';

  /// Domains that may appear in results.
  final List<String> allowedDomains;

  /// Domains that must not appear in results.
  final List<String> blockedDomains;

  /// Maximum number of searches in this request.
  final int? maxUses;

  /// Inclusion policy for results consumed by completed code execution.
  final AnthropicToolResponseInclusion? responseInclusion;

  /// Approximate location object used to localize results.
  final JsonObject? userLocation;

  @override
  JsonObject toJson() => _toJson({
    if (allowedDomains.isNotEmpty) 'allowed_domains': allowedDomains,
    if (blockedDomains.isNotEmpty) 'blocked_domains': blockedDomains,
    'max_uses': ?maxUses,
    'response_inclusion': ?responseInclusion?.wireValue,
    'user_location': ?userLocation?.toDart(),
  });
}

/// Anthropic-hosted URL fetching pinned to the 2026-03-18 schema.
final class AnthropicWebFetchTool extends AnthropicNativeTool {
  /// Creates a web-fetch definition.
  AnthropicWebFetchTool({
    Iterable<String> allowedDomains = const [],
    Iterable<String> blockedDomains = const [],
    this.citationsEnabled,
    this.maxContentTokens,
    this.maxUses,
    this.responseInclusion,
    this.useCache,
    super.allowedCallers,
    super.cacheControl,
    super.deferLoading,
    super.strict,
    super.extensions,
  }) : allowedDomains = List.unmodifiable(allowedDomains),
       blockedDomains = List.unmodifiable(blockedDomains),
       super(
         name: 'web_fetch',
         type: discriminator,
         executionOwner: ToolExecutionOwner.provider,
         reservedFields: _webFetchFields,
       ) {
    _validateDomains(this.allowedDomains, 'allowedDomains');
    _validateDomains(this.blockedDomains, 'blockedDomains');
    _validatePositive(maxContentTokens, 'maxContentTokens');
    _validatePositive(maxUses, 'maxUses');
  }

  /// Versioned discriminator from the pinned Messages schema.
  static const discriminator = 'web_fetch_20260318';

  /// Domains the tool may fetch.
  final List<String> allowedDomains;

  /// Domains the tool must not fetch.
  final List<String> blockedDomains;

  /// Whether fetched documents include citations.
  final bool? citationsEnabled;

  /// Approximate maximum page-text token count.
  final int? maxContentTokens;

  /// Maximum number of fetches in this request.
  final int? maxUses;

  /// Inclusion policy for results consumed by completed code execution.
  final AnthropicToolResponseInclusion? responseInclusion;

  /// Whether Anthropic may use cached fetched content.
  final bool? useCache;

  @override
  JsonObject toJson() => _toJson({
    if (allowedDomains.isNotEmpty) 'allowed_domains': allowedDomains,
    if (blockedDomains.isNotEmpty) 'blocked_domains': blockedDomains,
    if (citationsEnabled case final enabled?) 'citations': {'enabled': enabled},
    'max_content_tokens': ?maxContentTokens,
    'max_uses': ?maxUses,
    'response_inclusion': ?responseInclusion?.wireValue,
    'use_cache': ?useCache,
  });
}

/// Anthropic-hosted code execution pinned to the 2026-05-21 schema.
final class AnthropicCodeExecutionTool extends AnthropicNativeTool {
  /// Creates a code-execution definition.
  AnthropicCodeExecutionTool({
    super.allowedCallers,
    super.cacheControl,
    super.deferLoading,
    super.strict,
    super.extensions,
  }) : super(
         name: 'code_execution',
         type: discriminator,
         executionOwner: ToolExecutionOwner.provider,
       );

  /// Versioned discriminator from the pinned Messages schema.
  static const discriminator = 'code_execution_20260521';

  @override
  JsonObject toJson() => _toJson(const {});
}

/// Anthropic-hosted tool search pinned to the 2025-11-19 schema.
final class AnthropicToolSearchTool extends AnthropicNativeTool {
  AnthropicToolSearchTool._({
    required super.name,
    required super.type,
    super.allowedCallers,
    super.cacheControl,
    super.deferLoading,
    super.strict,
    super.extensions,
  }) : super(
         executionOwner: ToolExecutionOwner.provider,
       );

  /// Creates the BM25 tool-search variant.
  factory AnthropicToolSearchTool.bm25({
    Iterable<AnthropicToolCaller> allowedCallers = const [],
    AnthropicCacheControl? cacheControl,
    bool? deferLoading,
    bool? strict,
    JsonObject? extensions,
  }) => AnthropicToolSearchTool._(
    name: 'tool_search_tool_bm25',
    type: bm25Discriminator,
    allowedCallers: allowedCallers,
    cacheControl: cacheControl,
    deferLoading: deferLoading,
    strict: strict,
    extensions: extensions,
  );

  /// Creates the regex tool-search variant.
  factory AnthropicToolSearchTool.regex({
    Iterable<AnthropicToolCaller> allowedCallers = const [],
    AnthropicCacheControl? cacheControl,
    bool? deferLoading,
    bool? strict,
    JsonObject? extensions,
  }) => AnthropicToolSearchTool._(
    name: 'tool_search_tool_regex',
    type: regexDiscriminator,
    allowedCallers: allowedCallers,
    cacheControl: cacheControl,
    deferLoading: deferLoading,
    strict: strict,
    extensions: extensions,
  );

  /// Versioned BM25 discriminator from the pinned Messages schema.
  static const bm25Discriminator = 'tool_search_tool_bm25_20251119';

  /// Versioned regex discriminator from the pinned Messages schema.
  static const regexDiscriminator = 'tool_search_tool_regex_20251119';

  @override
  JsonObject toJson() => _toJson(const {});
}

/// Caller-executed computer use pinned to the 2025-11-24 beta schema.
final class AnthropicComputerTool extends AnthropicNativeTool {
  /// Creates a computer-use definition for one display.
  AnthropicComputerTool({
    required this.displayWidthPx,
    required this.displayHeightPx,
    this.displayNumber,
    this.enableZoom,
    Iterable<JsonObject> inputExamples = const [],
    super.allowedCallers,
    super.cacheControl,
    super.deferLoading,
    super.strict,
    super.extensions,
  }) : inputExamples = List.unmodifiable(inputExamples),
       super(
         name: 'computer',
         type: discriminator,
         executionOwner: ToolExecutionOwner.caller,
         reservedFields: _computerFields,
       ) {
    _validatePositive(displayWidthPx, 'displayWidthPx');
    _validatePositive(displayHeightPx, 'displayHeightPx');
    _validateNonNegative(displayNumber, 'displayNumber');
  }

  /// Versioned discriminator from the pinned beta Messages schema.
  static const discriminator = 'computer_20251124';

  /// Display width in pixels.
  final int displayWidthPx;

  /// Display height in pixels.
  final int displayHeightPx;

  /// Optional X11 display number.
  final int? displayNumber;

  /// Whether the zoom action is enabled.
  final bool? enableZoom;

  /// Example native action inputs shown to the model.
  final List<JsonObject> inputExamples;

  @override
  JsonObject toJson() => _toJson({
    'display_width_px': displayWidthPx,
    'display_height_px': displayHeightPx,
    'display_number': ?displayNumber,
    'enable_zoom': ?enableZoom,
    if (inputExamples.isNotEmpty)
      'input_examples': inputExamples.map((example) => example.toDart()).toList(),
  });
}

/// Caller-executed bash tool pinned to the 2025-01-24 schema.
final class AnthropicBashTool extends AnthropicNativeTool {
  /// Creates a bash definition.
  AnthropicBashTool({
    Iterable<JsonObject> inputExamples = const [],
    super.allowedCallers,
    super.cacheControl,
    super.deferLoading,
    super.strict,
    super.extensions,
  }) : inputExamples = List.unmodifiable(inputExamples),
       super(
         name: 'bash',
         type: discriminator,
         executionOwner: ToolExecutionOwner.caller,
         reservedFields: _inputExampleFields,
       );

  /// Versioned discriminator from the pinned Messages schema.
  static const discriminator = 'bash_20250124';

  /// Example native action inputs shown to the model.
  final List<JsonObject> inputExamples;

  @override
  JsonObject toJson() => _toJson({
    if (inputExamples.isNotEmpty)
      'input_examples': inputExamples.map((example) => example.toDart()).toList(),
  });
}

/// Caller-executed text editor pinned to the 2025-07-28 schema.
final class AnthropicTextEditorTool extends AnthropicNativeTool {
  /// Creates a text-editor definition.
  AnthropicTextEditorTool({
    this.maxCharacters,
    Iterable<JsonObject> inputExamples = const [],
    super.allowedCallers,
    super.cacheControl,
    super.deferLoading,
    super.strict,
    super.extensions,
  }) : inputExamples = List.unmodifiable(inputExamples),
       super(
         name: 'str_replace_based_edit_tool',
         type: discriminator,
         executionOwner: ToolExecutionOwner.caller,
         reservedFields: _textEditorFields,
       ) {
    _validateNonNegative(maxCharacters, 'maxCharacters');
  }

  /// Versioned discriminator from the pinned Messages schema.
  static const discriminator = 'text_editor_20250728';

  /// Maximum characters returned when viewing a file.
  final int? maxCharacters;

  /// Example native action inputs shown to the model.
  final List<JsonObject> inputExamples;

  @override
  JsonObject toJson() => _toJson({
    if (inputExamples.isNotEmpty)
      'input_examples': inputExamples.map((example) => example.toDart()).toList(),
    'max_characters': ?maxCharacters,
  });
}

/// Caller-executed memory tool pinned to the 2025-08-18 schema.
final class AnthropicMemoryTool extends AnthropicNativeTool {
  /// Creates a memory definition.
  AnthropicMemoryTool({
    Iterable<JsonObject> inputExamples = const [],
    super.allowedCallers,
    super.cacheControl,
    super.deferLoading,
    super.strict,
    super.extensions,
  }) : inputExamples = List.unmodifiable(inputExamples),
       super(
         name: 'memory',
         type: discriminator,
         executionOwner: ToolExecutionOwner.caller,
         reservedFields: _inputExampleFields,
       );

  /// Versioned discriminator from the pinned Messages schema.
  static const discriminator = 'memory_20250818';

  /// Example native action inputs shown to the model.
  final List<JsonObject> inputExamples;

  @override
  JsonObject toJson() => _toJson({
    if (inputExamples.isNotEmpty)
      'input_examples': inputExamples.map((example) => example.toDart()).toList(),
  });
}

const Set<String> _commonToolFields = {
  'name',
  'type',
  'allowed_callers',
  'cache_control',
  'defer_loading',
  'strict',
};

const Set<String> _webSearchFields = {
  'allowed_domains',
  'blocked_domains',
  'max_uses',
  'response_inclusion',
  'user_location',
};

const Set<String> _webFetchFields = {
  'allowed_domains',
  'blocked_domains',
  'citations',
  'max_content_tokens',
  'max_uses',
  'response_inclusion',
  'use_cache',
};

const Set<String> _inputExampleFields = {'input_examples'};

const Set<String> _computerFields = {
  ..._inputExampleFields,
  'display_width_px',
  'display_height_px',
  'display_number',
  'enable_zoom',
};

const Set<String> _textEditorFields = {..._inputExampleFields, 'max_characters'};

void _validatePositive(int? value, String name) {
  if (value != null && value <= 0) {
    throw ArgumentError.value(value, name, 'must be positive');
  }
}

void _validateNonNegative(int? value, String name) {
  if (value != null && value < 0) {
    throw ArgumentError.value(value, name, 'must not be negative');
  }
}

void _validateDomains(Iterable<String> domains, String name) {
  for (final domain in domains) {
    if (domain.isEmpty ||
        domain.trim() != domain ||
        domain.contains('://') ||
        domain.contains('/') ||
        domain.contains('?') ||
        domain.contains('#')) {
      throw ArgumentError.value(
        domain,
        name,
        'must contain a domain without a URL scheme, path, query, or fragment',
      );
    }
  }
}
