import 'dart:convert';

import 'package:artificer_core/src/errors.dart';
import 'package:artificer_core/src/generation/generation.dart';
import 'package:artificer_core/src/json/json_value.dart';
import 'package:artificer_core/src/messages/messages.dart';
import 'package:artificer_core/src/native.dart';
import 'package:artificer_core/src/protocols/generation_assembler.dart';
import 'package:artificer_core/src/protocols/responses/responses_codec.dart';
import 'package:artificer_core/src/protocols/sse.dart';
import 'package:conflux/result.dart';

/// Execution-local translation of Responses events into bounded common output.
/// Native terminal snapshots remain authoritative; EOF alone never succeeds.
final class ResponsesStreamDecoder {
  /// Creates fresh decoder state without retaining known event history.
  ResponsesStreamDecoder({
    required this.codec,
    required this.modelId,
    required this.maxResponseBytes,
  }) : _assembler = GenerationAssembler(maxResponseBytes: maxResponseBytes);

  /// Provider-owned normalization and native event aliases.
  final ResponsesCodec codec;

  /// Request target used for replay compatibility.
  final String modelId;

  /// Bound on the terminal native snapshot as well as common assembly.
  final int maxResponseBytes;

  /// HTTP metadata supplied when the response begins.
  ResponseMetadata? metadata;
  final GenerationAssembler _assembler;
  final Map<String, GenerationPartKind> _parts = {};
  final Set<String> _finished = {};
  GenerationResult? _final;
  AiError? _failure;

  /// Whether a valid terminal response snapshot has been received.
  bool get terminal => _final != null;

  /// Begins the normalized stream after valid response headers.
  Result<GenerationEvent, AiError> start() =>
      _assembler.add(GenerationStarted(requestId: metadata?.requestId));

  /// Translates one event; interleaved native indices retain stable local IDs.
  Result<List<GenerationEvent>, AiError> add(SseEvent frame) {
    if (_failure case final error?) return Failure(error);
    if (_final != null) {
      return _fail(const ProtocolError('Native event arrived after terminal response.'));
    }
    final events = <GenerationEvent>[];
    try {
      final Object? decoded;
      try {
        decoded = jsonDecode(frame.data);
        JsonValues.validate(decoded);
      } on FormatException {
        return _malformed();
      }
      if (decoded is! Map<String, Object?>) throw const _MalformedEvent('Expected event object.');
      final nativeType = decoded['type'] ?? frame.event;
      if (nativeType is! String) throw const _MalformedEvent('Missing event type.');
      final type = codec.dialect.eventAliases[nativeType] ?? nativeType;
      final nativeError = codec.errorFrom(decoded, metadata: metadata);
      if (nativeError != null) return _fail(withPartial(nativeError));
      if (type == 'error' || type == 'response.failed') {
        final response = decoded['response'];
        final error = response is Map<String, Object?>
            ? codec.errorFrom(response, metadata: metadata)
            : null;
        return _fail(
          withPartial(
            error ??
                ProviderError(
                  'Responses stream failed.',
                  details: decoded,
                  statusCode: metadata?.statusCode,
                  requestId: metadata?.requestId,
                ),
          ),
        );
      }
      switch (type) {
        case 'response.created':
        case 'response.in_progress':
          break;
        case 'response.output_item.added':
          final item = _object(decoded['item']);
          if (item['type'] == 'function_call' || item['type'] == 'custom_tool_call') {
            _start(
              events,
              _index(decoded, 'output_index'),
              0,
              GenerationPartKind.toolCall,
              callId: item['call_id'] is String && (item['call_id']! as String).isNotEmpty
                  ? item['call_id']! as String
                  : null,
              name: item['name'] is String && (item['name']! as String).isNotEmpty
                  ? item['name']! as String
                  : null,
              owner: ToolExecutionOwner.application,
            );
          }
        case 'response.output_text.delta':
        case 'response.reasoning_summary_text.delta':
        case 'response.function_call_arguments.delta':
        case 'response.custom_tool_call_input.delta':
          final oi = _index(decoded, 'output_index');
          final ci = type == 'response.reasoning_summary_text.delta'
              ? _index(decoded, 'summary_index', optional: true)
              : _index(decoded, 'content_index', optional: true);
          final kind = type == 'response.output_text.delta'
              ? GenerationPartKind.text
              : type == 'response.reasoning_summary_text.delta'
              ? GenerationPartKind.reasoning
              : GenerationPartKind.toolCall;
          final id = _start(
            events,
            oi,
            ci,
            kind,
            owner: kind == GenerationPartKind.toolCall ? ToolExecutionOwner.application : null,
          );
          final text = decoded['delta'];
          if (text is! String) throw const _MalformedEvent('Delta must be text.');
          _emit(
            events,
            PartDelta(
              id: id,
              delta: switch (kind) {
                GenerationPartKind.text => TextDelta(text: text),
                GenerationPartKind.reasoning => ReasoningDelta(text: text),
                _ => ToolArgumentsDelta(text: text),
              },
            ),
          );
        case 'response.content_part.added':
        case 'response.reasoning_summary_part.added':
          final part = _object(decoded['part']);
          final oi = _index(decoded, 'output_index');
          final ci = _index(
            decoded,
            type == 'response.content_part.added' ? 'content_index' : 'summary_index',
            optional: true,
          );
          if (part['type'] == 'output_text' || part['type'] == 'summary_text') {
            final kind = part['type'] == 'output_text'
                ? GenerationPartKind.text
                : GenerationPartKind.reasoning;
            final id = _start(events, oi, ci, kind);
            final prefix = part['text'];
            if (prefix is String && prefix.isNotEmpty) {
              _emit(
                events,
                PartDelta(
                  id: id,
                  delta: kind == GenerationPartKind.text
                      ? TextDelta(text: prefix)
                      : ReasoningDelta(text: prefix),
                ),
              );
            }
          }
        case 'response.output_item.done':
          // Terminal output supplies late metadata; avoid retaining item snapshots.
          _object(decoded['item']);
        case 'response.output_text.done':
        case 'response.function_call_arguments.done':
        case 'response.custom_tool_call_input.done':
        case 'response.reasoning_summary_text.done':
        case 'response.content_part.done':
        case 'response.reasoning_summary_part.done':
          // The item snapshot carries late citations and tool identity together.
          break;
        case 'response.completed':
        case 'response.incomplete':
          final response = _object(decoded['response']);
          if (utf8.encode(jsonEncode(response)).length > maxResponseBytes) {
            return _fail(
              ResponseLimitError(
                'Native response exceeds byte limit.',
                limit: maxResponseBytes,
                partialOutput: _assembler.partialOutput,
              ),
            );
          }
          final normalized = codec
              .decode(response, metadata: metadata)
              .flatMap(
                (value) => codec.normalize(
                  value,
                  NativePayload(
                    providerId: codec.dialect.providerId,
                    api: codec.dialect.api,
                    modelId: modelId,
                    data: response,
                  ),
                  metadata: metadata,
                ),
              );
          final result = _accept(normalized);
          if (result == null) return Failure(_failure!);
          final expected = type == 'response.completed' ? 'completed' : 'incomplete';
          if (response['status'] != expected) {
            throw const _MalformedEvent('Terminal event contradicts response status.');
          }
          final output = response['output'];
          if (output is! List) throw const _MalformedEvent('Missing terminal output.');
          for (var oi = 0; oi < output.length; oi++) {
            _finishItem(events, oi, _object(output[oi]));
            if (_failure case final error?) return Failure(error);
          }
          if (result.usage case final usage?) _emit(events, UsageUpdated(usage: usage));
          _final = result;
        default:
          _emit(
            events,
            ProviderEvent(
              providerId: codec.dialect.providerId,
              api: codec.dialect.api,
              event: nativeType,
              data: decoded,
            ),
          );
      }
      if (_failure case final error?) return Failure(error);
      return Success(events);
    } on _MalformedEvent {
      return _malformed();
    }
  }

  Failure<List<GenerationEvent>, AiError> _malformed() => _fail(
    ProtocolError('Malformed Responses stream event.', partialOutput: _assembler.partialOutput),
  );

  /// Returns the final result after the transport owner has completed cleanup.
  Result<GenerationFinished, AiError> complete() {
    if (_failure case final error?) return Failure(error);
    final result = _final;
    if (result == null) {
      return Failure(
        ProtocolError(
          'Responses stream ended before terminal semantics.',
          partialOutput: _assembler.partialOutput,
        ),
      );
    }
    return _assembler.complete(
      terminal: true,
      native: result.native,
      finishReason: result.finishReason,
      nativeFinishReason: result.nativeFinishReason,
      responseId: result.responseId,
      metadata: metadata,
      replay: result.message.replay,
    );
  }

  /// Preserves the expected error kind while attaching available common output.
  AiError withPartial(AiError error) => switch (error) {
    ProtocolError(:final message) => ProtocolError(
      message,
      partialOutput: _assembler.partialOutput,
    ),
    ResponseLimitError(:final message, :final limit) => ResponseLimitError(
      message,
      limit: limit,
      partialOutput: _assembler.partialOutput,
    ),
    ProviderError(
      :final message,
      :final statusCode,
      :final code,
      :final details,
      :final requestId,
      :final retryAfter,
    ) =>
      ProviderError(
        message,
        statusCode: statusCode,
        code: code,
        details: details,
        requestId: requestId,
        retryAfter: retryAfter,
        partialOutput: _assembler.partialOutput,
      ),
    _ => error,
  };

  String _start(
    List<GenerationEvent> events,
    int oi,
    int ci,
    GenerationPartKind kind, {
    String? callId,
    String? name,
    ToolExecutionOwner? owner,
  }) {
    final id = '$oi:$ci';
    if (!_parts.containsKey(id)) {
      if (ci >= 1000000) throw const _MalformedEvent('Content index is too large.');
      _emit(
        events,
        PartStarted(
          id: id,
          index: oi * 1000000 + ci,
          kind: kind,
          callId: callId,
          name: name,
          owner: owner,
        ),
      );
      _parts[id] = kind;
    } else if (_parts[id] != kind) {
      throw const _MalformedEvent('Part kind changed.');
    }
    return id;
  }

  void _finishItem(List<GenerationEvent> events, int oi, Map<String, Object?> item) {
    final parts = _accept(codec.normalizeItem(item));
    if (parts == null) return;
    for (var ci = 0; ci < parts.length; ci++) {
      final part = parts[ci];
      final id = '$oi:$ci';
      if (_finished.contains(id)) continue;
      final kind = switch (part) {
        TextOutputPart() => GenerationPartKind.text,
        ReasoningOutputPart() => GenerationPartKind.reasoning,
        RefusalOutputPart() => GenerationPartKind.refusal,
        ToolCallPart() => GenerationPartKind.toolCall,
        ProviderToolPart() => GenerationPartKind.providerTool,
        OpaqueOutputPart() => GenerationPartKind.opaque,
      };
      _start(events, oi, ci, kind);
      _emit(events, PartFinished(id: id, part: part));
      if (_failure != null) return;
      _finished.add(id);
    }
  }

  void _emit(List<GenerationEvent> events, GenerationEvent event) {
    if (_failure != null) return;
    final accepted = _accept(_assembler.add(event));
    if (accepted != null) events.add(accepted);
  }

  T? _accept<T>(Result<T, AiError> result) {
    switch (result) {
      case Success(:final value):
        return value;
      case Failure(:final error):
        _fail<Object?>(error);
        return null;
    }
  }

  Failure<T, AiError> _fail<T>(AiError error) {
    _failure = error;
    _assembler.fail(error);
    return Failure(error);
  }

  static Map<String, Object?> _object(Object? value) {
    if (value is! Map<String, Object?>) throw const _MalformedEvent('Expected object.');
    return value;
  }

  static int _index(Map<String, Object?> data, String key, {bool optional = false}) {
    final value = data[key];
    if (value == null && optional) return 0;
    if (value is! int || value < 0) throw const _MalformedEvent('Invalid stream index.');
    return value;
  }
}

// Only structural event checks use this marker. A provider hook's own
// FormatException must escape unchanged as a Conflux defect.
class _MalformedEvent extends FormatException {
  const _MalformedEvent(super.message);
}
