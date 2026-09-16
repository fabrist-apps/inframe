import 'dart:convert';

import 'package:artificer_core/src/json/json_value.dart';
import 'package:artificer_core/src/json/json_value_hook.dart';
import 'package:dart_mappable/dart_mappable.dart';

part 'tools.mapper.dart';

/// An application function declaration with no execution callback.
@MappableClass(generateMethods: GenerateMethods.encode | GenerateMethods.decode)
final class FunctionTool with FunctionToolMappable {
  /// Creates the value retaining supplied collections.
  FunctionTool({required this.name, required this.inputSchema, this.description}) {
    if (name.isEmpty) throw ArgumentError.value(name, 'name', 'Must not be empty.');
  }

  /// Name.
  final String name;

  /// Description.
  final String? description;

  /// InputSchema.
  @MappableField(hook: JsonValueHook())
  final Map<String, Object?> inputSchema;

  /// Decodes persisted map data.
  static const fromMap = FunctionToolMapper.fromMap;

  /// Decodes persisted JSON.
  static const fromJson = FunctionToolMapper.fromJson;
}

/// Closed ToolChoice variants.
@MappableClass(
  discriminatorKey: 'type',
  generateMethods: GenerateMethods.encode | GenerateMethods.decode,
)
sealed class ToolChoice with ToolChoiceMappable {
  /// Creates a variant.
  const ToolChoice();

  /// Decodes persisted map data.
  static const fromMap = ToolChoiceMapper.fromMap;

  /// Decodes persisted JSON.
  static const fromJson = ToolChoiceMapper.fromJson;
}

/// AutoToolChoice.
@MappableClass(
  discriminatorValue: 'auto',
  generateMethods: GenerateMethods.encode | GenerateMethods.decode,
)
final class AutoToolChoice extends ToolChoice with AutoToolChoiceMappable {
  /// Creates the value retaining supplied collections.
  const AutoToolChoice();

  /// Decodes persisted map data.
  static const fromMap = AutoToolChoiceMapper.fromMap;

  /// Decodes persisted JSON.
  static const fromJson = AutoToolChoiceMapper.fromJson;
}

/// NoToolChoice.
@MappableClass(
  discriminatorValue: 'none',
  generateMethods: GenerateMethods.encode | GenerateMethods.decode,
)
final class NoToolChoice extends ToolChoice with NoToolChoiceMappable {
  /// Creates the value retaining supplied collections.
  const NoToolChoice();

  /// Decodes persisted map data.
  static const fromMap = NoToolChoiceMapper.fromMap;

  /// Decodes persisted JSON.
  static const fromJson = NoToolChoiceMapper.fromJson;
}

/// RequiredToolChoice.
@MappableClass(
  discriminatorValue: 'required',
  generateMethods: GenerateMethods.encode | GenerateMethods.decode,
)
final class RequiredToolChoice extends ToolChoice with RequiredToolChoiceMappable {
  /// Creates the value retaining supplied collections.
  const RequiredToolChoice();

  /// Decodes persisted map data.
  static const fromMap = RequiredToolChoiceMapper.fromMap;

  /// Decodes persisted JSON.
  static const fromJson = RequiredToolChoiceMapper.fromJson;
}

/// NamedToolChoice.
@MappableClass(
  discriminatorValue: 'named',
  generateMethods: GenerateMethods.encode | GenerateMethods.decode,
)
final class NamedToolChoice extends ToolChoice with NamedToolChoiceMappable {
  /// Creates the value retaining supplied collections.
  NamedToolChoice({required this.name}) {
    if (name.isEmpty) throw ArgumentError.value(name, 'name');
  }

  /// Name.
  final String name;

  /// Decodes persisted map data.
  static const fromMap = NamedToolChoiceMapper.fromMap;

  /// Decodes persisted JSON.
  static const fromJson = NamedToolChoiceMapper.fromJson;
}

/// Closed OutputFormat variants.
@MappableClass(
  discriminatorKey: 'type',
  generateMethods: GenerateMethods.encode | GenerateMethods.decode,
)
sealed class OutputFormat with OutputFormatMappable {
  /// Creates a variant.
  const OutputFormat();

  /// Decodes persisted map data.
  static const fromMap = OutputFormatMapper.fromMap;

  /// Decodes persisted JSON.
  static const fromJson = OutputFormatMapper.fromJson;
}

/// TextOutput.
@MappableClass(
  discriminatorValue: 'text',
  generateMethods: GenerateMethods.encode | GenerateMethods.decode,
)
final class TextOutput extends OutputFormat with TextOutputMappable {
  /// Creates the value retaining supplied collections.
  const TextOutput();

  /// Decodes persisted map data.
  static const fromMap = TextOutputMapper.fromMap;

  /// Decodes persisted JSON.
  static const fromJson = TextOutputMapper.fromJson;
}

/// JsonObjectOutput.
@MappableClass(
  discriminatorValue: 'jsonObject',
  generateMethods: GenerateMethods.encode | GenerateMethods.decode,
)
final class JsonObjectOutput extends OutputFormat with JsonObjectOutputMappable {
  /// Creates the value retaining supplied collections.
  const JsonObjectOutput();

  /// Decodes persisted map data.
  static const fromMap = JsonObjectOutputMapper.fromMap;

  /// Decodes persisted JSON.
  static const fromJson = JsonObjectOutputMapper.fromJson;
}

/// JsonSchemaOutput.
@MappableClass(
  discriminatorValue: 'jsonSchema',
  generateMethods: GenerateMethods.encode | GenerateMethods.decode,
)
final class JsonSchemaOutput extends OutputFormat with JsonSchemaOutputMappable {
  /// Creates the value retaining supplied collections.
  JsonSchemaOutput({required this.name, required this.schema, this.description}) {
    if (name.isEmpty) throw ArgumentError.value(name, 'name');
  }

  /// Name.
  final String name;

  /// Description.
  final String? description;

  /// Schema.
  @MappableField(hook: JsonValueHook())
  final Map<String, Object?> schema;

  /// Decodes persisted map data.
  static const fromMap = JsonSchemaOutputMapper.fromMap;

  /// Decodes persisted JSON.
  static const fromJson = JsonSchemaOutputMapper.fromJson;
}

/// Closed ToolArguments variants.
@MappableClass(
  discriminatorKey: 'type',
  generateMethods: GenerateMethods.encode | GenerateMethods.decode,
)
sealed class ToolArguments with ToolArgumentsMappable {
  /// Creates a variant.
  const ToolArguments();

  /// Parses function arguments without fabricating an object on malformed output.
  static ToolArguments parse(String original) {
    try {
      final Object? value = jsonDecode(original);
      JsonValues.validate(value);
      if (value is Map<String, Object?>) return JsonToolArguments(value: value, original: original);
      return MalformedToolArguments(original: original, issue: 'Expected a JSON object.');
    } on FormatException catch (error) {
      return MalformedToolArguments(original: original, issue: error.message);
    }
  }

  /// Decodes persisted map data.
  static const fromMap = ToolArgumentsMapper.fromMap;

  /// Decodes persisted JSON.
  static const fromJson = ToolArgumentsMapper.fromJson;
}

/// JsonToolArguments.
@MappableClass(
  discriminatorValue: 'json',
  generateMethods: GenerateMethods.encode | GenerateMethods.decode,
)
final class JsonToolArguments extends ToolArguments with JsonToolArgumentsMappable {
  /// Creates the value retaining supplied collections.
  const JsonToolArguments({required this.value, this.original});

  /// Value.
  @MappableField(hook: JsonValueHook())
  final Map<String, Object?> value;

  /// Original.
  final String? original;

  /// Decodes persisted map data.
  static const fromMap = JsonToolArgumentsMapper.fromMap;

  /// Decodes persisted JSON.
  static const fromJson = JsonToolArgumentsMapper.fromJson;
}

/// FreeFormToolArguments.
@MappableClass(
  discriminatorValue: 'freeForm',
  generateMethods: GenerateMethods.encode | GenerateMethods.decode,
)
final class FreeFormToolArguments extends ToolArguments with FreeFormToolArgumentsMappable {
  /// Creates the value retaining supplied collections.
  const FreeFormToolArguments({required this.text});

  /// Text.
  final String text;

  /// Decodes persisted map data.
  static const fromMap = FreeFormToolArgumentsMapper.fromMap;

  /// Decodes persisted JSON.
  static const fromJson = FreeFormToolArgumentsMapper.fromJson;
}

/// NativeToolArguments.
@MappableClass(
  discriminatorValue: 'native',
  generateMethods: GenerateMethods.encode | GenerateMethods.decode,
)
final class NativeToolArguments extends ToolArguments with NativeToolArgumentsMappable {
  /// Creates the value retaining supplied collections.
  const NativeToolArguments({required this.providerId, required this.api, required this.value});

  /// ProviderId.
  final String providerId;

  /// Api.
  final String api;

  /// Value.
  @MappableField(hook: JsonValueHook())
  final Object? value;

  /// Decodes persisted map data.
  static const fromMap = NativeToolArgumentsMapper.fromMap;

  /// Decodes persisted JSON.
  static const fromJson = NativeToolArgumentsMapper.fromJson;
}

/// MalformedToolArguments.
@MappableClass(
  discriminatorValue: 'malformed',
  generateMethods: GenerateMethods.encode | GenerateMethods.decode,
)
final class MalformedToolArguments extends ToolArguments with MalformedToolArgumentsMappable {
  /// Creates the value retaining supplied collections.
  const MalformedToolArguments({required this.original, required this.issue});

  /// Original.
  final String original;

  /// Issue.
  final String issue;

  /// Decodes persisted map data.
  static const fromMap = MalformedToolArgumentsMapper.fromMap;

  /// Decodes persisted JSON.
  static const fromJson = MalformedToolArgumentsMapper.fromJson;
}

/// Closed ToolResultContent variants.
@MappableClass(
  discriminatorKey: 'type',
  generateMethods: GenerateMethods.encode | GenerateMethods.decode,
)
sealed class ToolResultContent with ToolResultContentMappable {
  /// Creates a variant.
  const ToolResultContent();

  /// Decodes persisted map data.
  static const fromMap = ToolResultContentMapper.fromMap;

  /// Decodes persisted JSON.
  static const fromJson = ToolResultContentMapper.fromJson;
}

/// JsonToolResultContent.
@MappableClass(
  discriminatorValue: 'json',
  generateMethods: GenerateMethods.encode | GenerateMethods.decode,
)
final class JsonToolResultContent extends ToolResultContent with JsonToolResultContentMappable {
  /// Creates the value retaining supplied collections.
  const JsonToolResultContent({required this.value});

  /// Value.
  @MappableField(hook: JsonValueHook())
  final Object? value;

  /// Decodes persisted map data.
  static const fromMap = JsonToolResultContentMapper.fromMap;

  /// Decodes persisted JSON.
  static const fromJson = JsonToolResultContentMapper.fromJson;
}

/// TextToolResultContent.
@MappableClass(
  discriminatorValue: 'text',
  generateMethods: GenerateMethods.encode | GenerateMethods.decode,
)
final class TextToolResultContent extends ToolResultContent with TextToolResultContentMappable {
  /// Creates the value retaining supplied collections.
  const TextToolResultContent({required this.parts});

  /// Parts.
  final List<String> parts;

  /// Decodes persisted map data.
  static const fromMap = TextToolResultContentMapper.fromMap;

  /// Decodes persisted JSON.
  static const fromJson = TextToolResultContentMapper.fromJson;
}

/// NativeToolResultContent.
@MappableClass(
  discriminatorValue: 'native',
  generateMethods: GenerateMethods.encode | GenerateMethods.decode,
)
final class NativeToolResultContent extends ToolResultContent with NativeToolResultContentMappable {
  /// Creates the value retaining supplied collections.
  const NativeToolResultContent({required this.providerId, required this.api, required this.value});

  /// ProviderId.
  final String providerId;

  /// Api.
  final String api;

  /// Value.
  @MappableField(hook: JsonValueHook())
  final Object? value;

  /// Decodes persisted map data.
  static const fromMap = NativeToolResultContentMapper.fromMap;

  /// Decodes persisted JSON.
  static const fromJson = NativeToolResultContentMapper.fromJson;
}

/// Closed ToolResult variants.
@MappableClass(
  discriminatorKey: 'type',
  generateMethods: GenerateMethods.encode | GenerateMethods.decode,
)
sealed class ToolResult with ToolResultMappable {
  /// Creates a variant.
  const ToolResult();

  /// Stable application call identity.
  String get callId;

  /// Caller supplied result, forwarded without execution or validation.
  ToolResultContent get content;

  /// Decodes persisted map data.
  static const fromMap = ToolResultMapper.fromMap;

  /// Decodes persisted JSON.
  static const fromJson = ToolResultMapper.fromJson;
}

/// ToolSuccess.
@MappableClass(
  discriminatorValue: 'success',
  generateMethods: GenerateMethods.encode | GenerateMethods.decode,
)
final class ToolSuccess extends ToolResult with ToolSuccessMappable {
  /// Creates the value retaining supplied collections.
  ToolSuccess({required this.callId, required this.content}) {
    if (callId.isEmpty) throw ArgumentError.value(callId, 'callId');
  }

  /// CallId.
  @override
  final String callId;

  /// Content.
  @override
  final ToolResultContent content;

  /// Decodes persisted map data.
  static const fromMap = ToolSuccessMapper.fromMap;

  /// Decodes persisted JSON.
  static const fromJson = ToolSuccessMapper.fromJson;
}

/// ToolFailure.
@MappableClass(
  discriminatorValue: 'applicationError',
  generateMethods: GenerateMethods.encode | GenerateMethods.decode,
)
final class ToolFailure extends ToolResult with ToolFailureMappable {
  /// Creates the value retaining supplied collections.
  ToolFailure({required this.callId, required this.content}) {
    if (callId.isEmpty) throw ArgumentError.value(callId, 'callId');
  }

  /// CallId.
  @override
  final String callId;

  /// Content.
  @override
  final ToolResultContent content;

  /// Decodes persisted map data.
  static const fromMap = ToolFailureMapper.fromMap;

  /// Decodes persisted JSON.
  static const fromJson = ToolFailureMapper.fromJson;
}
