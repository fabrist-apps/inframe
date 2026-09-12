import 'package:artificer_core/artificer_core.dart';
import 'package:artificer_core/json.dart';
import 'package:artificer_google/src/generate_content/generate_content_models.dart';

/// Lifecycle state returned by the stable Google Interactions v1 API.
enum GoogleInteractionStatus {
  /// Interaction work is still running.
  inProgress,

  /// The caller must provide a tool result or other input.
  requiresAction,

  /// The interaction completed successfully.
  completed,

  /// The provider recorded a failure on the interaction.
  failed,

  /// The interaction was cancelled.
  cancelled,

  /// The interaction ended with incomplete results.
  incomplete,

  /// A newer status retained through [GoogleInteraction.nativeStatus].
  unknown,
}

/// Typed model-inference request for `POST /v1/interactions`.
final class GoogleInteractionRequest {
  /// Creates this typed native value.
  GoogleInteractionRequest({
    required String model,
    required this.input,
    this.background,
    this.generationConfig,
    Map<String, String>? labels,
    this.previousInteractionId,
    Iterable<GoogleInteractionResponseFormat>? responseFormats,
    this.responseMimeType,
    Iterable<GoogleSafetySetting>? safetySettings,
    this.store,
    this.stream,
    this.systemInstruction,
    Iterable<GoogleInteractionTool>? tools,
    JsonObject? extraBody,
  }) : model = _nonEmpty(model, 'model'),
       labels = labels == null ? null : Map.unmodifiable(labels),
       responseFormats = responseFormats == null ? null : List.unmodifiable(responseFormats),
       safetySettings = safetySettings == null ? null : List.unmodifiable(safetySettings),
       tools = tools == null ? null : List.unmodifiable(tools),
       extraBody = extraBody ?? JsonObject({}) {
    _rejectCollisions(this.extraBody, _requestFields);
    if (previousInteractionId != null && previousInteractionId!.isEmpty) {
      throw ArgumentError.value(
        previousInteractionId,
        'previousInteractionId',
        'must not be empty',
      );
    }
    if (this.responseFormats?.isEmpty ?? false) {
      throw ArgumentError.value(responseFormats, 'responseFormats', 'must not be empty');
    }
    if (this.tools?.isEmpty ?? false) {
      throw ArgumentError.value(tools, 'tools', 'must not be empty');
    }
  }

  /// Native model string. The pinned schema and examples disagree on prefixing,
  /// so the SDK preserves the caller's nonempty value exactly.
  final String model;

  /// The model input for this interaction.
  final GoogleInteractionInput input;

  /// Whether the provider should run the interaction in the background.
  final bool? background;

  /// The generation config.
  final GoogleInteractionGenerationConfig? generationConfig;

  /// Caller-defined labels attached to the interaction.
  final Map<String, String>? labels;

  /// The explicit prior interaction to continue, when supplied.
  final String? previousInteractionId;

  /// Accepted response formats, as one object or an array on the wire.
  final List<GoogleInteractionResponseFormat>? responseFormats;

  /// The deprecated response MIME type accepted by stable v1.
  final String? responseMimeType;

  /// Safety rules for this interaction.
  final List<GoogleSafetySetting>? safetySettings;

  /// Whether the provider should retain the interaction for retrieval.
  final bool? store;

  /// Whether the request asks for an SSE response.
  final bool? stream;

  /// The system instruction for this interaction.
  final String? systemInstruction;

  /// Native tools available to the model.
  final List<GoogleInteractionTool>? tools;

  /// Forward-compatible request fields outside the typed snapshot.
  final JsonObject extraBody;

  /// Encodes this value as native JSON.
  JsonObject toJson({bool? stream}) {
    final formats = responseFormats;
    return JsonObject({
      ...extraBody.toDart(),
      'model': model,
      'input': input.toDart(),
      'background': ?background,
      if (generationConfig case final value?) 'generation_config': value.toJson().toDart(),
      'labels': ?labels,
      'previous_interaction_id': ?previousInteractionId,
      if (formats case final values?)
        'response_format': values.length == 1
            ? values.single.toJson().toDart()
            : values.map((value) => value.toJson().toDart()).toList(),
      'response_mime_type': ?responseMimeType,
      if (safetySettings case final values?)
        'safety_settings': values.map((value) => value.toJson().toDart()).toList(),
      'store': ?store,
      'stream': ?(stream ?? this.stream),
      'system_instruction': ?systemInstruction,
      if (tools case final values?)
        'tools': values.map((value) => value.toJson().toDart()).toList(),
    });
  }
}

/// Stable-v1 generation settings for one interaction.
final class GoogleInteractionGenerationConfig {
  /// Creates this typed native value.
  GoogleInteractionGenerationConfig({
    this.maxOutputTokens,
    this.seed,
    Iterable<String>? stopSequences,
    this.thinkingLevel,
    this.thinkingSummaries,
    this.toolChoice,
    this.speechConfig,
    JsonObject? extensions,
  }) : stopSequences = stopSequences == null ? null : List.unmodifiable(stopSequences),
       extensions = extensions ?? JsonObject({}) {
    if (maxOutputTokens != null && maxOutputTokens! <= 0) {
      throw ArgumentError.value(maxOutputTokens, 'maxOutputTokens', 'must be positive');
    }
    _rejectCollisions(this.extensions, _generationConfigFields);
  }

  /// The max output tokens.
  final int? maxOutputTokens;

  /// The seed.
  final int? seed;

  /// The stop sequences.
  final List<String>? stopSequences;

  /// The thinking level.
  final String? thinkingLevel;

  /// The thinking summaries.
  final String? thinkingSummaries;

  /// The tool choice.
  final JsonValue? toolChoice;

  /// Retained JSON because the pinned OpenAPI references missing speech schemas.
  final JsonValue? speechConfig;

  /// Fields outside the typed snapshot.
  final JsonObject extensions;

  /// Encodes this value as native JSON.
  JsonObject toJson() => JsonObject({
    ...extensions.toDart(),
    'max_output_tokens': ?maxOutputTokens,
    'seed': ?seed,
    'stop_sequences': ?stopSequences,
    'thinking_level': ?thinkingLevel,
    'thinking_summaries': ?thinkingSummaries,
    if (toolChoice case final value?) 'tool_choice': value.toDart(),
    if (speechConfig case final value?) 'speech_config': value.toDart(),
  });
}

/// One response format in the stable Interactions schema.
final class GoogleInteractionResponseFormat {
  /// Creates this typed native value.
  GoogleInteractionResponseFormat({
    required String type,
    this.aspectRatio,
    this.bitRate,
    this.delivery,
    this.duration,
    this.imageSize,
    this.mimeType,
    this.resolution,
    this.sampleRate,
    this.schema,
    JsonObject? extensions,
  }) : type = _nonEmpty(type, 'type'),
       extensions = extensions ?? JsonObject({}) {
    _rejectCollisions(this.extensions, _responseFormatFields);
  }

  /// The native union discriminator.
  final String type;

  /// Requested image or video aspect ratio.
  final String? aspectRatio;

  /// Requested compressed-audio bit rate.
  final int? bitRate;

  /// Whether generated media is returned inline or by URI.
  final String? delivery;

  /// Requested generated-video duration.
  final String? duration;

  /// Requested generated-image size.
  final String? imageSize;

  /// The mime type.
  final String? mimeType;

  /// Requested media resolution.
  final String? resolution;

  /// Requested audio sample rate.
  final int? sampleRate;

  /// The schema.
  final JsonObject? schema;

  /// Fields outside the typed snapshot.
  final JsonObject extensions;

  /// Encodes this value as native JSON.
  JsonObject toJson() => JsonObject({
    ...extensions.toDart(),
    'type': type,
    'aspect_ratio': ?aspectRatio,
    'bit_rate': ?bitRate,
    'delivery': ?delivery,
    'duration': ?duration,
    'image_size': ?imageSize,
    'mime_type': ?mimeType,
    'resolution': ?resolution,
    'sample_rate': ?sampleRate,
    if (schema case final value?) 'schema': value.toDart(),
  });
}

/// The request input union accepted by Interactions v1.
sealed class GoogleInteractionInput {
  const GoogleInteractionInput();

  factory GoogleInteractionInput.text(String text) = GoogleInteractionTextInput;
  factory GoogleInteractionInput.content(GoogleInteractionContent content) =
      GoogleInteractionContentInput;
  factory GoogleInteractionInput.contents(Iterable<GoogleInteractionContent> contents) =
      GoogleInteractionContentListInput;
  factory GoogleInteractionInput.steps(Iterable<GoogleInteractionStep> steps) =
      GoogleInteractionStepListInput;
  factory GoogleInteractionInput.raw(JsonValue value) = GoogleUnknownInteractionInput;

  factory GoogleInteractionInput.fromDart(Object? input) {
    if (input is String) return GoogleInteractionTextInput(input);
    if (input is Map<String, Object?>) {
      return GoogleInteractionContentInput(
        GoogleInteractionContent.fromJson(JsonObject(input)),
      );
    }
    if (input is! List<Object?> || input.isEmpty) {
      return GoogleUnknownInteractionInput(JsonValue.fromDart(input));
    }
    if (input.every((item) => item is Map<String, Object?> && _stepTypes.contains(item['type']))) {
      return GoogleInteractionStepListInput(
        input.map((item) => GoogleInteractionStep.fromJson(_objectJson(item, 'input step'))),
      );
    }
    if (input.every(
      (item) => item is Map<String, Object?> && _contentTypes.contains(item['type']),
    )) {
      return GoogleInteractionContentListInput(
        input.map(
          (item) => GoogleInteractionContent.fromJson(_objectJson(item, 'input content')),
        ),
      );
    }
    return GoogleUnknownInteractionInput(JsonValue.fromDart(input));
  }

  /// Encodes this union value in its native JSON shape.
  Object? toDart();
}

/// The typed native value.
final class GoogleInteractionTextInput extends GoogleInteractionInput {
  /// Creates this typed native value.
  GoogleInteractionTextInput(String text) : text = _nonEmpty(text, 'text');

  /// The text.
  final String text;
  @override
  String toDart() => text;
}

/// The typed native value.
final class GoogleInteractionContentInput extends GoogleInteractionInput {
  /// Creates this typed native value.
  const GoogleInteractionContentInput(this.content);

  /// Ordered native content parts.
  final GoogleInteractionContent content;
  @override
  Map<String, Object?> toDart() => content.toJson().toDart();
}

/// The typed native value.
final class GoogleInteractionContentListInput extends GoogleInteractionInput {
  /// Creates this typed native value.
  GoogleInteractionContentListInput(Iterable<GoogleInteractionContent> contents)
    : contents = List.unmodifiable(contents) {
    if (this.contents.isEmpty) {
      throw ArgumentError.value(contents, 'contents', 'must not be empty');
    }
  }

  /// The contents.
  final List<GoogleInteractionContent> contents;
  @override
  List<Object?> toDart() => contents.map((value) => value.toJson().toDart()).toList();
}

/// The typed native value.
final class GoogleInteractionStepListInput extends GoogleInteractionInput {
  /// Creates this typed native value.
  GoogleInteractionStepListInput(Iterable<GoogleInteractionStep> steps)
    : steps = List.unmodifiable(steps) {
    if (this.steps.isEmpty) throw ArgumentError.value(steps, 'steps', 'must not be empty');
  }

  /// Ordered interaction steps, when returned.
  final List<GoogleInteractionStep> steps;
  @override
  List<Object?> toDart() => steps.map((value) => value.toJson().toDart()).toList();
}

/// The typed native value.
final class GoogleUnknownInteractionInput extends GoogleInteractionInput {
  /// Creates this typed native value.
  const GoogleUnknownInteractionInput(this.value);

  /// The value.
  final JsonValue value;
  @override
  Object? toDart() => value.toDart();
}

/// Text, image, audio, or document content in the Interactions dialect.
final class GoogleInteractionContent {
  GoogleInteractionContent._({
    required this.type,
    required this.text,
    required this.channels,
    required this.data,
    required this.uri,
    required this.mimeType,
    required this.resolution,
    required this.sampleRate,
    required this.annotations,
    required this.raw,
    required this.extensions,
  });

  /// Creates this typed native value.
  factory GoogleInteractionContent.text(String text, {JsonObject? extensions}) =>
      GoogleInteractionContent.fromJson(
        _typedJson(extensions, _contentFields, {
          'type': 'text',
          'text': _nonEmpty(text, 'text'),
        }),
      );

  /// Creates this typed native value.
  factory GoogleInteractionContent.media({
    required String type,
    int? channels,
    String? data,
    String? uri,
    String? mimeType,
    String? resolution,
    int? sampleRate,
    JsonObject? extensions,
  }) {
    if (!_mediaContentTypes.contains(type)) {
      throw ArgumentError.value(type, 'type', 'must be image, audio, or document');
    }
    return GoogleInteractionContent.fromJson(
      _typedJson(extensions, _contentFields, {
        'type': type,
        'channels': ?channels,
        'data': ?data,
        'uri': ?uri,
        'mime_type': ?mimeType,
        'resolution': ?resolution,
        'sample_rate': ?sampleRate,
      }),
    );
  }

  /// Decodes native JSON while retaining unknown fields.
  factory GoogleInteractionContent.fromJson(JsonObject raw) {
    final value = raw.toDart();
    final type = _string(value, 'type');
    final annotations = switch (value['annotations']) {
      null => const <GoogleInteractionAnnotation>[],
      final List<Object?> values =>
        values
            .map(
              (item) => GoogleInteractionAnnotation.fromJson(
                _objectJson(item, 'content annotation'),
              ),
            )
            .toList(growable: false),
      _ => throw const FormatException('content.annotations must be an array.'),
    };
    return GoogleInteractionContent._(
      type: type,
      text: _optionalString(value, 'text'),
      channels: _optionalInt(value, 'channels'),
      data: _optionalString(value, 'data'),
      uri: _optionalString(value, 'uri'),
      mimeType: _optionalString(value, 'mime_type'),
      resolution: _optionalString(value, 'resolution'),
      sampleRate: _optionalInt(value, 'sample_rate'),
      annotations: List.unmodifiable(annotations),
      raw: raw,
      extensions: JsonObject(
        _without(value, _contentFields),
      ),
    );
  }

  /// The native union discriminator.
  final String type;

  /// The text.
  final String? text;

  /// Number of channels in audio content.
  final int? channels;

  /// The data.
  final String? data;

  /// The uri.
  final String? uri;

  /// The mime type.
  final String? mimeType;

  /// Requested media resolution, when present.
  final String? resolution;

  /// Audio sample rate in hertz, when present.
  final int? sampleRate;

  /// The annotations.
  final List<GoogleInteractionAnnotation> annotations;

  /// The complete native JSON object.
  final JsonObject raw;

  /// Fields outside the typed snapshot.
  final JsonObject extensions;

  /// Encodes this value as native JSON.
  JsonObject toJson() => raw;
}

/// A citation annotation retained with its typed discriminator and raw fields.
final class GoogleInteractionAnnotation {
  GoogleInteractionAnnotation._(this.type, this.raw, this.extensions);

  /// Decodes native JSON while retaining unknown fields.
  factory GoogleInteractionAnnotation.fromJson(JsonObject raw) {
    final value = raw.toDart();
    return GoogleInteractionAnnotation._(
      _string(value, 'type'),
      raw,
      JsonObject(_without(value, {'type'})),
    );
  }

  /// The native union discriminator.
  final String type;

  /// The complete native JSON object.
  final JsonObject raw;

  /// Fields outside the typed snapshot.
  final JsonObject extensions;

  /// Encodes this value as native JSON.
  JsonObject toJson() => raw;
}

/// Tool declaration with explicit caller/provider execution ownership.
sealed class GoogleInteractionTool {
  GoogleInteractionTool._(_DecodedInteractionTool value)
    : type = value.type,
      owner = value.owner,
      name = value.name,
      description = value.description,
      parameters = value.parameters,
      fileSearchStoreNames = value.fileSearchStoreNames,
      metadataFilter = value.metadataFilter,
      topK = value.topK,
      enableWidget = value.enableWidget,
      latitude = value.latitude,
      longitude = value.longitude,
      searchTypes = value.searchTypes,
      raw = value.raw,
      extensions = value.extensions;

  factory GoogleInteractionTool.function({
    required String name,
    JsonObject? parameters,
    String? description,
    JsonObject? extensions,
  }) => GoogleInteractionTool.fromJson(
    _typedJson(extensions, _toolFields, {
      'type': 'function',
      'name': _nonEmpty(name, 'name'),
      'description': ?description,
      if (parameters case final value?) 'parameters': value.toDart(),
    }),
  );

  factory GoogleInteractionTool.codeExecution({JsonObject? extensions}) =>
      GoogleInteractionTool.fromJson(
        _typedJson(extensions, _toolFields, {'type': 'code_execution'}),
      );

  factory GoogleInteractionTool.fileSearch({
    Iterable<String>? storeNames,
    String? metadataFilter,
    int? topK,
    JsonObject? extensions,
  }) => GoogleInteractionTool.fromJson(
    _typedJson(extensions, _toolFields, {
      'type': 'file_search',
      'file_search_store_names': ?storeNames?.toList(),
      'metadata_filter': ?metadataFilter,
      'top_k': ?topK,
    }),
  );

  factory GoogleInteractionTool.googleMaps({
    bool? enableWidget,
    double? latitude,
    double? longitude,
    JsonObject? extensions,
  }) => GoogleInteractionTool.fromJson(
    _typedJson(extensions, _toolFields, {
      'type': 'google_maps',
      'enable_widget': ?enableWidget,
      'latitude': ?latitude,
      'longitude': ?longitude,
    }),
  );

  factory GoogleInteractionTool.googleSearch({
    Iterable<String>? searchTypes,
    JsonObject? extensions,
  }) => GoogleInteractionTool.fromJson(
    _typedJson(extensions, _toolFields, {
      'type': 'google_search',
      'search_types': ?searchTypes?.toList(),
    }),
  );

  factory GoogleInteractionTool.urlContext({JsonObject? extensions}) =>
      GoogleInteractionTool.fromJson(
        _typedJson(extensions, _toolFields, {'type': 'url_context'}),
      );

  factory GoogleInteractionTool.fromJson(JsonObject raw) {
    final value = raw.toDart();
    final type = _string(value, 'type');
    final decoded = _DecodedInteractionTool(
      type: type,
      owner: switch (type) {
        'function' => ToolExecutionOwner.caller,
        final value when _providerToolTypes.contains(value) => ToolExecutionOwner.provider,
        _ => null,
      },
      name: _optionalString(value, 'name'),
      description: _optionalString(value, 'description'),
      parameters: _optionalObject(value, 'parameters'),
      fileSearchStoreNames: _optionalStrings(value, 'file_search_store_names'),
      metadataFilter: _optionalString(value, 'metadata_filter'),
      topK: _optionalInt(value, 'top_k'),
      enableWidget: _optionalBool(value, 'enable_widget'),
      latitude: _optionalDouble(value, 'latitude'),
      longitude: _optionalDouble(value, 'longitude'),
      searchTypes: _optionalStrings(value, 'search_types'),
      raw: raw,
      extensions: JsonObject(
        _without(value, {
          'type',
          'name',
          'description',
          'parameters',
          'file_search_store_names',
          'metadata_filter',
          'top_k',
          'enable_widget',
          'latitude',
          'longitude',
          'search_types',
        }),
      ),
    );
    return _knownToolTypes.contains(type)
        ? _KnownGoogleInteractionTool._(decoded)
        : GoogleUnknownInteractionTool._(decoded);
  }

  /// The native union discriminator.
  final String type;

  /// Who executes the tool call, or null for an unknown type.
  final ToolExecutionOwner? owner;

  /// The native tool name, when the type has one.
  final String? name;

  /// The description.
  final String? description;

  /// The parameters.
  final JsonObject? parameters;

  /// The file search store names.
  final List<String>? fileSearchStoreNames;

  /// The metadata filter.
  final String? metadataFilter;

  /// The top k.
  final int? topK;

  /// The enable widget.
  final bool? enableWidget;

  /// The latitude.
  final double? latitude;

  /// The longitude.
  final double? longitude;

  /// The search types.
  final List<String>? searchTypes;

  /// The complete native JSON object.
  final JsonObject raw;

  /// Fields outside the typed snapshot.
  final JsonObject extensions;

  /// Encodes this value as native JSON.
  JsonObject toJson() => raw;
}

final class _KnownGoogleInteractionTool extends GoogleInteractionTool {
  _KnownGoogleInteractionTool._(super.value) : super._();
}

/// An unrecognized tool declaration retained without loss.
final class GoogleUnknownInteractionTool extends GoogleInteractionTool {
  GoogleUnknownInteractionTool._(super.value) : super._();
}

final class _DecodedInteractionTool {
  const _DecodedInteractionTool({
    required this.type,
    required this.owner,
    required this.name,
    required this.description,
    required this.parameters,
    required this.fileSearchStoreNames,
    required this.metadataFilter,
    required this.topK,
    required this.enableWidget,
    required this.latitude,
    required this.longitude,
    required this.searchTypes,
    required this.raw,
    required this.extensions,
  });

  final String type;
  final ToolExecutionOwner? owner;
  final String? name;
  final String? description;
  final JsonObject? parameters;
  final List<String>? fileSearchStoreNames;
  final String? metadataFilter;
  final int? topK;
  final bool? enableWidget;
  final double? latitude;
  final double? longitude;
  final List<String>? searchTypes;
  final JsonObject raw;
  final JsonObject extensions;
}

/// One typed interaction step, including tool execution ownership.
sealed class GoogleInteractionStep {
  GoogleInteractionStep._(_DecodedInteractionStep value)
    : type = value.type,
      owner = value.owner,
      id = value.id,
      callId = value.callId,
      name = value.name,
      arguments = value.arguments,
      result = value.result,
      isError = value.isError,
      signature = value.signature,
      content = value.content,
      summary = value.summary,
      raw = value.raw,
      extensions = value.extensions;

  factory GoogleInteractionStep.userInput(Iterable<GoogleInteractionContent> content) =>
      GoogleInteractionStep.fromJson(
        JsonObject({
          'type': 'user_input',
          'content': content.map((value) => value.toJson().toDart()).toList(),
        }),
      );

  factory GoogleInteractionStep.functionResult({
    required String callId,
    required JsonValue result,
    String? name,
    bool? isError,
  }) => GoogleInteractionStep.fromJson(
    JsonObject({
      'type': 'function_result',
      'call_id': _nonEmpty(callId, 'callId'),
      'result': result.toDart(),
      'name': ?name,
      'is_error': ?isError,
    }),
  );

  factory GoogleInteractionStep.fromJson(JsonObject raw) {
    final value = raw.toDart();
    final type = _string(value, 'type');
    final content = _optionalContentList(value, 'content');
    final summary = _optionalContentList(value, 'summary');
    final decoded = _DecodedInteractionStep(
      type: type,
      owner: switch (type) {
        'function_call' || 'function_result' => ToolExecutionOwner.caller,
        final value when _providerStepTypes.contains(value) => ToolExecutionOwner.provider,
        _ => null,
      },
      id: _optionalString(value, 'id'),
      callId: _optionalString(value, 'call_id'),
      name: _optionalString(value, 'name'),
      arguments: _optionalObject(value, 'arguments'),
      result: value.containsKey('result') ? JsonValue.fromDart(value['result']) : null,
      isError: _optionalBool(value, 'is_error'),
      signature: _optionalString(value, 'signature'),
      content: content,
      summary: summary,
      raw: raw,
      extensions: JsonObject(
        _without(value, {
          'type',
          'id',
          'call_id',
          'name',
          'arguments',
          'result',
          'is_error',
          'signature',
          'content',
          'summary',
        }),
      ),
    );
    return _stepTypes.contains(type)
        ? _KnownGoogleInteractionStep._(decoded)
        : GoogleUnknownInteractionStep._(decoded);
  }

  /// The native union discriminator.
  final String type;

  /// Who executes the tool call, or null for an unknown type.
  final ToolExecutionOwner? owner;

  /// The provider interaction or tool-call identifier.
  final String? id;

  /// The call identifier referenced by a result step.
  final String? callId;

  /// The native tool name, when the type has one.
  final String? name;

  /// Typed JSON arguments supplied to a tool call.
  final JsonObject? arguments;

  /// The tool result in its native JSON shape.
  final JsonValue? result;

  /// The is error.
  final bool? isError;

  /// The signature.
  final String? signature;

  /// Ordered native content parts.
  final List<GoogleInteractionContent>? content;

  /// Ordered thought-summary content.
  final List<GoogleInteractionContent>? summary;

  /// The complete native JSON object.
  final JsonObject raw;

  /// Fields outside the typed snapshot.
  final JsonObject extensions;

  /// Encodes this value as native JSON.
  JsonObject toJson() => raw;
}

final class _KnownGoogleInteractionStep extends GoogleInteractionStep {
  _KnownGoogleInteractionStep._(super.value) : super._();
}

/// An unrecognized interaction step retained without loss.
final class GoogleUnknownInteractionStep extends GoogleInteractionStep {
  GoogleUnknownInteractionStep._(super.value) : super._();
}

final class _DecodedInteractionStep {
  const _DecodedInteractionStep({
    required this.type,
    required this.owner,
    required this.id,
    required this.callId,
    required this.name,
    required this.arguments,
    required this.result,
    required this.isError,
    required this.signature,
    required this.content,
    required this.summary,
    required this.raw,
    required this.extensions,
  });

  final String type;
  final ToolExecutionOwner? owner;
  final String? id;
  final String? callId;
  final String? name;
  final JsonObject? arguments;
  final JsonValue? result;
  final bool? isError;
  final String? signature;
  final List<GoogleInteractionContent>? content;
  final List<GoogleInteractionContent>? summary;
  final JsonObject raw;
  final JsonObject extensions;
}

/// Stable-v1 token accounting, retaining modality and grounding extensions.
final class GoogleInteractionUsage {
  GoogleInteractionUsage._({
    required this.totalCachedTokens,
    required this.totalInputTokens,
    required this.totalOutputTokens,
    required this.totalThoughtTokens,
    required this.totalTokens,
    required this.totalToolUseTokens,
    required this.raw,
    required this.extensions,
  });

  /// Decodes native JSON while retaining unknown fields.
  factory GoogleInteractionUsage.fromJson(JsonObject raw) {
    final value = raw.toDart();
    return GoogleInteractionUsage._(
      totalCachedTokens: _optionalInt(value, 'total_cached_tokens'),
      totalInputTokens: _optionalInt(value, 'total_input_tokens'),
      totalOutputTokens: _optionalInt(value, 'total_output_tokens'),
      totalThoughtTokens: _optionalInt(value, 'total_thought_tokens'),
      totalTokens: _optionalInt(value, 'total_tokens'),
      totalToolUseTokens: _optionalInt(value, 'total_tool_use_tokens'),
      raw: raw,
      extensions: JsonObject(
        _without(value, {
          'total_cached_tokens',
          'total_input_tokens',
          'total_output_tokens',
          'total_thought_tokens',
          'total_tokens',
          'total_tool_use_tokens',
        }),
      ),
    );
  }

  /// The total cached tokens.
  final int? totalCachedTokens;

  /// The total input tokens.
  final int? totalInputTokens;

  /// The total output tokens.
  final int? totalOutputTokens;

  /// The total thought tokens.
  final int? totalThoughtTokens;

  /// The total tokens.
  final int? totalTokens;

  /// The total tool use tokens.
  final int? totalToolUseTokens;

  /// The complete native JSON object.
  final JsonObject raw;

  /// Fields outside the typed snapshot.
  final JsonObject extensions;

  /// Encodes this value as native JSON.
  JsonObject toJson() => raw;
}

/// Error recorded on an interaction resource without turning retrieval into I/O failure.
final class GoogleInteractionError {
  GoogleInteractionError._(this.code, this.message, this.raw, this.extensions);

  /// Decodes native JSON while retaining unknown fields.
  factory GoogleInteractionError.fromJson(JsonObject raw) {
    final value = raw.toDart();
    return GoogleInteractionError._(
      _optionalString(value, 'code'),
      _optionalString(value, 'message'),
      raw,
      JsonObject(_without(value, {'code', 'message'})),
    );
  }

  /// The code.
  final String? code;

  /// The message.
  final String? message;

  /// The complete native JSON object.
  final JsonObject raw;

  /// Fields outside the typed snapshot.
  final JsonObject extensions;

  /// Encodes this value as native JSON.
  JsonObject toJson() => raw;
}

/// One interaction resource returned by create, retrieve, or cancel.
final class GoogleInteraction {
  GoogleInteraction._({
    required this.id,
    required this.model,
    required this.input,
    required this.previousInteractionId,
    required this.status,
    required this.nativeStatus,
    required this.steps,
    required this.created,
    required this.updated,
    required this.errors,
    required this.labels,
    required this.maxTotalTokens,
    required this.systemInstruction,
    required this.tools,
    required this.usage,
    required this.raw,
    required this.extensions,
  });

  /// Decodes native JSON while retaining unknown fields.
  factory GoogleInteraction.fromJson(JsonObject raw) {
    final value = raw.toDart();
    final nativeStatus = _string(value, 'status');
    return GoogleInteraction._(
      id: _optionalString(value, 'id'),
      model: _optionalString(value, 'model'),
      input: value.containsKey('input') ? GoogleInteractionInput.fromDart(value['input']) : null,
      previousInteractionId: _optionalString(value, 'previous_interaction_id'),
      status: _status(nativeStatus),
      nativeStatus: nativeStatus,
      steps: _optionalSteps(value, 'steps'),
      created: _optionalString(value, 'created'),
      updated: _optionalString(value, 'updated'),
      errors: _optionalErrors(value, 'errors'),
      labels: _optionalStringMap(value, 'labels'),
      maxTotalTokens: _optionalString(value, 'max_total_tokens'),
      systemInstruction: _optionalString(value, 'system_instruction'),
      tools: _optionalTools(value, 'tools'),
      usage: switch (value['usage']) {
        null => null,
        final Map<String, Object?> usage => GoogleInteractionUsage.fromJson(JsonObject(usage)),
        _ => throw const FormatException('interaction.usage must be an object.'),
      },
      raw: raw,
      extensions: JsonObject(
        _without(value, {
          'id',
          'model',
          'input',
          'previous_interaction_id',
          'status',
          'steps',
          'created',
          'updated',
          'errors',
          'labels',
          'max_total_tokens',
          'system_instruction',
          'tools',
          'usage',
        }),
      ),
    );
  }

  /// The provider interaction or tool-call identifier.
  final String? id;

  /// The native model name preserved exactly as supplied or returned.
  final String? model;

  /// The model input for this interaction.
  final GoogleInteractionInput? input;

  /// The explicit prior interaction to continue, when supplied.
  final String? previousInteractionId;

  /// The typed lifecycle status.
  final GoogleInteractionStatus status;

  /// The exact status string returned by the provider.
  final String nativeStatus;

  /// Ordered interaction steps, when returned.
  final List<GoogleInteractionStep>? steps;

  /// The provider creation timestamp, when returned.
  final String? created;

  /// The provider update timestamp, when returned.
  final String? updated;

  /// Diagnostic errors recorded on the interaction.
  final List<GoogleInteractionError>? errors;

  /// Caller-defined labels attached to the interaction.
  final Map<String, String>? labels;

  /// The max total tokens.
  final String? maxTotalTokens;

  /// The system instruction for this interaction.
  final String? systemInstruction;

  /// Native tools available to the model.
  final List<GoogleInteractionTool>? tools;

  /// Token accounting returned by the provider.
  final GoogleInteractionUsage? usage;

  /// The complete native JSON object.
  final JsonObject raw;

  /// Fields outside the typed snapshot.
  final JsonObject extensions;

  /// Encodes this value as native JSON.
  JsonObject toJson() => raw;
}

/// Successful empty response from an explicit delete.
final class GoogleInteractionDeleteResult {
  /// Creates a delete result from the response body retained by the transport.
  const GoogleInteractionDeleteResult(this.raw);

  /// The response object, empty for the stable v1 delete operation.
  final JsonObject raw;
}

const Set<String> _requestFields = {
  'model',
  'input',
  'background',
  'generation_config',
  'labels',
  'previous_interaction_id',
  'response_format',
  'response_mime_type',
  'safety_settings',
  'store',
  'stream',
  'system_instruction',
  'tools',
};

const Set<String> _generationConfigFields = {
  'max_output_tokens',
  'seed',
  'stop_sequences',
  'thinking_level',
  'thinking_summaries',
  'tool_choice',
  'speech_config',
};

const Set<String> _responseFormatFields = {
  'type',
  'aspect_ratio',
  'bit_rate',
  'delivery',
  'duration',
  'image_size',
  'mime_type',
  'resolution',
  'sample_rate',
  'schema',
};

const Set<String> _contentTypes = {'text', 'image', 'audio', 'document'};
const Set<String> _mediaContentTypes = {'image', 'audio', 'document'};
const Set<String> _contentFields = {
  'type',
  'text',
  'channels',
  'data',
  'uri',
  'mime_type',
  'resolution',
  'sample_rate',
  'annotations',
};
const Set<String> _toolFields = {
  'type',
  'name',
  'description',
  'parameters',
  'file_search_store_names',
  'metadata_filter',
  'top_k',
  'enable_widget',
  'latitude',
  'longitude',
  'search_types',
};
const Set<String> _providerToolTypes = {
  'code_execution',
  'file_search',
  'google_maps',
  'google_search',
  'url_context',
};
const Set<String> _knownToolTypes = {'function', ..._providerToolTypes};
const Set<String> _stepTypes = {
  'user_input',
  'model_output',
  'thought',
  'function_call',
  'function_result',
  ..._providerStepTypes,
};
const Set<String> _providerStepTypes = {
  'code_execution_call',
  'code_execution_result',
  'file_search_call',
  'file_search_result',
  'google_maps_call',
  'google_maps_result',
  'google_search_call',
  'google_search_result',
  'url_context_call',
  'url_context_result',
};

GoogleInteractionStatus _status(String value) => switch (value) {
  'in_progress' => GoogleInteractionStatus.inProgress,
  'requires_action' => GoogleInteractionStatus.requiresAction,
  'completed' => GoogleInteractionStatus.completed,
  'failed' => GoogleInteractionStatus.failed,
  'cancelled' => GoogleInteractionStatus.cancelled,
  'incomplete' => GoogleInteractionStatus.incomplete,
  _ => GoogleInteractionStatus.unknown,
};

List<GoogleInteractionContent>? _optionalContentList(
  Map<String, Object?> value,
  String key,
) => switch (value[key]) {
  null => null,
  final List<Object?> values => List.unmodifiable(
    values.map(
      (item) => GoogleInteractionContent.fromJson(_objectJson(item, '$key content')),
    ),
  ),
  _ => throw FormatException('$key must be an array.'),
};

List<GoogleInteractionStep>? _optionalSteps(Map<String, Object?> value, String key) =>
    switch (value[key]) {
      null => null,
      final List<Object?> values => List.unmodifiable(
        values.map(
          (item) => GoogleInteractionStep.fromJson(_objectJson(item, '$key step')),
        ),
      ),
      _ => throw FormatException('$key must be an array.'),
    };

List<GoogleInteractionError>? _optionalErrors(Map<String, Object?> value, String key) =>
    switch (value[key]) {
      null => null,
      final List<Object?> values => List.unmodifiable(
        values.map(
          (item) => GoogleInteractionError.fromJson(_objectJson(item, '$key error')),
        ),
      ),
      _ => throw FormatException('$key must be an array.'),
    };

List<GoogleInteractionTool>? _optionalTools(Map<String, Object?> value, String key) =>
    switch (value[key]) {
      null => null,
      final List<Object?> values => List.unmodifiable(
        values.map(
          (item) => GoogleInteractionTool.fromJson(_objectJson(item, '$key tool')),
        ),
      ),
      _ => throw FormatException('$key must be an array.'),
    };

Map<String, String>? _optionalStringMap(Map<String, Object?> value, String key) =>
    switch (value[key]) {
      null => null,
      final Map<String, Object?> values when values.values.every((item) => item is String) =>
        Map.unmodifiable(values.cast<String, String>()),
      _ => throw FormatException('$key must be a string map.'),
    };

List<String>? _optionalStrings(Map<String, Object?> value, String key) => switch (value[key]) {
  null => null,
  final List<Object?> values when values.every((item) => item is String) => List.unmodifiable(
    values.cast<String>(),
  ),
  _ => throw FormatException('$key must be a string array.'),
};

JsonObject? _optionalObject(Map<String, Object?> value, String key) => switch (value[key]) {
  null => null,
  final Map<String, Object?> object => JsonObject(object),
  _ => throw FormatException('$key must be an object.'),
};

JsonObject _objectJson(Object? value, String name) {
  if (value is! Map<String, Object?>) {
    throw FormatException('$name must be an object.');
  }
  return JsonObject(value);
}

String _string(Map<String, Object?> value, String key) {
  final field = value[key];
  if (field is! String || field.isEmpty) throw FormatException('$key must be a nonempty string.');
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

double? _optionalDouble(Map<String, Object?> value, String key) {
  final field = value[key];
  if (field == null) return null;
  if (field is! num) throw FormatException('$key must be a number.');
  return field.toDouble();
}

bool? _optionalBool(Map<String, Object?> value, String key) {
  final field = value[key];
  if (field == null) return null;
  if (field is! bool) throw FormatException('$key must be a boolean.');
  return field;
}

String _nonEmpty(String value, String name) {
  if (value.isEmpty) throw ArgumentError.value(value, name, 'must not be empty');
  return value;
}

Map<String, Object?> _without(Map<String, Object?> value, Set<String> keys) =>
    Map.fromEntries(value.entries.where((entry) => !keys.contains(entry.key)));

void _rejectCollisions(JsonObject extra, Set<String> fields) {
  final collision = extra.toDart().keys.where(fields.contains).firstOrNull;
  if (collision != null) {
    throw ArgumentError.value(collision, 'extraBody', 'collides with a typed field');
  }
}

JsonObject _typedJson(
  JsonObject? extensions,
  Set<String> typedFields,
  Map<String, Object?> values,
) {
  final extra = extensions ?? JsonObject({});
  _rejectCollisions(extra, typedFields);
  return JsonObject({...extra.toDart(), ...values});
}
