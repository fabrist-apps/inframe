import 'package:artificer_core/src/json/json_value_hook.dart';
import 'package:artificer_core/src/settings.dart';
import 'package:dart_mappable/dart_mappable.dart';

part 'responses_models.mapper.dart';

/// Provider-native tool inventory and neutral extra fields; common controls remain authoritative.
@MappableClass()
final class ResponsesOptions with ResponsesOptionsMappable {
  /// Creates the value retaining supplied collections.
  const ResponsesOptions({
    this.nativeTools = const Setting.inherit(),
    this.extraBody = const Setting.inherit(),
  });

  /// NativeTools.
  final Setting<List<Map<String, Object?>>> nativeTools;

  /// ExtraBody.
  final Setting<Map<String, Object?>> extraBody;

  /// Decodes persisted map data.
  static const fromMap = ResponsesOptionsMapper.fromMap;

  /// Decodes persisted JSON.
  static const fromJson = ResponsesOptionsMapper.fromJson;
}

/// Typed foreground text request. Wire serialization resolves policy and always sends store false.
@MappableClass()
final class ResponsesRequest with ResponsesRequestMappable {
  /// Creates the value retaining supplied collections.
  const ResponsesRequest({
    required this.model,
    required this.input,
    this.instructions,
    this.tools = const [],
    this.toolChoice,
    this.text,
    this.maxOutputTokens,
    this.temperature,
    this.topP,
    this.extraBody = const {},
  });

  /// Model.
  final String model;

  /// Input.
  @MappableField(hook: JsonValueHook())
  final List<Map<String, Object?>> input;

  /// Instructions.
  final String? instructions;

  /// Tools.
  @MappableField(hook: JsonValueHook())
  final List<Map<String, Object?>> tools;

  /// ToolChoice.
  @MappableField(hook: JsonValueHook())
  final Object? toolChoice;

  /// Text.
  @MappableField(hook: JsonValueHook())
  final Map<String, Object?>? text;

  /// MaxOutputTokens.
  final int? maxOutputTokens;

  /// Temperature.
  final double? temperature;

  /// TopP.
  final double? topP;

  /// ExtraBody.
  @MappableField(hook: JsonValueHook())
  final Map<String, Object?> extraBody;

  /// Decodes persisted map data.
  static const fromMap = ResponsesRequestMapper.fromMap;

  /// Decodes persisted JSON.
  static const fromJson = ResponsesRequestMapper.fromJson;
}

/// Typed response fields; NativePayload retains every unknown nested field.
@MappableClass()
final class ResponsesResponse with ResponsesResponseMappable {
  /// Creates the value retaining supplied collections.
  const ResponsesResponse({
    required this.id,
    required this.model,
    required this.status,
    required this.output,
    this.usage,
    this.error,
    this.incompleteDetails,
    this.candidates = const [],
  });

  /// Id.
  final String id;

  /// Model.
  final String model;

  /// Status.
  final String status;

  /// Output.
  @MappableField(hook: JsonValueHook())
  final List<Map<String, Object?>> output;

  /// Usage.
  @MappableField(hook: JsonValueHook())
  final Map<String, Object?>? usage;

  /// Error.
  @MappableField(hook: JsonValueHook())
  final Map<String, Object?>? error;

  /// IncompleteDetails.
  @MappableField(key: 'incomplete_details', hook: JsonValueHook())
  final Map<String, Object?>? incompleteDetails;

  /// Candidates.
  @MappableField(hook: JsonValueHook())
  final List<Map<String, Object?>> candidates;

  /// Decodes persisted map data.
  static const fromMap = ResponsesResponseMapper.fromMap;

  /// Decodes persisted JSON.
  static const fromJson = ResponsesResponseMapper.fromJson;
}
