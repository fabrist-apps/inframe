import 'dart:collection';
import 'dart:convert';

import 'package:artificer_core/src/errors.dart';
import 'package:artificer_core/src/generation/generation.dart';
import 'package:artificer_core/src/json/json_value.dart';
import 'package:artificer_core/src/messages/messages.dart';
import 'package:artificer_core/src/native.dart';
import 'package:artificer_core/src/protocols/chat/chat_codec.dart';
import 'package:artificer_core/src/protocols/chat/chat_dialect.dart';
import 'package:artificer_core/src/protocols/chat/chat_models.dart';
import 'package:artificer_core/src/protocols/generation_assembler.dart';
import 'package:artificer_core/src/protocols/sse.dart';
import 'package:conflux/result.dart';

/// Execution-local compatible Chat assembly, shared by configured dialects.
/// Consumers append [complete] only after their transport Flow has released I/O.
final class ChatStreamAssembly {
  /// Creates fresh bounded state for one selected candidate.
  ChatStreamAssembly(
    this.codec,
    this.model, {
    this.choiceIndex = 0,
    int maxResponseBytes = 64 * 1024 * 1024,
  }) : assembler = GenerationAssembler(maxResponseBytes: maxResponseBytes),
       _raw = _SizedJsonObject({'model': model, 'choices': <Object?>[]});

  /// Pure codec owning native normalization and provider identity.
  final ChatCodec codec;

  /// Requested model alias retained for same-target replay compatibility.
  final String model;

  /// Explicit candidate index represented by this stream.
  final int choiceIndex;

  /// Core bounded common/native output assembly.
  final GenerationAssembler assembler;
  final _SizedJsonObject _raw;
  final _SizedJsonObject _message = _SizedJsonObject({'role': 'assistant'});
  final _SizedJsonObject _choice = _SizedJsonObject({});
  final Map<int, _SizedJsonObject> _tools = {};
  final Set<String> _parts = {};
  late ResponseMetadata _metadata;
  String? _finish;
  NativeResponse<ChatResponse>? _response;
  bool _sentinel = false;
  bool _choiceFinished = false;

  /// Whether a recognized sentinel ends network consumption immediately.
  bool get terminal => _sentinel;

  /// Emits response start after valid HTTP headers, before any data frame.
  Result<GenerationEvent, AiError> start(ResponseMetadata metadata) {
    _metadata = metadata;
    return assembler.add(GenerationStarted(requestId: metadata.requestId));
  }

  /// Converts a single frame without retaining known event history.
  Result<List<GenerationEvent>, AiError> accept(SseEvent event) {
    if (event.data == codec.dialect.sentinel) {
      if (codec.dialect.terminalPolicy == ChatTerminalPolicy.sentinel) _sentinel = true;
      return const Success([]);
    }
    final Map<String, Object?> data;
    try {
      data = ChatCodec.object(jsonDecode(event.data));
      JsonValues.validate(data);
    } on FormatException {
      return Failure(
        ProtocolError('Malformed Chat stream frame.', partialOutput: assembler.partialOutput),
      );
    }
    if (codec.error(data, _metadata) case final error?) return Failure(error);
    try {
      final events = <GenerationEvent>[];
      void add(GenerationEvent event) {
        events.add(event);
      }

      if (data['choices'] is! List<Object?>) {
        add(
          ProviderEvent(
            providerId: codec.dialect.providerId,
            api: codec.dialect.api,
            event: event.event ?? 'unknown',
            data: data,
          ),
        );
      } else {
        for (final entry in data.entries) {
          if (entry.key == 'choices') continue;
          _raw[entry.key] = entry.key == 'object' && entry.value == 'chat.completion.chunk'
              ? 'chat.completion'
              : entry.value;
        }
        if (data['usage'] != null) add(UsageUpdated(usage: ChatCodec.usage(data['usage'])!));
        for (final item in ChatCodec.list(data['choices'])) {
          final choice = ChatCodec.object(item);
          final index = ChatCodec.integer(choice['index']);
          if (index != choiceIndex) {
            add(
              ProviderEvent(
                providerId: codec.dialect.providerId,
                api: codec.dialect.api,
                event: 'unselectedChoice',
                data: choice,
              ),
            );
            continue;
          }
          final delta = ChatCodec.object(choice['delta'] ?? <String, Object?>{});
          if (_choiceFinished && delta.isNotEmpty) {
            throw const FormatException('Delta after selected finish.');
          }
          for (final entry in delta.entries) {
            if (entry.key == 'content' ||
                entry.key == codec.dialect.reasoningField ||
                entry.key == 'refusal') {
              if (entry.value == null) continue;
              final fragment = ChatCodec.string(entry.value, allowEmpty: true);
              final key = entry.key;
              final id = key == 'content'
                  ? 'text'
                  : key == 'refusal'
                  ? 'refusal'
                  : 'reasoning';
              final kind = key == 'content'
                  ? GenerationPartKind.text
                  : key == 'refusal'
                  ? GenerationPartKind.refusal
                  : GenerationPartKind.reasoning;
              if (_parts.add(id)) {
                add(
                  PartStarted(
                    id: id,
                    index: id == 'text'
                        ? 0
                        : id == 'reasoning'
                        ? 1
                        : 2,
                    kind: kind,
                  ),
                );
              }
              _message.append(key, fragment);
              if (kind == GenerationPartKind.text) {
                add(
                  PartDelta(
                    id: id,
                    delta: TextDelta(text: fragment),
                  ),
                );
              }
              if (kind == GenerationPartKind.reasoning) {
                add(
                  PartDelta(
                    id: id,
                    delta: ReasoningDelta(text: fragment),
                  ),
                );
              }
            } else if (entry.key == 'tool_calls') {
              for (final native in ChatCodec.list(entry.value)) {
                final call = ChatCodec.object(native);
                final toolIndex = ChatCodec.integer(call['index']);
                final target = _tools.putIfAbsent(
                  toolIndex,
                  () => _SizedJsonObject({
                    'type': call['type'] ?? 'function',
                    if (call['type'] == null || call['type'] == 'function')
                      'function': _SizedJsonObject({'arguments': ''}),
                  }),
                );
                final isFunction = target['type'] == 'function';
                final id = 'tool-$toolIndex';
                if (_parts.add(id)) {
                  add(
                    PartStarted(
                      id: id,
                      index: 100 + toolIndex,
                      kind: isFunction ? GenerationPartKind.toolCall : GenerationPartKind.opaque,
                      owner: isFunction ? ToolExecutionOwner.application : null,
                    ),
                  );
                }
                for (final field in call.entries) {
                  if (field.key == 'index') continue;
                  if (field.key == 'function' && isFunction) {
                    final nativeFunction = ChatCodec.object(target['function']);
                    final function = nativeFunction is _SizedJsonObject
                        ? nativeFunction
                        : _SizedJsonObject(nativeFunction);
                    for (final part in ChatCodec.object(field.value).entries) {
                      if (part.key == 'arguments' || part.key == 'name') {
                        final fragment = ChatCodec.string(part.value, allowEmpty: true);
                        function.append(part.key, fragment);
                        if (part.key == 'arguments') {
                          add(
                            PartDelta(
                              id: id,
                              delta: ToolArgumentsDelta(text: fragment),
                            ),
                          );
                        }
                      } else {
                        function[part.key] = part.value;
                      }
                    }
                    target['function'] = function;
                  } else if (field.key == 'id') {
                    final incoming = ChatCodec.string(field.value);
                    if (target['id'] != incoming) target.append('id', incoming);
                  } else {
                    target[field.key] = field.value;
                  }
                }
              }
              _message['tool_calls'] = [
                for (final index in _tools.keys.toList()..sort()) _tools[index],
              ];
            } else {
              _message[entry.key] = entry.value;
            }
          }
          if (choice['finish_reason'] != null) {
            _finish = ChatCodec.string(choice['finish_reason']);
            _choiceFinished = true;
          }
          _choice
            ..addAll(choice)
            ..['message'] = _message
            ..['finish_reason'] = _finish
            ..remove('delta');
          _raw['choices'] = [_choice];
        }
      }
      if (_raw.byteLength > assembler.maxResponseBytes) {
        return Failure(
          ResponseLimitError(
            'Assembled Chat response exceeds byte limit.',
            limit: assembler.maxResponseBytes,
            partialOutput: assembler.partialOutput,
          ),
        );
      }
      for (final event in events) {
        if (assembler.add(event) case Failure<GenerationEvent, AiError>(:final error)) {
          return Failure(error);
        }
      }
      return Success(events);
    } on FormatException {
      return Failure(
        ProtocolError('Malformed Chat stream frame.', partialOutput: assembler.partialOutput),
      );
    }
  }

  /// Finishes parts after native terminal semantics, retaining late metadata.
  Result<List<GenerationEvent>, AiError> finishParts() {
    if (!_choiceFinished ||
        (codec.dialect.terminalPolicy == ChatTerminalPolicy.sentinel && !_sentinel)) {
      return Failure(
        ProtocolError(
          'Chat stream ended before its terminal.',
          partialOutput: assembler.partialOutput,
        ),
      );
    }
    final decoded = codec.decode(_raw, _metadata, requestedModelId: model);
    if (decoded case Failure<NativeResponse<ChatResponse>, AiError>(:final error)) {
      return Failure(error);
    }
    _response = (decoded as Success<NativeResponse<ChatResponse>, AiError>).value;
    final normalized = codec.normalize(_response!, choiceIndex: choiceIndex);
    if (normalized case Failure<GenerationResult, AiError>(:final error)) return Failure(error);
    final result = (normalized as Success<GenerationResult, AiError>).value;
    final events = <GenerationEvent>[];
    var tool = 0;
    final toolIndices = _tools.keys.toList()..sort();
    for (final part in result.message.parts) {
      final id = switch (part) {
        TextOutputPart() => 'text',
        ReasoningOutputPart() => 'reasoning',
        RefusalOutputPart() => 'refusal',
        ToolCallPart() || OpaqueOutputPart() => 'tool-${toolIndices[tool++]}',
        _ => 'opaque-${events.length}',
      };
      if (!_parts.contains(id)) {
        return Failure(
          ProtocolError(
            'Native content lacks a streamed part.',
            partialOutput: assembler.partialOutput,
          ),
        );
      }
      final event = PartFinished(id: id, part: part);
      if (assembler.add(event) case Failure<GenerationEvent, AiError>(:final error)) {
        return Failure(error);
      }
      events.add(event);
    }
    return Success(events);
  }

  /// Emits the single final result after the transport has completed cleanup.
  Result<GenerationFinished, AiError> complete() {
    final response = _response;
    if (response == null) {
      return Failure(
        ProtocolError('Chat response is incomplete.', partialOutput: assembler.partialOutput),
      );
    }
    return assembler.complete(
      terminal: true,
      native: response.raw,
      finishReason: ChatCodec.finishReason(_finish),
      nativeFinishReason: _finish,
      responseId: response.value.id,
      metadata: response.metadata,
      replay: ProviderReplay(
        providerId: codec.dialect.providerId,
        api: codec.dialect.api,
        modelId: response.raw.modelId,
        items: [_message],
      ),
    );
  }

  /// Attaches available output to framing, transport, or native error outcomes.
  AiError withPartial(AiError error) => switch (error) {
    ProtocolError(:final message) => ProtocolError(message, partialOutput: assembler.partialOutput),
    ResponseLimitError(:final message, :final limit) => ResponseLimitError(
      message,
      limit: limit,
      partialOutput: assembler.partialOutput,
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
        partialOutput: assembler.partialOutput,
      ),
    _ => error,
  };
}

/// Caches encoded field sizes. Refresh a parent field after mutating its child.
/// Stream fragments are counted once instead of re-encoding accumulated text.
final class _SizedJsonObject extends MapBase<String, Object?> {
  _SizedJsonObject(Map<String, Object?> values) {
    addAll(values);
  }

  final Map<String, Object?> _values = {};
  final Map<String, int> _fieldBytes = {};
  int byteLength = 2;

  static int _encodedSize(Object? value) => switch (value) {
    _SizedJsonObject() => value.byteLength,
    List<Object?>() =>
      2 +
          (value.isEmpty ? 0 : value.length - 1) +
          value.fold(0, (sum, item) => sum + _encodedSize(item)),
    _ => utf8.encode(jsonEncode(value)).length,
  };

  @override
  Object? operator [](Object? key) => _values[key];

  @override
  void operator []=(String key, Object? value) {
    _set(key, value, _encodedSize(value));
  }

  void _set(String key, Object? value, int valueBytes) {
    final oldBytes = _fieldBytes[key];
    if (oldBytes == null) {
      byteLength += _encodedSize(key) + 1 + (_values.isEmpty ? 0 : 1);
    }
    byteLength += valueBytes - (oldBytes ?? 0);
    _fieldBytes[key] = valueBytes;
    _values[key] = value;
  }

  void append(String key, String fragment) {
    final previous = (_values[key] ?? '') as String;
    var size = (_fieldBytes[key] ?? 2) + _encodedSize(fragment) - 2;
    // A surrogate pair split across frames encodes differently when joined.
    if (previous.isNotEmpty && fragment.isNotEmpty) {
      final last = previous.codeUnitAt(previous.length - 1);
      final first = fragment.codeUnitAt(0);
      if (last >= 0xd800 && last <= 0xdbff && first >= 0xdc00 && first <= 0xdfff) {
        final left = String.fromCharCode(last);
        final right = String.fromCharCode(first);
        size += _encodedSize('$left$right') - _encodedSize(left) - _encodedSize(right) + 2;
      }
    }
    _set(key, '$previous$fragment', size);
  }

  @override
  Iterable<String> get keys => _values.keys;

  @override
  Object? remove(Object? key) {
    final size = _fieldBytes.remove(key);
    if (size == null) return null;
    byteLength -= _encodedSize(key) + 1 + size + (_values.length > 1 ? 1 : 0);
    return _values.remove(key);
  }

  @override
  void clear() {
    _values.clear();
    _fieldBytes.clear();
    byteLength = 2;
  }
}
