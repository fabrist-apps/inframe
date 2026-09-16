import 'package:artificer_core/src/serialization.dart';
import 'package:dart_mappable/dart_mappable.dart';

part 'messages.mapper.dart';

/// One explicit, caller-owned conversation turn.
@MappableClass(
  discriminatorKey: 'type',
  generateMethods: GenerateMethods.encode | GenerateMethods.decode,
)
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
@MappableClass(
  discriminatorValue: 'user',
  generateMethods: GenerateMethods.encode | GenerateMethods.decode,
)
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
@MappableClass(
  discriminatorValue: 'assistant',
  generateMethods: GenerateMethods.encode | GenerateMethods.decode,
)
final class AssistantMessage extends Message with AssistantMessageMappable {
  /// Creates a [AssistantMessage] retaining the supplied values.
  AssistantMessage(this.parts, {super.schemaVersion});

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
@MappableClass(
  discriminatorKey: 'type',
  generateMethods: GenerateMethods.encode | GenerateMethods.decode,
)
sealed class InputPart with InputPartMappable {
  /// Creates a [InputPart] retaining the supplied values.
  const InputPart();

  /// Decodes a map using the shipped generated mapper.
  static const fromMap = InputPartMapper.fromMap;

  /// Decodes a JSON string using the shipped generated mapper.
  static const fromJson = InputPartMapper.fromJson;
}

/// One text input segment.
@MappableClass(
  discriminatorValue: 'text',
  generateMethods: GenerateMethods.encode | GenerateMethods.decode,
)
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
@MappableClass(
  discriminatorKey: 'type',
  generateMethods: GenerateMethods.encode | GenerateMethods.decode,
)
sealed class OutputPart with OutputPartMappable {
  /// Creates a [OutputPart] retaining the supplied values.
  const OutputPart();

  /// Decodes a map using the shipped generated mapper.
  static const fromMap = OutputPartMapper.fromMap;

  /// Decodes a JSON string using the shipped generated mapper.
  static const fromJson = OutputPartMapper.fromJson;
}

/// Text returned by the model.
@MappableClass(
  discriminatorValue: 'text',
  generateMethods: GenerateMethods.encode | GenerateMethods.decode,
)
final class TextOutputPart extends OutputPart with TextOutputPartMappable {
  /// Creates a [TextOutputPart] retaining the supplied values.
  const TextOutputPart(this.text);

  /// The text content.
  final String text;

  /// Decodes a map using the shipped generated mapper.
  static const fromMap = TextOutputPartMapper.fromMap;

  /// Decodes a JSON string using the shipped generated mapper.
  static const fromJson = TextOutputPartMapper.fromJson;
}
