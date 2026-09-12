import 'dart:convert';

import 'package:artificer_core/artificer_core.dart';
import 'package:artificer_core/json.dart';
import 'package:artificer_core/protocols.dart';
import 'package:artificer_core/transport.dart';
import 'package:artificer_xai/src/responses/lifecycle_models.dart';
import 'package:artificer_xai/src/responses/response_models.dart';
import 'package:conflux/conflux.dart';

const _providerId = 'xai';
const _api = 'responses';

/// Typed native Responses operations and common normalization.
final class XaiResponsesResource {
  /// Creates the resource over one provider-owned core client.
  const XaiResponsesResource(this._client);

  final ProviderHttpClient _client;

  /// Creates one ordinary response.
  Effect<NativeResponse<XaiResponse>, AiError> create(XaiResponseRequest request) {
    final body = _encode(request, stream: false);
    return _client
        .sendJson(
          ProviderHttpRequest(method: 'POST', path: 'responses', body: body),
          providerId: _providerId,
          api: _api,
          modelId: request.model,
        )
        .flatMap(_decode);
  }

  /// Retrieves one stored response without polling.
  Effect<NativeResponse<XaiResponse>, AiError> retrieve(String responseId) => _responseCall(
    method: 'GET',
    path: 'responses/${Uri.encodeComponent(_nonEmpty(responseId, 'responseId'))}',
  );

  /// Explicitly deletes one stored response.
  Effect<NativeResponse<XaiDeletedResponse>, AiError> delete(String responseId) {
    final id = _nonEmpty(responseId, 'responseId');
    return _client
        .sendJson(
          ProviderHttpRequest(method: 'DELETE', path: 'responses/${Uri.encodeComponent(id)}'),
          providerId: _providerId,
          api: _api,
          modelId: 'responses',
        )
        .flatMap((response) => _decodeTyped(response, XaiDeletedResponse.fromJson));
  }

  /// Lists one input-item page without following its cursor.
  Effect<NativeResponse<XaiResponseInputItemPage>, AiError> listInputItems(
    String responseId, {
    int? limit,
    XaiListOrder? order,
    String? after,
  }) {
    final id = _nonEmpty(responseId, 'responseId');
    if (limit != null && (limit < 1 || limit > 100)) {
      throw ArgumentError.value(limit, 'limit', 'must be between 1 and 100');
    }
    final query = <String, Object?>{
      if (limit != null) 'limit': '$limit',
      if (order != null) 'order': order.wireValue,
      if (after != null) 'after': _nonEmpty(after, 'after'),
    };
    final path = Uri(
      path: 'responses/${Uri.encodeComponent(id)}/input_items',
      queryParameters: query.isEmpty ? null : query,
    ).toString();
    return _client
        .sendJson(
          ProviderHttpRequest(method: 'GET', path: path),
          providerId: _providerId,
          api: _api,
          modelId: 'responses',
        )
        .flatMap((response) => _decodeTyped(response, XaiResponseInputItemPage.fromJson));
  }

  /// Compacts one explicit native input without storing hidden client state.
  Effect<NativeResponse<XaiCompactResponse>, AiError> compact(
    XaiCompactResponseRequest request,
  ) => _client
      .sendJson(
        ProviderHttpRequest(method: 'POST', path: 'responses/compact', body: request.toJson()),
        providerId: _providerId,
        api: _api,
        modelId: request.model,
      )
      .flatMap((response) => _decodeTyped(response, XaiCompactResponse.fromJson));

  /// Streams typed native Responses events.
  Flow<XaiResponseEvent, AiError> stream(
    XaiResponseRequest request, {
    int decodedEventCapacity = 16,
    int maxEventBytes = 8 * 1024 * 1024,
    int? maxStreamBytes,
  }) {
    final body = _encode(request, stream: true);
    return _client.sendSse(
      ProviderHttpRequest(method: 'POST', path: 'responses', body: body),
      createProtocol: _XaiNativeResponsesProtocol.new,
      decodedEventCapacity: decodedEventCapacity,
      maxEventBytes: maxEventBytes,
      maxStreamBytes: maxStreamBytes,
    );
  }

  /// Streams common events from the same Responses wire decoder.
  Flow<GenerationEvent, AiError> streamCommon(
    XaiResponseRequest request, {
    int decodedEventCapacity = 16,
    int maxEventBytes = 8 * 1024 * 1024,
    int? maxStreamBytes,
    int maxAssembledBytes = 64 * 1024 * 1024,
  }) {
    final body = _encode(request, stream: true);
    return _client.sendSse(
      ProviderHttpRequest(method: 'POST', path: 'responses', body: body),
      createProtocol: () => _XaiCommonResponsesProtocol(
        request.model,
        maxAssembledBytes: maxAssembledBytes,
      ),
      decodedEventCapacity: decodedEventCapacity,
      maxEventBytes: maxEventBytes,
      maxStreamBytes: maxStreamBytes,
    );
  }

  /// Normalizes an already-decoded native response without issuing I/O.
  GenerationResult normalize(NativeResponse<XaiResponse> response) {
    final value = response.value;
    final parts = _normalizedParts(value).map((entry) => entry.$2);
    final usage = value.usage;
    return GenerationResult(
      message: AssistantMessage(
        parts,
        replay: ProviderReplay(
          providerId: _providerId,
          api: _api,
          modelId: response.payload.modelId,
          items: [
            for (final item in value.output)
              ReplayItem(
                id: item.id,
                phase: _optionalExtensionString(item.extensions, 'phase'),
                data: item.raw,
              ),
          ],
        ),
      ),
      finishReason: _finishReason(value),
      nativeFinishReason: value.status.name,
      usage: usage == null
          ? null
          : Usage(
              inputTokens: usage.inputTokens,
              outputTokens: usage.outputTokens,
              totalTokens: usage.totalTokens,
            ),
      responseId: value.id,
      requestId: response.metadata.requestId,
      nativePayload: response.payload,
      metadata: response.metadata,
    );
  }

  JsonObject _encode(XaiResponseRequest request, {required bool stream}) =>
      JsonObject({...request.toJson().toDart(), 'stream': stream});

  Effect<NativeResponse<XaiResponse>, AiError> _decode(NativeResponse<JsonObject> response) {
    try {
      final value = XaiResponse.fromJson(response.value);
      if (value.status == XaiResponseStatus.failed) {
        final error = value.raw.toDart()['error'];
        final details = error is Map<String, Object?> ? JsonObject(error) : value.raw;
        return Effect.fail(
          ProviderError(
            error is Map<String, Object?> && error['message'] is String
                ? error['message']! as String
                : 'Xai response failed.',
            code: error is Map<String, Object?> && error['code'] is String
                ? error['code']! as String
                : null,
            details: details,
            requestId: response.metadata.requestId,
          ),
        );
      }
      return Effect.succeed(
        NativeResponse(
          value: value,
          payload: response.payload,
          metadata: response.metadata,
        ),
      );
    } on FormatException catch (error) {
      return Effect.fail(ProtocolError(error.message));
    }
  }

  Effect<NativeResponse<XaiResponse>, AiError> _responseCall({
    required String method,
    required String path,
  }) => _client
      .sendJson(
        ProviderHttpRequest(method: method, path: path),
        providerId: _providerId,
        api: _api,
        modelId: 'responses',
      )
      .flatMap(_decode);
}

Effect<NativeResponse<T>, AiError> _decodeTyped<T>(
  NativeResponse<JsonObject> response,
  T Function(JsonObject) decode,
) {
  try {
    return Effect.succeed(
      NativeResponse(
        value: decode(response.value),
        payload: response.payload,
        metadata: response.metadata,
      ),
    );
  } on FormatException catch (error) {
    return Effect.fail(ProtocolError(error.message));
  }
}

/// One typed native Responses stream event.
sealed class XaiResponseEvent {
  XaiResponseEvent({required this.type, required this.raw, required this.extensions});

  /// Decodes an event from its complete JSON payload.
  factory XaiResponseEvent.fromJson(JsonObject raw) {
    final value = raw.toDart();
    final type = _string(value, 'type');
    final extensions = JsonObject(
      _without(value, {
        'type',
        'response',
        'delta',
        'output_index',
        'content_index',
        'summary_index',
      }),
    );
    return switch (type) {
      'response.created' => XaiResponseCreatedEvent._(
        response: XaiResponse.fromJson(_jsonObject(value['response'], 'response')),
        raw: raw,
        extensions: extensions,
      ),
      'response.output_text.delta' => XaiResponseTextDeltaEvent._(
        outputIndex: _integer(value, 'output_index'),
        contentIndex: _integer(value, 'content_index'),
        delta: _string(value, 'delta'),
        raw: raw,
        extensions: extensions,
      ),
      'response.refusal.delta' => XaiResponseRefusalDeltaEvent._(
        outputIndex: _integer(value, 'output_index'),
        contentIndex: _integer(value, 'content_index'),
        delta: _string(value, 'delta'),
        raw: raw,
        extensions: extensions,
      ),
      'response.reasoning_summary_text.delta' => XaiResponseReasoningDeltaEvent._(
        outputIndex: _integer(value, 'output_index'),
        summaryIndex: _integer(value, 'summary_index'),
        delta: _string(value, 'delta'),
        raw: raw,
        extensions: extensions,
      ),
      'response.function_call_arguments.delta' ||
      'response.custom_tool_call_input.delta' => XaiResponseToolArgumentsDeltaEvent._(
        type: type,
        outputIndex: _integer(value, 'output_index'),
        delta: _string(value, 'delta'),
        raw: raw,
        extensions: extensions,
      ),
      'response.completed' || 'response.incomplete' => XaiResponseCompletedEvent._(
        type: type,
        response: XaiResponse.fromJson(_jsonObject(value['response'], 'response')),
        raw: raw,
        extensions: extensions,
      ),
      _ => XaiUnknownResponseEvent._(type: type, raw: raw, extensions: extensions),
    };
  }

  /// Native event type.
  final String type;

  /// Complete native event JSON.
  final JsonObject raw;

  /// Fields outside this event's typed members.
  final JsonObject extensions;
}

/// The initial native response state.
final class XaiResponseCreatedEvent extends XaiResponseEvent {
  XaiResponseCreatedEvent._({
    required this.response,
    required super.raw,
    required super.extensions,
  }) : super(type: 'response.created');

  /// The created response.
  final XaiResponse response;
}

/// One visible text delta.
final class XaiResponseTextDeltaEvent extends XaiResponseEvent {
  XaiResponseTextDeltaEvent._({
    required this.outputIndex,
    required this.contentIndex,
    required this.delta,
    required super.raw,
    required super.extensions,
  }) : super(type: 'response.output_text.delta');

  /// New visible text.
  final String delta;

  /// Position of the output item in the terminal response.
  final int outputIndex;

  /// Position of the content item in the output message.
  final int contentIndex;
}

/// One refusal text delta.
final class XaiResponseRefusalDeltaEvent extends XaiResponseEvent {
  XaiResponseRefusalDeltaEvent._({
    required this.outputIndex,
    required this.contentIndex,
    required this.delta,
    required super.raw,
    required super.extensions,
  }) : super(type: 'response.refusal.delta');

  /// Position of the output item in the terminal response.
  final int outputIndex;

  /// Position of the content item in the output message.
  final int contentIndex;

  /// New refusal text.
  final String delta;
}

/// One reasoning summary text delta.
final class XaiResponseReasoningDeltaEvent extends XaiResponseEvent {
  XaiResponseReasoningDeltaEvent._({
    required this.outputIndex,
    required this.summaryIndex,
    required this.delta,
    required super.raw,
    required super.extensions,
  }) : super(type: 'response.reasoning_summary_text.delta');

  /// Position of the reasoning item in the terminal response.
  final int outputIndex;

  /// Position of the summary in the reasoning item.
  final int summaryIndex;

  /// New reasoning summary text.
  final String delta;
}

/// One function or custom tool input delta.
final class XaiResponseToolArgumentsDeltaEvent extends XaiResponseEvent {
  XaiResponseToolArgumentsDeltaEvent._({
    required super.type,
    required this.outputIndex,
    required this.delta,
    required super.raw,
    required super.extensions,
  });

  /// Position of the tool item in the terminal response.
  final int outputIndex;

  /// New tool input text.
  final String delta;
}

/// A successful or incomplete terminal response event.
final class XaiResponseCompletedEvent extends XaiResponseEvent {
  XaiResponseCompletedEvent._({
    required super.type,
    required this.response,
    required super.raw,
    required super.extensions,
  });

  /// The terminal response.
  final XaiResponse response;
}

/// An event outside the typed snapshot, retained without loss.
final class XaiUnknownResponseEvent extends XaiResponseEvent {
  XaiUnknownResponseEvent._({
    required super.type,
    required super.raw,
    required super.extensions,
  });
}

final class _XaiNativeResponsesProtocol implements SseProtocol<XaiResponseEvent> {
  var _terminal = false;

  @override
  bool get isTerminal => _terminal;

  @override
  Object? get partialOutput => null;

  @override
  Iterable<XaiResponseEvent> start(ResponseMetadata metadata) => const [];

  @override
  Iterable<XaiResponseEvent> decode(SseEvent event) {
    final decoded = _decodeEvent(event);
    if (decoded.type == 'response.failed' || decoded.type == 'error') {
      throw _streamError(decoded);
    }
    if (decoded is XaiResponseCompletedEvent) _terminal = true;
    return [decoded];
  }

  @override
  Iterable<XaiResponseEvent> finish() {
    if (!_terminal) throw const ProtocolError('Responses stream ended before a terminal event.');
    return const [];
  }
}

final class _XaiCommonResponsesProtocol implements SseProtocol<GenerationEvent> {
  _XaiCommonResponsesProtocol(
    this.modelId, {
    required int maxAssembledBytes,
  }) : assembler = GenerationStreamAssembler(
         providerId: _providerId,
         api: _api,
         modelId: modelId,
         maxAssembledBytes: maxAssembledBytes,
       );

  final String modelId;
  final GenerationStreamAssembler assembler;
  final Map<int, GenerationPartKind> _started = {};
  final List<ReplayItem> _unknownEvents = [];
  var _unknownEventBytes = 0;
  var _terminal = false;
  XaiResponse? _lastTerminal;

  @override
  bool get isTerminal => _terminal;

  @override
  Object? get partialOutput => assembler.partialMessage;

  @override
  Iterable<GenerationEvent> start(ResponseMetadata metadata) => [assembler.start(metadata)];

  @override
  Iterable<GenerationEvent> decode(SseEvent event) sync* {
    final decoded = _decodeEvent(event);
    switch (decoded) {
      case XaiResponseCreatedEvent(:final response):
        assembler.setResponseId(response.id);
      case XaiResponseTextDeltaEvent(
        :final outputIndex,
        :final contentIndex,
        :final delta,
      ):
        yield* _append(
          _partIndex(outputIndex, contentIndex),
          GenerationPartKind.text,
          delta,
        );
      case XaiResponseRefusalDeltaEvent(
        :final outputIndex,
        :final contentIndex,
        :final delta,
      ):
        yield* _append(
          _partIndex(outputIndex, contentIndex),
          GenerationPartKind.refusal,
          delta,
        );
      case XaiResponseReasoningDeltaEvent(
        :final outputIndex,
        :final summaryIndex,
        :final delta,
      ):
        yield* _append(
          _partIndex(outputIndex, summaryIndex),
          GenerationPartKind.reasoning,
          delta,
        );
      case XaiResponseToolArgumentsDeltaEvent(:final outputIndex, :final delta):
        yield* _append(
          _partIndex(outputIndex, 0),
          GenerationPartKind.applicationToolCall,
          delta,
        );
      case XaiResponseCompletedEvent(:final response):
        _terminal = true;
        _lastTerminal = response;
      case XaiUnknownResponseEvent():
        if (decoded.type == 'response.failed' || decoded.type == 'error') {
          throw _streamError(decoded, partialOutput: assembler.partialMessage);
        }
        _unknownEventBytes += utf8.encode(decoded.raw.encode()).length;
        if (_unknownEventBytes > assembler.maxAssembledBytes) {
          throw ResponseLimitError(
            'Retained unknown events exceeded the configured byte limit.',
            limit: assembler.maxAssembledBytes,
            actual: _unknownEventBytes,
            partialOutput: assembler.partialMessage,
          );
        }
        _unknownEvents.add(ReplayItem(phase: 'unknown-event', data: decoded.raw));
        yield assembler.providerEvent(decoded.type, decoded.raw);
    }
  }

  @override
  Iterable<GenerationEvent> finish() sync* {
    if (!_terminal) {
      throw ProtocolError(
        'Responses stream ended before a terminal event.',
        partialOutput: assembler.partialMessage,
      );
    }
    final terminal = _lastTerminal;
    if (terminal == null) throw const ProtocolError('Responses terminal payload was not retained.');
    final normalizedParts = _normalizedParts(terminal);
    final terminalIndexes = normalizedParts.map((entry) => entry.$1).toSet();
    final missing = _started.keys.where((index) => !terminalIndexes.contains(index)).toList();
    if (missing.isNotEmpty) {
      throw ProtocolError(
        'Responses terminal payload omitted streamed parts ${missing.join(', ')}.',
        partialOutput: assembler.partialMessage,
      );
    }
    for (final (index, part) in normalizedParts) {
      final kind = _partKind(part);
      final startedKind = _started[index];
      if (startedKind == null) {
        _started[index] = kind;
        yield assembler.startPart(index: index, kind: kind, owner: _partOwner(part));
      } else if (startedKind != kind) {
        throw ProtocolError(
          'Responses part $index changed from ${startedKind.name} to ${kind.name}.',
          partialOutput: assembler.partialMessage,
        );
      }
      yield assembler.finishPart(index, part);
    }
    if (terminal.usage case final usage?) {
      yield assembler.updateUsage(
        Usage(
          inputTokens: usage.inputTokens,
          outputTokens: usage.outputTokens,
          totalTokens: usage.totalTokens,
        ),
      );
    }
    yield assembler.finish(
      finishReason: _finishReason(terminal),
      nativeFinishReason: terminal.status.name,
      nativeResponse: terminal.raw,
      replay: [
        for (final item in terminal.output)
          ReplayItem(
            id: item.id,
            phase: _optionalExtensionString(item.extensions, 'phase'),
            data: item.raw,
          ),
        ..._unknownEvents,
      ],
    );
  }

  Iterable<GenerationEvent> _append(
    int index,
    GenerationPartKind kind,
    String delta,
  ) sync* {
    final existingKind = _started[index];
    if (existingKind == null) {
      _started[index] = kind;
      yield assembler.startPart(index: index, kind: kind);
    } else if (existingKind != kind) {
      throw ProtocolError(
        'Responses part $index changed from ${existingKind.name} to ${kind.name}.',
        partialOutput: assembler.partialMessage,
      );
    }
    yield assembler.appendText(index, delta);
  }
}

XaiResponseEvent _decodeEvent(SseEvent event) {
  try {
    return XaiResponseEvent.fromJson(JsonObject.parse(event.data));
  } on FormatException catch (error) {
    throw ProtocolError(error.message);
  }
}

FinishReason _finishReason(XaiResponse response) {
  if (response.status == XaiResponseStatus.incomplete) {
    final details = response.raw.toDart()['incomplete_details'];
    if (details is Map<String, Object?>) {
      return switch (details['reason']) {
        'max_output_tokens' || 'max_messages' => FinishReason.outputLimit,
        'content_filter' => FinishReason.contentFilter,
        _ => FinishReason.other,
      };
    }
  }
  if (response.output
      .whereType<XaiResponseMessageItem>()
      .expand((item) => item.content)
      .any((part) => part is XaiRefusalContent)) {
    return FinishReason.refusal;
  }
  if (response.output.any((item) => item is XaiCallerToolOutputItem)) {
    return FinishReason.toolCalls;
  }
  return FinishReason.stop;
}

List<(int, OutputPart)> _normalizedParts(XaiResponse response) {
  final parts = <(int, OutputPart)>[];
  for (var outputIndex = 0; outputIndex < response.output.length; outputIndex++) {
    final item = response.output[outputIndex];
    if (item case XaiResponseMessageItem(:final content)) {
      for (var contentIndex = 0; contentIndex < content.length; contentIndex++) {
        final contentPart = content[contentIndex];
        final part = switch (contentPart) {
          XaiOutputTextContent(:final text) => TextOutputPart(
            text,
            citations: _citations(contentPart),
          ),
          XaiRefusalContent(:final refusal) => RefusalPart(refusal),
          XaiUnknownOutputContent() => OpaqueOutputPart(
            providerId: _providerId,
            api: _api,
            kind: contentPart.type,
            data: contentPart.raw,
          ),
        };
        parts.add((_partIndex(outputIndex, contentIndex), part));
      }
    } else if (item case XaiReasoningOutputItem(:final summaries)) {
      if (summaries.isEmpty) {
        parts.add(
          (
            _partIndex(outputIndex, 0),
            OpaqueOutputPart(
              providerId: _providerId,
              api: _api,
              kind: item.type,
              data: item.raw,
            ),
          ),
        );
      } else {
        for (var summaryIndex = 0; summaryIndex < summaries.length; summaryIndex++) {
          parts.add(
            (
              _partIndex(outputIndex, summaryIndex),
              ReasoningSummaryPart(summaries[summaryIndex]),
            ),
          );
        }
      }
    } else if (item case XaiCallerToolOutputItem()) {
      parts.add(
        (
          _partIndex(outputIndex, 0),
          ApplicationToolCallPart(
            id: item.callId,
            name: item.name,
            arguments: _toolArguments(item),
          ),
        ),
      );
    } else if (item case XaiProviderToolOutputItem()) {
      parts.add(
        (
          _partIndex(outputIndex, 0),
          ProviderToolRecordPart(
            id: item.id ?? item.type,
            name: item.type.replaceFirst('_call', ''),
            owner: ToolExecutionOwner.provider,
            status: _providerToolStatus(item.status),
            details: item.raw,
          ),
        ),
      );
    } else {
      parts.add(
        (
          _partIndex(outputIndex, 0),
          OpaqueOutputPart(
            providerId: _providerId,
            api: _api,
            kind: item.type,
            data: item.raw,
          ),
        ),
      );
    }
  }
  return parts;
}

int _partIndex(int outputIndex, int nestedIndex) => outputIndex * 1000 + nestedIndex;

GenerationPartKind _partKind(OutputPart part) => switch (part) {
  TextOutputPart() => GenerationPartKind.text,
  RefusalPart() => GenerationPartKind.refusal,
  ReasoningSummaryPart() => GenerationPartKind.reasoning,
  ApplicationToolCallPart() => GenerationPartKind.applicationToolCall,
  ProviderToolRecordPart() => GenerationPartKind.providerTool,
  OpaqueOutputPart() => GenerationPartKind.opaque,
};

GenerationPartOwner _partOwner(OutputPart part) => switch (part) {
  ProviderToolRecordPart() || OpaqueOutputPart() => GenerationPartOwner.provider,
  _ => GenerationPartOwner.application,
};

Iterable<Citation> _citations(XaiOutputTextContent part) sync* {
  final annotations = part.raw.toDart()['annotations'];
  if (annotations is! List<Object?>) return;
  for (final annotation in annotations) {
    if (annotation is! Map<String, Object?>) continue;
    final url = annotation['url'];
    if (url is! String) continue;
    final uri = Uri.tryParse(url);
    if (uri == null) continue;
    yield Citation(
      uri: uri,
      title: switch (annotation['title']) {
        final String title => title,
        _ => null,
      },
      documentReference: switch (annotation['file_id']) {
        final String fileId => fileId,
        _ => null,
      },
      nativeMetadata: JsonObject(annotation),
    );
  }
}

ProviderError _streamError(XaiResponseEvent event, {Object? partialOutput}) {
  final raw = event.raw.toDart();
  final error = switch (event.type) {
    'response.failed' => switch (raw['response']) {
      final Map<String, Object?> response => response['error'],
      _ => null,
    },
    _ => raw,
  };
  final fields = error is Map<String, Object?> ? error : const <String, Object?>{};
  return ProviderError(
    fields['message'] is String ? fields['message']! as String : 'Xai reported a streaming error.',
    code: fields['code'] is String ? fields['code']! as String : null,
    details: event.raw,
    partialOutput: partialOutput,
  );
}

String? _optionalExtensionString(JsonObject extensions, String key) =>
    switch (extensions.toDart()[key]) {
      final String value => value,
      _ => null,
    };

ToolArguments _toolArguments(XaiCallerToolOutputItem item) {
  if (item.type == 'custom_tool_call') return TextToolArguments(item.input);
  if (item.type != 'function_call') {
    return NativeToolArguments(
      providerId: _providerId,
      api: _api,
      action: item.extensions,
    );
  }
  try {
    return JsonToolArguments(JsonObject.parse(item.input), originalText: item.input);
  } on FormatException catch (error) {
    return MalformedToolArguments(originalText: item.input, issue: error.message);
  }
}

ProviderToolStatus _providerToolStatus(String? status) => switch (status) {
  'pending' => ProviderToolStatus.pending,
  'in_progress' || 'searching' || 'interpreting' => ProviderToolStatus.running,
  'completed' => ProviderToolStatus.completed,
  'failed' => ProviderToolStatus.failed,
  _ => ProviderToolStatus.unknown,
};

String _string(Map<String, Object?> value, String key) {
  final field = value[key];
  if (field is! String) throw FormatException('$key must be a string.');
  return field;
}

int _integer(Map<String, Object?> value, String key) {
  final field = value[key];
  if (field is! int) throw FormatException('$key must be an integer.');
  return field;
}

JsonObject _jsonObject(Object? value, String name) {
  if (value is! Map<String, Object?>) throw FormatException('$name must be an object.');
  return JsonObject(value);
}

String _nonEmpty(String value, String name) {
  if (value.isEmpty) throw ArgumentError.value(value, name, 'must not be empty');
  return value;
}

Map<String, Object?> _without(Map<String, Object?> value, Set<String> keys) =>
    Map.fromEntries(value.entries.where((entry) => !keys.contains(entry.key)));
