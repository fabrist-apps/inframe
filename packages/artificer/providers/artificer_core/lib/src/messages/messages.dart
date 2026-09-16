import 'package:artificer_core/src/json/json_value_hook.dart';
import 'package:artificer_core/src/serialization.dart';
import 'package:artificer_core/src/tools/tools.dart';
import 'package:dart_mappable/dart_mappable.dart';

part 'messages.mapper.dart';

/// One explicit, caller-owned conversation turn.
@MappableClass(discriminatorKey: 'type')
sealed class Message with MessageMappable {
  /// Creates a [Message] retaining the supplied values.
  Message({this.schemaVersion = 1}) {
    DomainSchema.check(schemaVersion);
  }

  /// Persisted domain schema version; only version 1 is supported.
  final int schemaVersion;

  /// Decodes a map using the shipped generated mapper.
  static const fromMap = MessageMapper.fromMap;

  /// Decodes a JSON string using the shipped generated mapper.
  static const fromJson = MessageMapper.fromJson;
}

/// Ordered text supplied by the caller.
@MappableClass(discriminatorValue: 'user')
final class UserMessage extends Message with UserMessageMappable {
  /// Creates a [UserMessage] retaining the supplied values.
  UserMessage(this.parts, {super.schemaVersion}) {
    if (parts.isEmpty) throw ArgumentError.value(parts, 'parts', 'Must not be empty.');
  }

  /// Creates a [UserMessage] retaining the supplied values.
  UserMessage.text(String text) : this([TextInputPart(text)]);

  /// Ordered parts, retained without defensive copying.
  final List<InputPart> parts;

  /// Decodes a map using the shipped generated mapper.
  static const fromMap = UserMessageMapper.fromMap;

  /// Decodes a JSON string using the shipped generated mapper.
  static const fromJson = UserMessageMapper.fromJson;
}

/// Model-authored output. Empty output is valid for blocked responses.
@MappableClass(discriminatorValue: 'assistant')
final class AssistantMessage extends Message with AssistantMessageMappable {
  /// Creates a [AssistantMessage] retaining the supplied values.
  AssistantMessage(this.parts, {this.replay, super.schemaVersion});

  /// Same-target native replay. Clear after direct mutation of nested content.
  ProviderReplay? replay;

  /// Replaces content and drops replay state. Generated copyWith retains replay.
  AssistantMessage withParts(List<OutputPart> parts) => AssistantMessage(parts);

  /// Ordered parts, retained without defensive copying.
  final List<OutputPart> parts;

  /// The text content.
  String get text => parts.whereType<TextOutputPart>().map((part) => part.text).join();

  /// Decodes a map using the shipped generated mapper.
  static const fromMap = AssistantMessageMapper.fromMap;

  /// Decodes a JSON string using the shipped generated mapper.
  static const fromJson = AssistantMessageMapper.fromJson;
}

/// Text-only input family.
@MappableClass(discriminatorKey: 'type')
sealed class InputPart with InputPartMappable {
  /// Creates a [InputPart] retaining the supplied values.
  const InputPart();

  /// Decodes a map using the shipped generated mapper.
  static const fromMap = InputPartMapper.fromMap;

  /// Decodes a JSON string using the shipped generated mapper.
  static const fromJson = InputPartMapper.fromJson;
}

/// One text input segment.
@MappableClass(discriminatorValue: 'text')
final class TextInputPart extends InputPart with TextInputPartMappable {
  /// Creates a [TextInputPart] retaining the supplied values.
  const TextInputPart(this.text);

  /// The text content.
  final String text;

  /// Decodes a map using the shipped generated mapper.
  static const fromMap = TextInputPartMapper.fromMap;

  /// Decodes a JSON string using the shipped generated mapper.
  static const fromJson = TextInputPartMapper.fromJson;
}

/// Ordered output content.
@MappableClass(discriminatorKey: 'type')
sealed class OutputPart with OutputPartMappable {
  /// Creates a [OutputPart] retaining the supplied values.
  const OutputPart();

  /// Decodes a map using the shipped generated mapper.
  static const fromMap = OutputPartMapper.fromMap;

  /// Decodes a JSON string using the shipped generated mapper.
  static const fromJson = OutputPartMapper.fromJson;
}

/// Text returned by the model.
@MappableClass(discriminatorValue: 'text')
final class TextOutputPart extends OutputPart with TextOutputPartMappable {
  /// Creates a [TextOutputPart] retaining the supplied values.
  const TextOutputPart(this.text, {this.citations = const []});

  /// Ordered citations attached to this text.
  final List<Citation> citations;

  /// The text content.
  final String text;

  /// Decodes a map using the shipped generated mapper.
  static const fromMap = TextOutputPartMapper.fromMap;

  /// Decodes a JSON string using the shipped generated mapper.
  static const fromJson = TextOutputPartMapper.fromJson;
}

/// Caller supplied application results, in original order.
@MappableClass(discriminatorValue: 'tool')
final class ToolMessage extends Message with ToolMessageMappable {
  /// Creates a nonempty result turn without copying it.
  ToolMessage(this.results, {super.schemaVersion}) {
    if (results.isEmpty) throw ArgumentError.value(results, 'results');
  }

  /// Ordered application results.
  final List<ToolResult> results;

  /// Decodes persisted map data.
  static const fromMap = ToolMessageMapper.fromMap;

  /// Decodes persisted JSON.
  static const fromJson = ToolMessageMapper.fromJson;
}

/// Ordered citation details; native data retains unknown provider fields.
@MappableClass()
final class Citation with CitationMappable {
  /// Creates the value retaining supplied collections.
  const Citation({
    required this.data,
    this.url,
    this.title,
    this.start,
    this.end,
  });

  /// Data.
  @MappableField(hook: JsonValueHook())
  final Object? data;

  /// Url.
  final String? url;

  /// Title.
  final String? title;

  /// Start.
  final int? start;

  /// End.
  final int? end;

  /// Decodes persisted map data.
  static const fromMap = CitationMapper.fromMap;

  /// Decodes persisted JSON.
  static const fromJson = CitationMapper.fromJson;
}

/// Ordered native JSON blocks for exact same-target resubmission.
@MappableClass()
final class ProviderReplay with ProviderReplayMappable {
  /// Creates the value retaining supplied collections.
  ProviderReplay({
    required this.providerId,
    required this.api,
    required this.modelId,
    required this.items,
    this.schemaVersion = 1,
  }) {
    DomainSchema.check(schemaVersion);
  }

  /// ProviderId.
  final String providerId;

  /// Api.
  final String api;

  /// ModelId.
  final String modelId;

  /// Items.
  @MappableField(hook: JsonValueHook())
  final List<Object?> items;

  /// SchemaVersion.
  final int schemaVersion;

  /// Decodes persisted map data.
  static const fromMap = ProviderReplayMapper.fromMap;

  /// Decodes persisted JSON.
  static const fromJson = ProviderReplayMapper.fromJson;
}

/// Explicit execution ownership; provider work never becomes an application call.
@MappableEnum()
enum ToolExecutionOwner {
  /// Executed by the calling application.
  application,

  /// Executed by the provider.
  provider,
}

/// Observed provider work state, including unfinished records.
@MappableEnum()
enum ToolStatus {
  /// Waiting to start.
  pending,

  /// Execution underway.
  running,

  /// Execution completed.
  completed,

  /// Execution failed.
  failed,

  /// Unrecognized or absent native status.
  unknown,
}

/// ReasoningOutputPart.
@MappableClass(discriminatorValue: 'reasoning')
final class ReasoningOutputPart extends OutputPart with ReasoningOutputPartMappable {
  /// Creates the value retaining supplied collections.
  const ReasoningOutputPart({required this.summary});

  /// Summary.
  final String summary;

  /// Decodes persisted map data.
  static const fromMap = ReasoningOutputPartMapper.fromMap;

  /// Decodes persisted JSON.
  static const fromJson = ReasoningOutputPartMapper.fromJson;
}

/// RefusalOutputPart.
@MappableClass(discriminatorValue: 'refusal')
final class RefusalOutputPart extends OutputPart with RefusalOutputPartMappable {
  /// Creates the value retaining supplied collections.
  const RefusalOutputPart({required this.text});

  /// Text.
  final String text;

  /// Decodes persisted map data.
  static const fromMap = RefusalOutputPartMapper.fromMap;

  /// Decodes persisted JSON.
  static const fromJson = RefusalOutputPartMapper.fromJson;
}

/// OpaqueOutputPart.
@MappableClass(discriminatorValue: 'opaque')
final class OpaqueOutputPart extends OutputPart with OpaqueOutputPartMappable {
  /// Creates the value retaining supplied collections.
  const OpaqueOutputPart({required this.providerId, required this.api, required this.data});

  /// ProviderId.
  final String providerId;

  /// Api.
  final String api;

  /// Data.
  @MappableField(hook: JsonValueHook())
  final Object? data;

  /// Decodes persisted map data.
  static const fromMap = OpaqueOutputPartMapper.fromMap;

  /// Decodes persisted JSON.
  static const fromJson = OpaqueOutputPartMapper.fromJson;
}

/// ToolCallPart.
@MappableClass(discriminatorValue: 'toolCall')
final class ToolCallPart extends OutputPart with ToolCallPartMappable {
  /// Creates the value retaining supplied collections.
  ToolCallPart({required this.callId, required this.name, required this.arguments}) {
    if (callId.isEmpty || name.isEmpty) {
      throw ArgumentError('Tool call ID and name must be nonempty.');
    }
  }

  /// CallId.
  final String callId;

  /// Name.
  final String name;

  /// Arguments.
  final ToolArguments arguments;

  /// Decodes persisted map data.
  static const fromMap = ToolCallPartMapper.fromMap;

  /// Decodes persisted JSON.
  static const fromJson = ToolCallPartMapper.fromJson;
}

/// ProviderToolPart.
@MappableClass(discriminatorValue: 'providerTool')
final class ProviderToolPart extends OutputPart with ProviderToolPartMappable {
  /// Creates the value retaining supplied collections.
  const ProviderToolPart({
    required this.id,
    required this.name,
    required this.owner,
    required this.native,
    this.status = ToolStatus.unknown,
  });

  /// Id.
  final String id;

  /// Name.
  final String name;

  /// Owner.
  final ToolExecutionOwner owner;

  /// Status.
  final ToolStatus status;

  /// Native.
  @MappableField(hook: JsonValueHook())
  final Object? native;

  /// Decodes persisted map data.
  static const fromMap = ProviderToolPartMapper.fromMap;

  /// Decodes persisted JSON.
  static const fromJson = ProviderToolPartMapper.fromJson;
}
