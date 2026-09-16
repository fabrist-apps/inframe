import 'package:artificer_core/src/generation/generation.dart';
import 'package:artificer_core/src/json/json_value_hook.dart';
import 'package:artificer_core/src/settings.dart';
import 'package:dart_mappable/dart_mappable.dart';

part 'chat_models.mapper.dart';

/// Compatible Chat settings that do not duplicate common request fields.
@MappableClass(generateMethods: GenerateMethods.encode | GenerateMethods.decode)
final class ChatOptions with ChatOptionsMappable {
  /// Creates per-call overrides; omission inherits provider defaults.
  const ChatOptions({
    this.seed = const Setting.inherit(),
    this.user = const Setting.inherit(),
    this.parallelToolCalls = const Setting.inherit(),
    this.extraBody = const Setting.inherit(),
  });

  /// Native reproducibility hint.
  final Setting<int> seed;

  /// Native caller identifier; not included in diagnostics.
  final Setting<String> user;

  /// Native application tool concurrency preference.
  final Setting<bool> parallelToolCalls;

  /// Neutral native text fields; replaces the inherited extras map.
  final Setting<Map<String, Object?>> extraBody;

  /// Generated persisted-map decoder.
  static const fromMap = ChatOptionsMapper.fromMap;

  /// Generated persisted-JSON decoder.
  static const fromJson = ChatOptionsMapper.fromJson;
}

/// A foreground native Chat request, independent of common generation defaults.
@MappableClass(generateMethods: GenerateMethods.encode | GenerateMethods.decode)
final class NativeChatRequest with NativeChatRequestMappable {
  /// Retains supplied native text messages and optional fields.
  NativeChatRequest({
    required this.model,
    required this.messages,
    this.maxTokens,
    this.temperature,
    this.topP,
    this.stop,
    this.tools,
    this.toolChoice,
    this.responseFormat,
    this.n,
    this.seed,
    this.user,
    this.parallelToolCalls,
    this.extraBody = const {},
  }) {
    if (model.isEmpty) throw ArgumentError.value(model, 'model');
    if (messages.isEmpty) throw ArgumentError.value(messages, 'messages');
  }

  /// Open provider-local model identity.
  final String model;

  /// Ordered native text/tool messages, including provider role distinctions.
  @MappableField(hook: JsonValueHook())
  final List<Map<String, Object?>> messages;

  /// Native output limit; omitted unless explicitly supplied.
  final NativeField<int>? maxTokens;

  /// Native sampling value with explicit null support.
  final NativeField<double>? temperature;

  /// Native nucleus sampling value with explicit null support.
  final NativeField<double>? topP;

  /// Native stop configuration with omitted/null/value distinction.
  final NativeField<Object?>? stop;

  /// Native typed tool declarations; endpoint inventory still applies.
  @MappableField(hook: JsonValueHook())
  final List<Map<String, Object?>>? tools;

  /// Native tool-selection shape.
  final NativeField<Object?>? toolChoice;

  /// Native output-format shape.
  @MappableField(hook: JsonValueHook())
  final Map<String, Object?>? responseFormat;

  /// Native candidate count; common calls always use one.
  final int? n;

  /// Native seed with omitted/null/value distinction.
  final NativeField<int>? seed;

  /// Native caller identifier with omitted/null/value distinction.
  final NativeField<String>? user;

  /// Native application tool concurrency preference.
  final NativeField<bool>? parallelToolCalls;

  /// Neutral extra text fields, never overrides of typed fields.
  @MappableField(hook: JsonValueHook())
  final Map<String, Object?> extraBody;

  /// Generated persisted-map decoder.
  static const fromMap = NativeChatRequestMapper.fromMap;

  /// Generated persisted-JSON decoder.
  static const fromJson = NativeChatRequestMapper.fromJson;
}

/// Typed Chat response view; its NativeResponse separately retains all JSON.
@MappableClass(generateMethods: GenerateMethods.encode | GenerateMethods.decode)
final class ChatResponse with ChatResponseMappable {
  /// Retains choices and available native identity/accounting.
  const ChatResponse({required this.model, required this.choices, this.id, this.usage});

  /// Actual service model identity, which can differ from the requested alias.
  final String model;

  /// Available candidate messages in service order.
  final List<ChatChoice> choices;

  /// Native response identity.
  final String? id;

  /// Nullable native usage; missing accounting is never synthesized as zero.
  final Usage? usage;

  /// Generated persisted-map decoder.
  static const fromMap = ChatResponseMapper.fromMap;

  /// Generated persisted-JSON decoder.
  static const fromJson = ChatResponseMapper.fromJson;
}

/// A native candidate that callers may select explicitly for normalization.
@MappableClass(generateMethods: GenerateMethods.encode | GenerateMethods.decode)
final class ChatChoice with ChatChoiceMappable {
  /// Retains the native message without losing unknown fields.
  const ChatChoice({required this.index, required this.message, this.finishReason});

  /// Provider candidate index, independent of list position.
  final int index;

  /// Complete native assistant message, including extensions and replay fields.
  @MappableField(hook: JsonValueHook())
  final Map<String, Object?> message;

  /// Native terminal reason, including unfamiliar provider values.
  final String? finishReason;

  /// Generated persisted-map decoder.
  static const fromMap = ChatChoiceMapper.fromMap;

  /// Generated persisted-JSON decoder.
  static const fromJson = ChatChoiceMapper.fromJson;
}
