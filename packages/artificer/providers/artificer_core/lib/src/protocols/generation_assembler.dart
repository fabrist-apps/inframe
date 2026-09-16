import 'dart:convert';

import 'package:artificer_core/src/errors.dart';
import 'package:artificer_core/src/generation/generation.dart';
import 'package:artificer_core/src/json/json_value.dart';
import 'package:artificer_core/src/messages/messages.dart';
import 'package:artificer_core/src/native.dart';
import 'package:artificer_core/src/tools/tools.dart';
import 'package:conflux/result.dart';

/// Validates one stream's ordering and retains its bounded common/native result.
///
/// Endpoint codecs recognize terminal semantics and supply authoritative finished
/// parts for late citations, signatures and native tool identity. Transport owners
/// emit the returned final event only after releasing response resources.
final class GenerationAssembler {
  /// Creates execution-local assembly state with a positive retained-byte limit.
  GenerationAssembler({this.maxResponseBytes = 64 * 1024 * 1024}) {
    if (maxResponseBytes <= 0) throw ArgumentError.value(maxResponseBytes, 'maxResponseBytes');
  }

  /// Maximum combined retained common, native and unknown-event JSON size.
  final int maxResponseBytes;
  final Map<String, _Part> _parts = {};
  final List<Map<String, Object?>> _unknown = [];
  int _retainedBytes = 0;
  bool _started = false;
  bool _completed = false;
  AiError? _failure;
  String? _responseId;
  Usage? _usage;

  /// Available ordered output and unfinished deltas, suitable for typed errors.
  Map<String, Object?> get partialOutput => {
    'parts': [
      for (final part in _orderedParts)
        if (part.finished != null)
          part.finished!.toMap()
        else
          {'id': part.start.id, 'index': part.start.index, 'delta': part.text.toString()},
    ],
    'unknownEvents': _unknown,
  };

  List<_Part> get _orderedParts =>
      _parts.values.toList()..sort((a, b) => a.start.index.compareTo(b.start.index));

  /// Accepts a translated event without retaining all known event records.
  Result<GenerationEvent, AiError> add(GenerationEvent event) {
    if (_failure case final error?) return Failure(error);
    if (_completed) return _reject('Events arrived after completion.');
    if (event is GenerationStarted) {
      if (_started) return _reject('Generation started more than once.');
      if (!_reserve(_size(event.toMap()))) return Failure(_failure!);
      _started = true;
      _responseId = event.responseId;
      return Success(event);
    }
    if (!_started) return _reject('Generation event arrived before start.');
    switch (event) {
      case GenerationStarted():
        return _reject('Generation started more than once.');
      case PartStarted():
        if (event.id.isEmpty ||
            event.index < 0 ||
            _parts.containsKey(event.id) ||
            _parts.values.any((p) => p.start.index == event.index)) {
          return _reject('Part identity or order index is invalid or duplicated.');
        }
        if (!_reserve(_size(event.toMap()))) return Failure(_failure!);
        _parts[event.id] = _Part(event);
      case PartDelta(:final id, :final delta):
        final part = _parts[id];
        if (part == null || part.finished != null) {
          return _reject('Delta references an absent or finished part.');
        }
        final text = switch (delta) {
          TextDelta(:final text) when part.start.kind == GenerationPartKind.text => text,
          ReasoningDelta(:final text) when part.start.kind == GenerationPartKind.reasoning => text,
          ToolArgumentsDelta(:final text) when part.start.kind == GenerationPartKind.toolCall =>
            text,
          _ => null,
        };
        if (text == null) return _reject('Delta kind does not match its part.');
        final bytes = utf8.encode(text).length;
        if (!_reserve(bytes)) return Failure(_failure!);
        part
          ..deltaBytes += bytes
          ..hasDelta = true;
        part.text.write(text);
      case PartFinished(:final id, part: final output):
        final part = _parts[id];
        if (part == null || part.finished != null) {
          return _reject('Finish references an absent or finished part.');
        }
        if (!_validOutput(output)) return Failure(_failure!);
        if (!_compatible(part, output)) {
          return _reject('Finished part contradicts its kind, identity or deltas.');
        }
        if (!_reserve(_size(output.toMap()) - part.deltaBytes)) return Failure(_failure!);
        part.finished = output;
        part.text.clear();
        part.deltaBytes = 0;
      case UsageUpdated(:final usage):
        if (!_reserve(_size(usage.toMap()) - (_usage == null ? 0 : _size(_usage!.toMap())))) {
          return Failure(_failure!);
        }
        _usage = usage;
      case ProviderEvent():
        if (!_validJson(event.data)) return Failure(_failure!);
        final record = event.toMap();
        if (!_reserve(_size(record))) return Failure(_failure!);
        _unknown.add(record);
      case GenerationFinished():
        return _reject('Use complete with explicit endpoint terminal semantics.');
    }
    return Success(event);
  }

  /// Assembles text, summary or JSON arguments; codecs may add late metadata.
  Result<OutputPart, AiError> assembledPart(String id, {String? callId, String? name}) {
    if (_failure case final error?) return Failure(error);
    final part = _parts[id];
    if (part == null) return Failure(ProtocolError('Unknown part.', partialOutput: partialOutput));
    if (part.finished case final output?) return Success(output);
    final text = part.text.toString();
    switch (part.start.kind) {
      case GenerationPartKind.text:
        return Success(TextOutputPart(text));
      case GenerationPartKind.reasoning:
        return Success(ReasoningOutputPart(summary: text));
      case GenerationPartKind.toolCall:
        final resolvedId = callId ?? part.start.callId;
        final resolvedName = name ?? part.start.name;
        if (resolvedId == null ||
            resolvedId.isEmpty ||
            resolvedName == null ||
            resolvedName.isEmpty) {
          return Failure(
            ProtocolError('Application tool identity is incomplete.', partialOutput: partialOutput),
          );
        }
        return Success(
          ToolCallPart(
            callId: resolvedId,
            name: resolvedName,
            arguments: ToolArguments.parse(text),
          ),
        );
      case GenerationPartKind.refusal:
      case GenerationPartKind.providerTool:
      case GenerationPartKind.opaque:
        return Failure(
          ProtocolError(
            'Native part requires an authoritative finished value.',
            partialOutput: partialOutput,
          ),
        );
    }
  }

  /// Produces one final value only after the endpoint recognizes its terminal.
  Result<GenerationFinished, AiError> complete({
    required bool terminal,
    required NativePayload native,
    required FinishReason finishReason,
    String? nativeFinishReason,
    String? responseId,
    ResponseMetadata? metadata,
    ProviderReplay? replay,
  }) {
    if (_failure case final error?) return Failure(error);
    if (_completed ||
        !_started ||
        !terminal ||
        _parts.values.any((part) => part.finished == null)) {
      return _reject('Stream ended without a valid terminal and complete parts.');
    }
    if (!_validJson(native.data) ||
        !_validJson(native.unknownEvents) ||
        !_validJson(replay?.items)) {
      return Failure(_failure!);
    }
    final payload = NativePayload(
      providerId: native.providerId,
      api: native.api,
      modelId: native.modelId,
      data: native.data,
      unknownEvents: [...native.unknownEvents, ..._unknown],
    );
    // Unknown events already count in retained bytes; add only newly retained data.
    final extraBytes = _size(native.toMap()) + (replay == null ? 0 : _size(replay.toMap()));
    if (!_reserve(extraBytes)) return Failure(_failure!);
    _completed = true;
    return Success(
      GenerationFinished(
        GenerationResult(
          message: AssistantMessage([
            for (final part in _orderedParts) part.finished!,
          ], replay: replay),
          finishReason: finishReason,
          nativeFinishReason: nativeFinishReason,
          native: payload,
          usage: _usage,
          responseId: responseId ?? _responseId,
          metadata: metadata,
        ),
      ),
    );
  }

  /// Marks an endpoint error so later EOF cannot fabricate a finished result.
  Result<GenerationEvent, AiError> fail(AiError error) {
    _failure ??= error;
    return Failure(_failure!);
  }

  bool _compatible(_Part part, OutputPart output) {
    final kind = switch (output) {
      TextOutputPart() => GenerationPartKind.text,
      ReasoningOutputPart() => GenerationPartKind.reasoning,
      RefusalOutputPart() => GenerationPartKind.refusal,
      ToolCallPart() => GenerationPartKind.toolCall,
      ProviderToolPart() => GenerationPartKind.providerTool,
      OpaqueOutputPart() => GenerationPartKind.opaque,
    };
    if (kind != part.start.kind) return false;
    if (output is ToolCallPart) {
      if ((part.start.callId != null && part.start.callId != output.callId) ||
          (part.start.name != null && part.start.name != output.name) ||
          part.start.owner == ToolExecutionOwner.provider) {
        return false;
      }
    }
    if (output is ProviderToolPart &&
        part.start.owner != null &&
        output.owner != part.start.owner) {
      return false;
    }
    if (!part.hasDelta) return true;
    final finishedText = switch (output) {
      TextOutputPart(:final text) => text,
      ReasoningOutputPart(:final summary) => summary,
      ToolCallPart(:final arguments) => switch (arguments) {
        JsonToolArguments(:final original) => original,
        FreeFormToolArguments(:final text) => text,
        MalformedToolArguments(:final original) => original,
        NativeToolArguments() => null,
      },
      _ => null,
    };
    return finishedText == part.text.toString();
  }

  bool _validOutput(OutputPart part) => switch (part) {
    TextOutputPart(:final citations) => citations.every((citation) => _validJson(citation.data)),
    OpaqueOutputPart(:final data) => _validJson(data),
    ProviderToolPart(:final native) => _validJson(native),
    ToolCallPart(:final arguments) => switch (arguments) {
      JsonToolArguments(:final value) => _validJson(value),
      NativeToolArguments(:final value) => _validJson(value),
      _ => true,
    },
    _ => true,
  };

  bool _validJson(Object? value) {
    try {
      JsonValues.validate(value);
      return true;
    } on FormatException {
      _failure = ProtocolError(
        'Native stream data is not JSON compatible.',
        partialOutput: partialOutput,
      );
      return false;
    }
  }

  int _size(Object? value) => utf8.encode(jsonEncode(value)).length;

  bool _reserve(int bytes) {
    if (_retainedBytes + bytes > maxResponseBytes) {
      _failure = ResponseLimitError(
        'Assembled response exceeds byte limit.',
        limit: maxResponseBytes,
        partialOutput: partialOutput,
      );
      return false;
    }
    _retainedBytes += bytes;
    return true;
  }

  Failure<T, AiError> _reject<T>(String message) {
    _failure ??= ProtocolError(message, partialOutput: partialOutput);
    return Failure(_failure!);
  }
}

final class _Part {
  _Part(this.start);
  final PartStarted start;
  final StringBuffer text = StringBuffer();
  int deltaBytes = 0;
  bool hasDelta = false;
  OutputPart? finished;
}
