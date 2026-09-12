import 'dart:convert';
import 'dart:typed_data';

import 'package:artificer_core/src/json/json_value.dart';

/// One ordered conversation turn.
sealed class Message {
  const Message();

  /// Serializes this value using schema version 1.
  JsonObject toJson();

  /// Deserializes and validates a schema-versioned value.
  static Message fromJson(JsonObject json) {
    final value = _versioned(json);
    return switch (_string(value, 'type')) {
      'user' => UserMessage(_list(value, 'parts').map(InputPart.fromDart)),
      'assistant' => AssistantMessage(
        _list(value, 'parts').map(OutputPart.fromDart),
        replay: switch (value['replay']) {
          final Map<String, Object?> replay => ProviderReplay.fromJson(JsonObject(replay)),
          _ => null,
        },
      ),
      'tool' => ToolMessage(_list(value, 'results').map(ToolResult.fromDart)),
      final type => throw FormatException('Unknown message type: $type'),
    };
  }
}

/// A caller-authored message.
final class UserMessage extends Message {
  /// Creates a [UserMessage].
  UserMessage(Iterable<InputPart> parts) : parts = List.unmodifiable(parts) {
    if (this.parts.isEmpty) throw ArgumentError.value(parts, 'parts', 'must not be empty');
  }

  /// The text content.
  UserMessage.text(String text) : this([TextInputPart(text)]);

  /// The ordered message parts.
  final List<InputPart> parts;

  @override
  JsonObject toJson() => JsonObject({
    'schemaVersion': 1,
    'type': 'user',
    'parts': parts.map((part) => part.toDart()).toList(),
  });
}

/// A model-authored message with optional provider replay data.
final class AssistantMessage extends Message {
  /// Creates an [AssistantMessage].
  AssistantMessage(Iterable<OutputPart> parts, {this.replay}) : parts = List.unmodifiable(parts);

  /// The ordered message parts.
  final List<OutputPart> parts;

  /// Provider data needed for exact same-target replay.
  final ProviderReplay? replay;

  /// The text content.
  String get text => parts.whereType<TextOutputPart>().map((part) => part.text).join();

  @override
  JsonObject toJson() => JsonObject({
    'schemaVersion': 1,
    'type': 'assistant',
    'parts': parts.map((part) => part.toDart()).toList(),
    if (replay case final replay?) 'replay': replay.toJson().toDart(),
  });
}

/// Application tool results returned as a conversation turn.
final class ToolMessage extends Message {
  /// Creates a [ToolMessage].
  ToolMessage(Iterable<ToolResult> results) : results = List.unmodifiable(results) {
    if (this.results.isEmpty) {
      throw ArgumentError.value(results, 'results', 'must not be empty');
    }
  }

  /// The ordered tool results returned to the model.
  final List<ToolResult> results;

  @override
  JsonObject toJson() => JsonObject({
    'schemaVersion': 1,
    'type': 'tool',
    'results': results.map((result) => result.toDart()).toList(),
  });
}

/// One caller input within a message or tool result.
sealed class InputPart {
  const InputPart();

  /// Returns a detached Dart representation.
  Map<String, Object?> toDart();

  /// Creates a validated immutable value from Dart data.
  static InputPart fromDart(Object? value) {
    final map = _object(value, 'input part');
    return switch (_string(map, 'type')) {
      'text' => TextInputPart(_string(map, 'text')),
      'media' => MediaInputPart(
        kind: _enumByName(MediaKind.values, _string(map, 'kind'), 'media kind'),
        mimeType: _string(map, 'mimeType'),
        source: MediaSource.fromDart(map['source']),
      ),
      final type => throw FormatException('Unknown input part type: $type'),
    };
  }
}

/// Text caller input.
final class TextInputPart extends InputPart {
  /// Creates a [TextInputPart].
  TextInputPart(this.text) {
    if (text.isEmpty) throw ArgumentError.value(text, 'text', 'must not be empty');
  }

  /// The text content.
  final String text;

  @override
  Map<String, Object?> toDart() => {'type': 'text', 'text': text};
}

/// Media accepted by common generation and embedding requests.
enum MediaKind {
  /// Image content.
  image,

  /// Audio content.
  audio,

  /// Video content.
  video,

  /// Document content.
  document,
}

/// Media caller input with one explicit source.
final class MediaInputPart extends InputPart {
  /// Creates a [MediaInputPart].
  MediaInputPart({required this.kind, required String mimeType, required this.source})
    : mimeType = _nonEmpty(mimeType, 'mimeType');

  /// The media or part kind.
  final MediaKind kind;

  /// The media MIME type.
  final String mimeType;

  /// The explicit media or upload source.
  final MediaSource source;

  @override
  Map<String, Object?> toDart() => {
    'type': 'media',
    'kind': kind.name,
    'mimeType': mimeType,
    'source': source.toDart(),
  };
}

/// An explicit media source; providers may forward or reject it.
sealed class MediaSource {
  const MediaSource();

  /// Returns a detached Dart representation.
  Map<String, Object?> toDart();

  /// Creates a validated immutable value from Dart data.
  static MediaSource fromDart(Object? value) {
    final map = _object(value, 'media source');
    return switch (_string(map, 'type')) {
      'bytes' => BytesMediaSource(base64Decode(_string(map, 'bytes'))),
      'url' => UrlMediaSource(Uri.parse(_string(map, 'url'))),
      'providerFile' => ProviderFileSource(
        providerId: _string(map, 'providerId'),
        api: _string(map, 'api'),
        reference: _string(map, 'reference'),
        mimeType: _string(map, 'mimeType'),
      ),
      final type => throw FormatException('Unknown media source type: $type'),
    };
  }
}

/// Copied media bytes encoded inline only when a provider supports them.
final class BytesMediaSource extends MediaSource {
  /// Creates a [BytesMediaSource].
  BytesMediaSource(Iterable<int> bytes)
    : bytes = List.unmodifiable(Uint8List.fromList(bytes.toList(growable: false)));

  /// An immutable copy of the source bytes.
  final List<int> bytes;

  @override
  Map<String, Object?> toDart() => {'type': 'bytes', 'bytes': base64Encode(bytes)};
}

/// An absolute native HTTP(S) media URL.
final class UrlMediaSource extends MediaSource {
  /// Creates a [UrlMediaSource].
  UrlMediaSource(this.url) {
    if (!url.isAbsolute || (url.scheme != 'http' && url.scheme != 'https')) {
      throw ArgumentError.value(url, 'url', 'must be an absolute HTTP(S) URL');
    }
  }

  /// The absolute HTTP or HTTPS source URL.
  final Uri url;

  @override
  Map<String, Object?> toDart() => {'type': 'url', 'url': url.toString()};
}

/// A provider-owned file ID or URI.
final class ProviderFileSource extends MediaSource {
  /// Creates a [ProviderFileSource].
  ProviderFileSource({
    required String providerId,
    required String api,
    required String reference,
    required String mimeType,
  }) : providerId = _nonEmpty(providerId, 'providerId'),
       api = _nonEmpty(api, 'api'),
       reference = _nonEmpty(reference, 'reference'),
       mimeType = _nonEmpty(mimeType, 'mimeType');

  /// The stable provider identifier used in diagnostics and replay data.
  final String providerId;

  /// The native API or dialect identifier.
  final String api;

  /// The provider-owned file reference.
  final String reference;

  /// The media MIME type.
  final String mimeType;

  @override
  Map<String, Object?> toDart() => {
    'type': 'providerFile',
    'providerId': providerId,
    'api': api,
    'reference': reference,
    'mimeType': mimeType,
  };
}

/// One model output within an assistant message.
sealed class OutputPart {
  const OutputPart();

  /// Returns a detached Dart representation.
  Map<String, Object?> toDart();

  /// Creates a validated immutable value from Dart data.
  static OutputPart fromDart(Object? value) {
    final map = _object(value, 'output part');
    return switch (_string(map, 'type')) {
      'text' => TextOutputPart(
        _string(map, 'text'),
        citations: _optionalList(map, 'citations').map(Citation.fromDart),
      ),
      'reasoningSummary' => ReasoningSummaryPart(_string(map, 'text')),
      'refusal' => RefusalPart(_string(map, 'text')),
      'applicationToolCall' => ApplicationToolCallPart(
        id: _string(map, 'id'),
        name: _string(map, 'name'),
        arguments: ToolArguments.fromDart(map['arguments']),
      ),
      'providerToolRecord' => ProviderToolRecordPart(
        id: _string(map, 'id'),
        name: _string(map, 'name'),
        owner: _enumByName(
          ToolExecutionOwner.values,
          _string(map, 'owner'),
          'tool execution owner',
        ),
        status: _enumByName(
          ProviderToolStatus.values,
          _string(map, 'status'),
          'provider tool status',
        ),
        details: JsonObject.fromDart(map['details']),
      ),
      'opaque' => OpaqueOutputPart(
        providerId: _string(map, 'providerId'),
        api: _string(map, 'api'),
        kind: _string(map, 'kind'),
        data: JsonObject.fromDart(map['data']),
      ),
      final type => throw FormatException('Unknown output part type: $type'),
    };
  }
}

/// Text output with ordered source citations.
final class TextOutputPart extends OutputPart {
  /// Creates a [TextOutputPart].
  TextOutputPart(this.text, {Iterable<Citation> citations = const []})
    : citations = List.unmodifiable(citations);

  /// The text content.
  final String text;

  /// The ordered citations attached to this text.
  final List<Citation> citations;

  @override
  Map<String, Object?> toDart() => {
    'type': 'text',
    'text': text,
    'citations': citations.map((citation) => citation.toDart()).toList(),
  };
}

/// A provider-supplied reasoning summary, never private reasoning reconstruction.
final class ReasoningSummaryPart extends OutputPart {
  /// Creates a [ReasoningSummaryPart].
  const ReasoningSummaryPart(this.text);

  /// The text content.
  final String text;

  @override
  Map<String, Object?> toDart() => {'type': 'reasoningSummary', 'text': text};
}

/// A provider-supplied refusal.
final class RefusalPart extends OutputPart {
  /// Creates a [RefusalPart].
  const RefusalPart(this.text);

  /// The text content.
  final String text;

  @override
  Map<String, Object?> toDart() => {'type': 'refusal', 'text': text};
}

/// A call that the application owns and may execute.
final class ApplicationToolCallPart extends OutputPart {
  /// Creates an [ApplicationToolCallPart].
  ApplicationToolCallPart({
    required String id,
    required String name,
    required this.arguments,
  }) : id = _nonEmpty(id, 'id'),
       name = _nonEmpty(name, 'name');

  /// The stable identifier.
  final String id;

  /// The declared name.
  final String name;

  /// The tool arguments exactly as supplied by the model.
  final ToolArguments arguments;

  @override
  Map<String, Object?> toDart() => {
    'type': 'applicationToolCall',
    'id': id,
    'name': name,
    'arguments': arguments.toDart(),
  };
}

/// Who executes a provider-defined tool.
enum ToolExecutionOwner {
  /// The caller executes the tool.
  caller,

  /// The provider executes the tool.
  provider,
}

/// Native provider-tool progress.
enum ProviderToolStatus {
  /// Execution has not started.
  pending,

  /// Execution is in progress.
  running,

  /// Execution completed successfully.
  completed,

  /// Execution failed.
  failed,

  /// The provider returned an unrecognized status.
  unknown,
}

/// A native provider-tool record that is not automatically executable.
final class ProviderToolRecordPart extends OutputPart {
  /// Creates a [ProviderToolRecordPart].
  ProviderToolRecordPart({
    required String id,
    required String name,
    required this.owner,
    required this.status,
    required this.details,
  }) : id = _nonEmpty(id, 'id'),
       name = _nonEmpty(name, 'name');

  /// The stable identifier.
  final String id;

  /// The declared name.
  final String name;

  /// The component responsible for executing the tool.
  final ToolExecutionOwner owner;

  /// The provider tool execution status.
  final ProviderToolStatus status;

  /// The retained native error details, when available.
  final JsonObject details;

  @override
  Map<String, Object?> toDart() => {
    'type': 'providerToolRecord',
    'id': id,
    'name': name,
    'owner': owner.name,
    'status': status.name,
    'details': details.toDart(),
  };
}

/// Unknown native content retained for typed inspection by its provider package.
final class OpaqueOutputPart extends OutputPart {
  /// Creates an [OpaqueOutputPart].
  OpaqueOutputPart({
    required String providerId,
    required String api,
    required String kind,
    required this.data,
  }) : providerId = _nonEmpty(providerId, 'providerId'),
       api = _nonEmpty(api, 'api'),
       kind = _nonEmpty(kind, 'kind');

  /// The stable provider identifier used in diagnostics and replay data.
  final String providerId;

  /// The native API or dialect identifier.
  final String api;

  /// The media or part kind.
  final String kind;

  /// The immutable native replay data.
  final JsonObject data;

  @override
  Map<String, Object?> toDart() => {
    'type': 'opaque',
    'providerId': providerId,
    'api': api,
    'kind': kind,
    'data': data.toDart(),
  };
}

/// A citation attached to generated text.
final class Citation {
  /// Creates a [Citation].
  Citation({required this.uri, this.title, this.documentReference, this.nativeMetadata});

  /// Creates a validated immutable value from Dart data.
  factory Citation.fromDart(Object? value) {
    final map = _object(value, 'citation');
    return Citation(
      uri: Uri.parse(_string(map, 'uri')),
      title: map['title'] as String?,
      documentReference: map['documentReference'] as String?,
      nativeMetadata: switch (map['nativeMetadata']) {
        final Map<String, Object?> metadata => JsonObject(metadata),
        _ => null,
      },
    );
  }

  /// The provider-local file URI or identifier.
  final Uri uri;

  /// The citation title, when supplied.
  final String? title;

  /// The provider document reference, when supplied.
  final String? documentReference;

  /// Additional immutable provider citation metadata.
  final JsonObject? nativeMetadata;

  /// Returns a detached Dart representation.
  Map<String, Object?> toDart() => {
    'uri': uri.toString(),
    'title': ?title,
    'documentReference': ?documentReference,
    if (nativeMetadata case final metadata?) 'nativeMetadata': metadata.toDart(),
  };
}

/// Application tool-call arguments without lossy JSON coercion.
sealed class ToolArguments {
  const ToolArguments();

  /// Returns a detached Dart representation.
  Map<String, Object?> toDart();

  /// Serializes this value using schema version 1.
  JsonObject toJson() => JsonObject({'schemaVersion': 1, ...toDart()});

  /// Deserializes and validates a schema-versioned value.
  static ToolArguments fromJson(JsonObject json) => fromDart(_versioned(json));

  /// Creates a validated immutable value from Dart data.
  static ToolArguments fromDart(Object? value) {
    final map = _object(value, 'tool arguments');
    return switch (_string(map, 'type')) {
      'json' => JsonToolArguments(
        JsonObject.fromDart(map['value']),
        originalText: map['originalText'] as String?,
      ),
      'text' => TextToolArguments(_string(map, 'text')),
      'native' => NativeToolArguments(
        providerId: _string(map, 'providerId'),
        api: _string(map, 'api'),
        action: JsonObject.fromDart(map['action']),
      ),
      'malformed' => MalformedToolArguments(
        originalText: _string(map, 'originalText'),
        issue: _string(map, 'issue'),
      ),
      final type => throw FormatException('Unknown tool argument type: $type'),
    };
  }
}

/// Parsed JSON object arguments, retaining original text when available.
final class JsonToolArguments extends ToolArguments {
  /// Creates a [JsonToolArguments].
  const JsonToolArguments(this.value, {this.originalText});

  /// The typed value.
  final JsonObject value;

  /// The original tool-argument text, when available.
  final String? originalText;

  @override
  Map<String, Object?> toDart() => {
    'type': 'json',
    'value': value.toDart(),
    'originalText': ?originalText,
  };
}

/// Declared free-form tool arguments.
final class TextToolArguments extends ToolArguments {
  /// Creates a [TextToolArguments].
  TextToolArguments(String text) : text = _nonEmpty(text, 'text');

  /// The text content.
  final String text;

  @override
  Map<String, Object?> toDart() => {'type': 'text', 'text': text};
}

/// A provider-tagged native tool action.
final class NativeToolArguments extends ToolArguments {
  /// Creates a [NativeToolArguments].
  NativeToolArguments({
    required String providerId,
    required String api,
    required this.action,
  }) : providerId = _nonEmpty(providerId, 'providerId'),
       api = _nonEmpty(api, 'api');

  /// The stable provider identifier used in diagnostics and replay data.
  final String providerId;

  /// The native API or dialect identifier.
  final String api;

  /// The action.
  final JsonObject action;

  @override
  Map<String, Object?> toDart() => {
    'type': 'native',
    'providerId': providerId,
    'api': api,
    'action': action.toDart(),
  };
}

/// Malformed JSON arguments retained with their parse issue.
final class MalformedToolArguments extends ToolArguments {
  /// Creates a [MalformedToolArguments].
  MalformedToolArguments({required this.originalText, required String issue})
    : issue = _nonEmpty(issue, 'issue');

  /// The original tool-argument text, when available.
  final String originalText;

  /// The parse issue that made the arguments malformed.
  final String issue;

  @override
  Map<String, Object?> toDart() => {
    'type': 'malformed',
    'originalText': originalText,
    'issue': issue,
  };
}

/// An application tool result tied to one call ID.
sealed class ToolResult {
  ToolResult(String callId) : callId = _nonEmpty(callId, 'callId');

  /// The application tool-call identifier.
  final String callId;

  /// Returns a detached Dart representation.
  Map<String, Object?> toDart();

  /// Serializes this value using schema version 1.
  JsonObject toJson() => JsonObject({'schemaVersion': 1, ...toDart()});

  /// Deserializes and validates a schema-versioned value.
  static ToolResult fromJson(JsonObject json) => fromDart(_versioned(json));

  /// Creates a validated immutable value from Dart data.
  static ToolResult fromDart(Object? value) {
    final map = _object(value, 'tool result');
    final callId = _string(map, 'callId');
    return switch (_string(map, 'type')) {
      'json' => JsonToolResult(callId: callId, value: JsonValue.fromDart(map['value'])),
      'content' => TextToolResult(
        callId: callId,
        content: _list(map, 'content').map(InputPart.fromDart),
      ),
      'native' => NativeToolResult(
        callId: callId,
        providerId: _string(map, 'providerId'),
        api: _string(map, 'api'),
        value: JsonObject.fromDart(map['value']),
      ),
      'applicationError' => ApplicationErrorToolResult(
        callId: callId,
        message: _string(map, 'message'),
        details: switch (map['details']) {
          final Map<String, Object?> details => JsonObject(details),
          _ => null,
        },
      ),
      final type => throw FormatException('Unknown tool result type: $type'),
    };
  }
}

/// A successful JSON tool result.
final class JsonToolResult extends ToolResult {
  /// Creates a [JsonToolResult].
  JsonToolResult({required String callId, required this.value}) : super(callId);

  /// The typed value.
  final JsonValue value;

  @override
  Map<String, Object?> toDart() => {'type': 'json', 'callId': callId, 'value': value.toDart()};
}

/// A successful ordered text/media tool result.
final class TextToolResult extends ToolResult {
  /// Creates a [TextToolResult].
  TextToolResult({required String callId, required Iterable<InputPart> content})
    : content = List.unmodifiable(content),
      super(callId) {
    if (this.content.isEmpty) {
      throw ArgumentError.value(content, 'content', 'must not be empty');
    }
  }

  /// The ordered content.
  final List<InputPart> content;

  @override
  Map<String, Object?> toDart() => {
    'type': 'content',
    'callId': callId,
    'content': content.map((part) => part.toDart()).toList(),
  };
}

/// A successful provider-tagged native action result.
final class NativeToolResult extends ToolResult {
  /// Creates a [NativeToolResult].
  NativeToolResult({
    required String callId,
    required String providerId,
    required String api,
    required this.value,
  }) : providerId = _nonEmpty(providerId, 'providerId'),
       api = _nonEmpty(api, 'api'),
       super(callId);

  /// The stable provider identifier used in diagnostics and replay data.
  final String providerId;

  /// The native API or dialect identifier.
  final String api;

  /// The typed value.
  final JsonObject value;

  @override
  Map<String, Object?> toDart() => {
    'type': 'native',
    'callId': callId,
    'providerId': providerId,
    'api': api,
    'value': value.toDart(),
  };
}

/// A declared application-level tool failure.
final class ApplicationErrorToolResult extends ToolResult {
  /// Creates an [ApplicationErrorToolResult].
  ApplicationErrorToolResult({
    required String callId,
    required String message,
    this.details,
  }) : message = _nonEmpty(message, 'message'),
       super(callId);

  /// The human-readable failure or result message.
  final String message;

  /// The retained native error details, when available.
  final JsonObject? details;

  @override
  Map<String, Object?> toDart() => {
    'type': 'applicationError',
    'callId': callId,
    'message': message,
    if (details case final details?) 'details': details.toDart(),
  };
}

/// Provider data required to submit a returned assistant message exactly.
final class ProviderReplay {
  /// Creates a [ProviderReplay].
  ProviderReplay({
    required String providerId,
    required String api,
    required String modelId,
    required Iterable<ReplayItem> items,
  }) : providerId = _nonEmpty(providerId, 'providerId'),
       api = _nonEmpty(api, 'api'),
       modelId = _nonEmpty(modelId, 'modelId'),
       items = List.unmodifiable(items);

  /// Deserializes and validates a schema-versioned value.
  factory ProviderReplay.fromJson(JsonObject json) {
    final value = _versioned(json);
    return ProviderReplay(
      providerId: _string(value, 'providerId'),
      api: _string(value, 'api'),
      modelId: _string(value, 'modelId'),
      items: _list(value, 'items').map(ReplayItem.fromDart),
    );
  }

  /// The stable provider identifier used in diagnostics and replay data.
  final String providerId;

  /// The native API or dialect identifier.
  final String api;

  /// The provider-local model identifier.
  final String modelId;

  /// The immutable ordered items.
  final List<ReplayItem> items;

  /// Serializes this value using schema version 1.
  JsonObject toJson() => JsonObject({
    'schemaVersion': 1,
    'providerId': providerId,
    'api': api,
    'modelId': modelId,
    'items': items.map((item) => item.toDart()).toList(),
  });
}

/// One ordered native replay item or block.
final class ReplayItem {
  /// Creates a [ReplayItem].
  ReplayItem({required this.data, this.id, this.phase});

  /// Creates a validated immutable value from Dart data.
  factory ReplayItem.fromDart(Object? value) {
    final map = _object(value, 'replay item');
    return ReplayItem(
      id: map['id'] as String?,
      phase: map['phase'] as String?,
      data: JsonObject.fromDart(map['data']),
    );
  }

  /// The stable identifier.
  final String? id;

  /// The provider-defined replay phase.
  final String? phase;

  /// The immutable native replay data.
  final JsonObject data;

  /// Returns a detached Dart representation.
  Map<String, Object?> toDart() => {
    'id': ?id,
    'phase': ?phase,
    'data': data.toDart(),
  };
}

Map<String, Object?> _versioned(JsonObject json) {
  final value = json.toDart();
  if (value['schemaVersion'] != 1) {
    throw FormatException('Unsupported schema version: ${value['schemaVersion']}');
  }
  return value;
}

Map<String, Object?> _object(Object? value, String name) {
  if (value is! Map<String, Object?>) throw FormatException('$name must be an object.');
  return value;
}

String _string(Map<String, Object?> value, String key) {
  final field = value[key];
  if (field is! String) throw FormatException('$key must be a string.');
  return field;
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

T _enumByName<T extends Enum>(List<T> values, String name, String kind) {
  for (final value in values) {
    if (value.name == name) return value;
  }
  throw FormatException('Unknown $kind: $name');
}

String _nonEmpty(String value, String name) {
  if (value.isEmpty) throw ArgumentError.value(value, name, 'must not be empty');
  return value;
}
