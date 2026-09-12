import 'package:artificer_core/json.dart';

/// A typed Responses input item.
sealed class XaiResponseInputItem {
  const XaiResponseInputItem();

  /// Encodes the item for the Responses API.
  Map<String, Object?> toDart();
}

/// An exact native item replayed from a previous response.
final class XaiRawResponseInputItem extends XaiResponseInputItem {
  /// Creates a lossless replay item.
  const XaiRawResponseInputItem(this.raw);

  /// Complete native input item.
  final JsonObject raw;

  @override
  Map<String, Object?> toDart() => raw.toDart();
}

/// A result for an application function call.
final class XaiFunctionCallOutputItem extends XaiResponseInputItem {
  /// Creates a function result item.
  XaiFunctionCallOutputItem({required String callId, required this.output})
    : callId = _nonEmpty(callId, 'callId');

  /// Native call ID.
  final String callId;

  /// Serialized result accepted by Responses.
  final String output;

  @override
  Map<String, Object?> toDart() => {
    'type': 'function_call_output',
    'call_id': callId,
    'output': output,
  };
}

/// A Responses input message.
final class XaiResponseInputMessage extends XaiResponseInputItem {
  /// Creates an input message.
  XaiResponseInputMessage({
    required this.role,
    required Iterable<XaiResponseInputPart> content,
  }) : content = List.unmodifiable(content) {
    if (this.content.isEmpty) throw ArgumentError.value(content, 'content', 'must not be empty');
  }

  /// Creates a user message containing one text part.
  XaiResponseInputMessage.userText(String text)
    : this(role: XaiResponseInputRole.user, content: [XaiTextInputPart(text)]);

  /// The native message role.
  final XaiResponseInputRole role;

  /// The ordered content.
  final List<XaiResponseInputPart> content;

  @override
  Map<String, Object?> toDart() => {
    'role': role.name,
    'content': content.map((part) => part.toDart()).toList(),
  };
}

/// A native Responses input-message role.
enum XaiResponseInputRole {
  /// A caller message.
  user,

  /// A prior model message.
  assistant,

  /// Developer instructions.
  developer,

  /// System instructions.
  system,
}

/// One typed native input part.
sealed class XaiResponseInputPart {
  const XaiResponseInputPart();

  /// Encodes the part.
  Map<String, Object?> toDart();
}

/// A native text input part.
final class XaiTextInputPart extends XaiResponseInputPart {
  /// Creates a text part.
  XaiTextInputPart(this.text) {
    if (text.isEmpty) throw ArgumentError.value(text, 'text', 'must not be empty');
  }

  /// The input text.
  final String text;

  @override
  Map<String, Object?> toDart() => {'type': 'input_text', 'text': text};
}

/// An image supplied by URL, data URL, or provider file ID.
final class XaiImageInputPart extends XaiResponseInputPart {
  /// Creates an image input with exactly one native source.
  XaiImageInputPart({this.imageUrl, this.fileId}) {
    if ((imageUrl == null) == (fileId == null)) {
      throw ArgumentError('Exactly one image source is required.');
    }
  }

  /// HTTP(S) or data URL.
  final String? imageUrl;

  /// Xai file ID.
  final String? fileId;

  @override
  Map<String, Object?> toDart() => {
    'type': 'input_image',
    'image_url': ?imageUrl,
    'file_id': ?fileId,
  };
}

/// A document supplied through an Xai file ID.
final class XaiFileInputPart extends XaiResponseInputPart {
  /// Creates a file input.
  XaiFileInputPart(String fileId) : fileId = _nonEmpty(fileId, 'fileId');

  /// Xai file ID.
  final String fileId;

  @override
  Map<String, Object?> toDart() => {'type': 'input_file', 'file_id': fileId};
}

/// A typed provider tool definition for Responses.
sealed class XaiToolDefinition {
  const XaiToolDefinition();

  /// Native type discriminator.
  String get type;

  /// Optional namespace used to reject collisions with application functions.
  String? get name => null;

  /// Encodes the native tool.
  Map<String, Object?> toDart();
}

/// An application function declaration.
final class XaiFunctionTool extends XaiToolDefinition {
  /// Creates a strict function tool.
  XaiFunctionTool({
    required String functionName,
    required this.parameters,
    this.description,
    this.strict = true,
  }) : functionName = _nonEmpty(functionName, 'functionName');

  /// Function name.
  final String functionName;

  /// Function description.
  final String? description;

  /// JSON Schema parameters.
  final JsonObject parameters;

  /// Whether the provider should enforce strict schema output.
  final bool strict;

  @override
  String get type => 'function';

  @override
  String get name => functionName;

  @override
  Map<String, Object?> toDart() => {
    'type': type,
    'name': functionName,
    'description': ?description,
    'parameters': parameters.toDart(),
    'strict': strict,
  };
}

/// Provider-hosted web search.
final class XaiWebSearchTool extends XaiToolDefinition {
  /// Creates a web-search tool.
  XaiWebSearchTool({
    Iterable<String>? allowedDomains,
    Iterable<String>? excludedDomains,
    this.enableImageSearch,
    this.enableImageUnderstanding,
  }) : allowedDomains = _limitedStrings(allowedDomains, 'allowedDomains', 5),
       excludedDomains = _limitedStrings(excludedDomains, 'excludedDomains', 5) {
    if (this.allowedDomains != null && this.excludedDomains != null) {
      throw ArgumentError('allowedDomains and excludedDomains cannot both be set');
    }
  }

  /// Domains xAI may use.
  final List<String>? allowedDomains;

  /// Domains xAI must exclude.
  final List<String>? excludedDomains;

  /// Whether image results may be searched.
  final bool? enableImageSearch;

  /// Whether image understanding is enabled during search.
  final bool? enableImageUnderstanding;

  @override
  String get type => 'web_search';

  @override
  Map<String, Object?> toDart() => {
    'type': type,
    'allowed_domains': ?allowedDomains,
    'excluded_domains': ?excludedDomains,
    'enable_image_search': ?enableImageSearch,
    'enable_image_understanding': ?enableImageUnderstanding,
  };
}

/// Provider-hosted search over X posts.
final class XaiXSearchTool extends XaiToolDefinition {
  /// Creates an X-search tool.
  XaiXSearchTool({
    Iterable<String>? allowedHandles,
    Iterable<String>? excludedHandles,
    this.fromDate,
    this.toDate,
    this.enableImageUnderstanding,
    this.enableVideoUnderstanding,
  }) : allowedHandles = _limitedStrings(allowedHandles, 'allowedHandles', 10),
       excludedHandles = _limitedStrings(excludedHandles, 'excludedHandles', 10) {
    if (this.allowedHandles != null && this.excludedHandles != null) {
      throw ArgumentError('allowedHandles and excludedHandles cannot both be set');
    }
  }

  /// X handles xAI may search.
  final List<String>? allowedHandles;

  /// X handles xAI must exclude.
  final List<String>? excludedHandles;

  /// Inclusive ISO-8601 start date.
  final String? fromDate;

  /// Inclusive ISO-8601 end date.
  final String? toDate;

  /// Whether image understanding is enabled.
  final bool? enableImageUnderstanding;

  /// Whether video understanding is enabled.
  final bool? enableVideoUnderstanding;

  @override
  String get type => 'x_search';

  @override
  Map<String, Object?> toDart() => {
    'type': type,
    'allowed_x_handles': ?allowedHandles,
    'excluded_x_handles': ?excludedHandles,
    'from_date': ?fromDate,
    'to_date': ?toDate,
    'enable_image_understanding': ?enableImageUnderstanding,
    'enable_video_understanding': ?enableVideoUnderstanding,
  };
}

/// Provider-hosted search over existing xAI collections.
final class XaiCollectionsSearchTool extends XaiToolDefinition {
  /// Creates collection search over [collectionIds].
  XaiCollectionsSearchTool({required Iterable<String> collectionIds, this.maxResults})
    : collectionIds = List.unmodifiable(collectionIds) {
    if (this.collectionIds.isEmpty ||
        this.collectionIds.length > 10 ||
        this.collectionIds.any((id) => id.isEmpty)) {
      throw ArgumentError.value(
        collectionIds,
        'collectionIds',
        'must contain between 1 and 10 nonempty IDs',
      );
    }
    if (maxResults != null && maxResults! < 1) {
      throw ArgumentError.value(maxResults, 'maxResults', 'must be positive');
    }
  }

  /// Existing xAI collection IDs.
  final List<String> collectionIds;

  /// Maximum number of results to return.
  final int? maxResults;

  @override
  String get type => 'file_search';

  @override
  Map<String, Object?> toDart() => {
    'type': type,
    'vector_store_ids': collectionIds,
    'max_num_results': ?maxResults,
  };
}

/// Provider-hosted code interpreter.
final class XaiCodeInterpreterTool extends XaiToolDefinition {
  /// Creates an xAI code-execution tool.
  const XaiCodeInterpreterTool();

  @override
  String get type => 'code_interpreter';

  @override
  Map<String, Object?> toDart() => {'type': type};
}

/// Provider-hosted remote MCP access.
final class XaiRemoteMcpTool extends XaiToolDefinition {
  /// Creates a remote MCP tool.
  XaiRemoteMcpTool({
    required String serverLabel,
    required this.serverUrl,
    this.serverDescription,
    this.authorization,
    Iterable<String>? allowedTools,
    Map<String, String>? headers,
    this.requireApproval,
    this.deferLoading,
  }) : serverLabel = _nonEmpty(serverLabel, 'serverLabel'),
       allowedTools = allowedTools == null ? null : List.unmodifiable(allowedTools),
       headers = headers == null ? null : Map.unmodifiable(headers) {
    if (!serverUrl.isAbsolute || serverUrl.scheme != 'https') {
      throw ArgumentError.value(serverUrl, 'serverUrl', 'must be an absolute HTTPS URL');
    }
  }

  /// Label shown to the model.
  final String serverLabel;

  /// Remote MCP server URL.
  final Uri serverUrl;

  /// Description exposed to the model.
  final String? serverDescription;

  /// Authorization value forwarded to the server.
  final String? authorization;

  /// Optional allowlist of remote tool names.
  final List<String>? allowedTools;

  /// Extra headers forwarded to the remote server.
  final Map<String, String>? headers;

  /// Native approval policy.
  final String? requireApproval;

  /// Whether tool definitions are loaded on demand.
  final bool? deferLoading;

  @override
  String get type => 'mcp';

  @override
  Map<String, Object?> toDart() => {
    'type': type,
    'server_label': serverLabel,
    'server_url': serverUrl.toString(),
    'server_description': ?serverDescription,
    'authorization': ?authorization,
    'allowed_tools': ?allowedTools,
    'headers': ?headers,
    'require_approval': ?requireApproval,
    'defer_loading': ?deferLoading,
  };
}

/// xAI-specific inference controls for Responses.
final class XaiInferenceOptions {
  /// Creates inference controls from the pinned xAI Responses schema.
  const XaiInferenceOptions({
    this.maxTurns,
    this.minP,
    this.topK,
    this.logprobs,
    this.topLogprobs,
    this.user,
  });

  /// Maximum number of agentic tool turns.
  final int? maxTurns;

  /// Minimum relative token probability.
  final double? minP;

  /// Maximum candidate-token count per sampling step.
  final int? topK;

  /// Whether token log probabilities are returned.
  final bool? logprobs;

  /// Number of alternative token log probabilities to return.
  final int? topLogprobs;

  /// Caller-defined End User identifier.
  final String? user;

  /// Encodes these controls using xAI field names.
  Map<String, Object?> toDart() => {
    'max_turns': ?maxTurns,
    'min_p': ?minP,
    'top_k': ?topK,
    'logprobs': ?logprobs,
    'top_logprobs': ?topLogprobs,
    'user': ?user,
  };
}

/// A typed native request for `POST /responses`.
final class XaiResponseRequest {
  /// Creates a Responses request.
  XaiResponseRequest({
    required String model,
    required Iterable<XaiResponseInputItem> input,
    this.instructions,
    this.maxOutputTokens,
    this.temperature,
    this.topP,
    this.store,
    this.stream,
    this.reasoning,
    this.promptCacheKey,
    this.serviceTier,
    this.inference,
    Iterable<String>? include,
    Iterable<XaiToolDefinition>? tools,
    this.toolChoice,
    this.text,
    Object? previousResponseId = _omitted,
    JsonObject? extraBody,
  }) : model = _nonEmpty(model, 'model'),
       input = List.unmodifiable(input),
       include = include == null ? null : List.unmodifiable(include),
       tools = tools == null ? null : List.unmodifiable(tools),
       _previousResponseId = _nullableStringValue(previousResponseId, 'previousResponseId'),
       _hasPreviousResponseId = !identical(previousResponseId, _omitted),
       extraBody = extraBody ?? JsonObject({}) {
    if (this.input.isEmpty) throw ArgumentError.value(input, 'input', 'must not be empty');
    if (maxOutputTokens != null && maxOutputTokens! <= 0) {
      throw ArgumentError.value(maxOutputTokens, 'maxOutputTokens', 'must be positive');
    }
    if (inference case final value?) {
      if (value.maxTurns != null && value.maxTurns! < 1) {
        throw ArgumentError.value(value.maxTurns, 'inference.maxTurns', 'must be positive');
      }
      if (value.minP != null && (value.minP! < 0 || value.minP! > 1)) {
        throw ArgumentError.value(value.minP, 'inference.minP', 'must be between 0 and 1');
      }
      if (value.topK != null && value.topK! < 1) {
        throw ArgumentError.value(value.topK, 'inference.topK', 'must be positive');
      }
      if (value.topLogprobs != null && (value.topLogprobs! < 0 || value.topLogprobs! > 8)) {
        throw ArgumentError.value(
          value.topLogprobs,
          'inference.topLogprobs',
          'must be between 0 and 8',
        );
      }
    }
    final collision = this.extraBody.toDart().keys.where(_typedResponseFields.contains).firstOrNull;
    if (collision != null) {
      throw ArgumentError.value(collision, 'extraBody', 'collides with a typed field');
    }
  }

  /// The provider-local model ID.
  final String model;

  /// The ordered explicit input history.
  final List<XaiResponseInputItem> input;

  /// Separate developer instructions.
  final String? instructions;

  /// The maximum output-token count.
  final int? maxOutputTokens;

  /// Sampling temperature when supplied.
  final double? temperature;

  /// Nucleus-sampling threshold when supplied.
  final double? topP;

  /// Whether the provider stores the response.
  final bool? store;

  /// Whether to stream the response.
  final bool? stream;

  /// Native reasoning configuration.
  final JsonObject? reasoning;

  /// Stable prompt-cache identifier.
  final String? promptCacheKey;

  /// Native service tier.
  final String? serviceTier;

  /// xAI-specific inference controls.
  final XaiInferenceOptions? inference;

  /// Additional native response fields requested by the caller.
  final List<String>? include;

  /// Native and application tool definitions.
  final List<XaiToolDefinition>? tools;

  /// Native tool selection value.
  final JsonValue? toolChoice;

  /// Native text-output configuration.
  final JsonObject? text;

  /// Explicit stored response to continue from in native calls.
  String? get previousResponseId => _previousResponseId;

  final String? _previousResponseId;
  final bool _hasPreviousResponseId;

  /// Forward-compatible fields outside this pinned typed snapshot.
  final JsonObject extraBody;

  /// Encodes this request and rejects collisions with typed fields.
  JsonObject toJson() {
    final extras = extraBody.toDart();
    return JsonObject({
      ...extras,
      'model': model,
      'input': input.map((item) => item.toDart()).toList(),
      'instructions': ?instructions,
      'max_output_tokens': ?maxOutputTokens,
      'temperature': ?temperature,
      'top_p': ?topP,
      'store': ?store,
      'stream': ?stream,
      if (reasoning case final value?) 'reasoning': value.toDart(),
      'prompt_cache_key': ?promptCacheKey,
      'service_tier': ?serviceTier,
      ...?inference?.toDart(),
      'include': ?include,
      if (tools case final value?) 'tools': value.map((tool) => tool.toDart()).toList(),
      if (toolChoice case final value?) 'tool_choice': value.toDart(),
      if (text case final value?) 'text': value.toDart(),
      if (_hasPreviousResponseId) 'previous_response_id': _previousResponseId,
    });
  }
}

/// Native response state.
enum XaiResponseStatus {
  /// Completed successfully.
  completed,

  /// Failed at the provider.
  failed,

  /// Still running.
  inProgress,

  /// Ended with partial output.
  incomplete,

  /// A newer native status.
  unknown,
}

/// A typed native Responses object with full raw and extension data.
final class XaiResponse {
  /// Decodes a Responses object.
  factory XaiResponse.fromJson(JsonObject raw) {
    final value = raw.toDart();
    return XaiResponse._(
      id: _string(value, 'id'),
      model: _string(value, 'model'),
      status: _status(_string(value, 'status')),
      output: _list(value, 'output').map(XaiResponseOutputItem.fromDart),
      usage: value['usage'] is Map<String, Object?>
          ? XaiResponseUsage.fromDart(value['usage'])
          : null,
      raw: raw,
      extensions: JsonObject(_without(value, {'id', 'model', 'status', 'output', 'usage'})),
    );
  }

  XaiResponse._({
    required this.id,
    required this.model,
    required this.status,
    required Iterable<XaiResponseOutputItem> output,
    required this.raw,
    required this.extensions,
    this.usage,
  }) : output = List.unmodifiable(output);

  /// Response ID.
  final String id;

  /// Actual model ID.
  final String model;

  /// Native lifecycle state.
  final XaiResponseStatus status;

  /// Ordered native output items.
  final List<XaiResponseOutputItem> output;

  /// Token accounting when returned.
  final XaiResponseUsage? usage;

  /// Complete native response.
  final JsonObject raw;

  /// Fields outside the typed snapshot.
  final JsonObject extensions;
}

/// One typed output item.
sealed class XaiResponseOutputItem {
  XaiResponseOutputItem({
    required this.type,
    required this.raw,
    required this.extensions,
    this.id,
  });

  /// Decodes a native output item.
  factory XaiResponseOutputItem.fromDart(Object? input) {
    final value = _object(input, 'output item');
    final raw = JsonObject(value);
    final type = _string(value, 'type');
    return switch (type) {
      'message' => XaiResponseMessageItem._(
        id: _optionalString(value, 'id'),
        status: _optionalString(value, 'status'),
        content: _list(value, 'content').map(XaiResponseOutputContent.fromDart),
        raw: raw,
        extensions: JsonObject(_without(value, {'type', 'id', 'status', 'role', 'content'})),
      ),
      'reasoning' => XaiReasoningOutputItem._(
        id: _optionalString(value, 'id'),
        status: _optionalString(value, 'status'),
        summaries: _optionalList(
          value,
          'summary',
        ).map((summary) => _string(_object(summary, 'reasoning summary'), 'text')),
        raw: raw,
        extensions: JsonObject(_without(value, {'type', 'id', 'status', 'summary'})),
      ),
      'function_call' || 'custom_tool_call' => XaiCallerToolOutputItem._(
        type: type,
        id: _optionalString(value, 'id'),
        callId: _string(value, 'call_id'),
        name: _string(value, 'name'),
        input: type == 'function_call' ? _string(value, 'arguments') : _string(value, 'input'),
        status: _optionalString(value, 'status'),
        raw: raw,
        extensions: JsonObject(
          _without(value, {'type', 'id', 'call_id', 'name', 'arguments', 'input', 'status'}),
        ),
      ),
      'web_search_call' ||
      'x_search_call' ||
      'file_search_call' ||
      'code_interpreter_call' ||
      'mcp_call' ||
      'mcp_list_tools' ||
      'tool_search_call' => XaiProviderToolOutputItem._(
        type: type,
        id: _optionalString(value, 'id'),
        status: _optionalString(value, 'status'),
        raw: raw,
        extensions: JsonObject(_without(value, {'type', 'id', 'status'})),
      ),
      _ => XaiUnknownOutputItem._(
        type: type,
        id: _optionalString(value, 'id'),
        raw: raw,
        extensions: JsonObject(_without(value, {'type', 'id'})),
      ),
    };
  }

  /// Native item type.
  final String type;

  /// Native item ID.
  final String? id;

  /// Complete native item.
  final JsonObject raw;

  /// Unknown fields on the item.
  final JsonObject extensions;
}

/// A native reasoning item with public summaries and opaque replay data.
final class XaiReasoningOutputItem extends XaiResponseOutputItem {
  XaiReasoningOutputItem._({
    required super.id,
    required this.status,
    required Iterable<String> summaries,
    required super.raw,
    required super.extensions,
  }) : summaries = List.unmodifiable(summaries),
       super(type: 'reasoning');

  /// Native item status.
  final String? status;

  /// Provider-supplied reasoning summaries.
  final List<String> summaries;
}

/// A function, custom, computer, shell, or patch call owned by the caller.
final class XaiCallerToolOutputItem extends XaiResponseOutputItem {
  XaiCallerToolOutputItem._({
    required super.type,
    required super.id,
    required this.callId,
    required this.name,
    required this.input,
    required this.status,
    required super.raw,
    required super.extensions,
  });

  /// Stable call ID referenced by the result.
  final String callId;

  /// Tool name.
  final String name;

  /// Native arguments or input text.
  final String input;

  /// Native item status.
  final String? status;
}

/// A provider-hosted tool record that callers never execute.
final class XaiProviderToolOutputItem extends XaiResponseOutputItem {
  XaiProviderToolOutputItem._({
    required super.type,
    required super.id,
    required this.status,
    required super.raw,
    required super.extensions,
  });

  /// Native item status.
  final String? status;
}

/// A native assistant message item.
final class XaiResponseMessageItem extends XaiResponseOutputItem {
  XaiResponseMessageItem._({
    required super.id,
    required this.status,
    required Iterable<XaiResponseOutputContent> content,
    required super.raw,
    required super.extensions,
  }) : content = List.unmodifiable(content),
       super(type: 'message');

  /// Native completion state.
  final String? status;

  /// Ordered native output content.
  final List<XaiResponseOutputContent> content;
}

/// An unknown output item retained without loss.
final class XaiUnknownOutputItem extends XaiResponseOutputItem {
  XaiUnknownOutputItem._({
    required super.type,
    required super.id,
    required super.raw,
    required super.extensions,
  });
}

/// One typed message content part.
sealed class XaiResponseOutputContent {
  XaiResponseOutputContent({required this.type, required this.raw, required this.extensions});

  /// Decodes one native content part.
  factory XaiResponseOutputContent.fromDart(Object? input) {
    final value = _object(input, 'output content');
    final raw = JsonObject(value);
    final type = _string(value, 'type');
    return switch (type) {
      'output_text' => XaiOutputTextContent._(
        text: _string(value, 'text'),
        raw: raw,
        extensions: JsonObject(_without(value, {'type', 'text'})),
      ),
      'refusal' => XaiRefusalContent._(
        refusal: _string(value, 'refusal'),
        raw: raw,
        extensions: JsonObject(_without(value, {'type', 'refusal'})),
      ),
      _ => XaiUnknownOutputContent._(
        type: type,
        raw: raw,
        extensions: JsonObject(_without(value, {'type'})),
      ),
    };
  }

  /// Native part type.
  final String type;

  /// Complete native part.
  final JsonObject raw;

  /// Unknown fields on the part.
  final JsonObject extensions;
}

/// Native visible text.
final class XaiOutputTextContent extends XaiResponseOutputContent {
  XaiOutputTextContent._({
    required this.text,
    required super.raw,
    required super.extensions,
  }) : super(type: 'output_text');

  /// Visible text.
  final String text;
}

/// Native refusal content.
final class XaiRefusalContent extends XaiResponseOutputContent {
  XaiRefusalContent._({
    required this.refusal,
    required super.raw,
    required super.extensions,
  }) : super(type: 'refusal');

  /// Refusal text.
  final String refusal;
}

/// Unknown content retained without loss.
final class XaiUnknownOutputContent extends XaiResponseOutputContent {
  XaiUnknownOutputContent._({
    required super.type,
    required super.raw,
    required super.extensions,
  });
}

/// Native Responses token accounting.
final class XaiResponseUsage {
  /// Decodes usage.
  factory XaiResponseUsage.fromDart(Object? input) {
    final value = _object(input, 'usage');
    return XaiResponseUsage._(
      inputTokens: _optionalInt(value, 'input_tokens'),
      outputTokens: _optionalInt(value, 'output_tokens'),
      totalTokens: _optionalInt(value, 'total_tokens'),
      raw: JsonObject(value),
    );
  }

  XaiResponseUsage._({
    required this.inputTokens,
    required this.outputTokens,
    required this.totalTokens,
    required this.raw,
  });

  /// Input tokens.
  final int? inputTokens;

  /// Output tokens.
  final int? outputTokens;

  /// Total tokens.
  final int? totalTokens;

  /// Complete usage object.
  final JsonObject raw;
}

const _omitted = Object();

String? _nullableStringValue(Object? value, String name) {
  if (identical(value, _omitted) || value == null) return null;
  if (value is! String || value.isEmpty) {
    throw ArgumentError.value(value, name, 'must be a nonempty string or null');
  }
  return value;
}

String _nonEmpty(String value, String name) {
  if (value.isEmpty) throw ArgumentError.value(value, name, 'must not be empty');
  return value;
}

Map<String, Object?> _object(Object? value, String name) {
  if (value is! Map<String, Object?>) throw FormatException('$name must be an object.');
  return value;
}

List<Object?> _list(Map<String, Object?> value, String key) {
  final field = value[key];
  if (field is! List<Object?>) throw FormatException('$key must be an array.');
  return field;
}

List<Object?> _optionalList(Map<String, Object?> value, String key) {
  final field = value[key];
  if (field == null) return const [];
  if (field is! List<Object?>) throw FormatException('$key must be an array.');
  return field;
}

String _string(Map<String, Object?> value, String key) {
  final field = value[key];
  if (field is! String) throw FormatException('$key must be a string.');
  return field;
}

String? _optionalString(Map<String, Object?> value, String key) {
  final field = value[key];
  if (field == null) return null;
  if (field is! String) throw FormatException('$key must be a string.');
  return field;
}

int? _optionalInt(Map<String, Object?> value, String key) {
  final field = value[key];
  if (field == null) return null;
  if (field is! int) throw FormatException('$key must be an integer.');
  return field;
}

List<String>? _limitedStrings(Iterable<String>? values, String name, int maximum) {
  if (values == null) return null;
  final frozen = List<String>.unmodifiable(values);
  if (frozen.isEmpty || frozen.length > maximum || frozen.any((value) => value.isEmpty)) {
    throw ArgumentError.value(
      values,
      name,
      'must contain between 1 and $maximum nonempty values',
    );
  }
  return frozen;
}

Map<String, Object?> _without(Map<String, Object?> value, Set<String> keys) =>
    Map.fromEntries(value.entries.where((entry) => !keys.contains(entry.key)));

XaiResponseStatus _status(String status) => switch (status) {
  'completed' => XaiResponseStatus.completed,
  'failed' => XaiResponseStatus.failed,
  'in_progress' => XaiResponseStatus.inProgress,
  'incomplete' => XaiResponseStatus.incomplete,
  _ => XaiResponseStatus.unknown,
};

const _typedResponseFields = {
  'model',
  'input',
  'instructions',
  'max_output_tokens',
  'temperature',
  'top_p',
  'store',
  'stream',
  'reasoning',
  'prompt_cache_key',
  'service_tier',
  'max_turns',
  'min_p',
  'top_k',
  'logprobs',
  'top_logprobs',
  'user',
  'include',
  'tools',
  'tool_choice',
  'text',
  'previous_response_id',
};
