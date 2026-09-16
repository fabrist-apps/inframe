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
       _raw = {'model': model, 'choices': <Object?>[]};

  /// Pure codec owning native normalization and provider identity.
  final ChatCodec codec;

  /// Requested model alias retained for same-target replay compatibility.
  final String model;

  /// Explicit candidate index represented by this stream.
  final int choiceIndex;

  /// Core bounded common/native output assembly.
  final GenerationAssembler assembler;
  final Map<String, Object?> _raw;
  final Map<String, Object?> _message = {'role': 'assistant'};
  final Map<String, Object?> _choice = {};
  final Map<int, Map<String, Object?>> _tools = {};
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
              _message[key] = '${_message[key] ?? ''}$fragment';
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
                  () => {
                    'type': call['type'] ?? 'function',
                    if (call['type'] == null || call['type'] == 'function')
                      'function': <String, Object?>{'arguments': ''},
                  },
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
                    final function = ChatCodec.object(target['function']);
                    for (final part in ChatCodec.object(field.value).entries) {
                      if (part.key == 'arguments' || part.key == 'name') {
                        final fragment = ChatCodec.string(part.value, allowEmpty: true);
                        function[part.key] = '${function[part.key] ?? ''}$fragment';
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
                  } else if (field.key == 'id') {
                    final incoming = ChatCodec.string(field.value);
                    if (target['id'] != incoming) target['id'] = '${target['id'] ?? ''}$incoming';
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
      if (utf8.encode(jsonEncode(_raw)).length > assembler.maxResponseBytes) {
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
