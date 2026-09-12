import 'dart:convert';

import '../errors.dart';
import '../generation/generation.dart';
import '../json/json_value.dart';
import '../messages/messages.dart';
import '../native.dart';

/// Builds common events and the final result from provider stream records.
final class GenerationStreamAssembler {
  GenerationStreamAssembler({
    required String providerId,
    required String api,
    required String modelId,
    this.maxAssembledBytes = 64 * 1024 * 1024,
  }) : providerId = _nonEmptyField(providerId, 'providerId'),
       api = _nonEmptyField(api, 'api'),
       modelId = _nonEmptyField(modelId, 'modelId') {
    if (maxAssembledBytes <= 0) {
      throw ArgumentError.value(maxAssembledBytes, 'maxAssembledBytes', 'must be positive');
    }
  }

  final String providerId;
  final String api;
  final String modelId;
  final int maxAssembledBytes;
  final Map<int, _PartState> _parts = {};
  ResponseMetadata? _metadata;
  String? _responseId;
  Usage? _usage;
  var _assembledBytes = 0;
  var _finished = false;

  /// The best immutable assistant message available at this point.
  AssistantMessage get partialMessage {
    final parts = _parts.values.toList()..sort((left, right) => left.index.compareTo(right.index));
    return AssistantMessage(parts.map((state) => state.snapshot).whereType<OutputPart>());
  }

  /// Starts the common stream exactly once.
  GenerationStarted start(ResponseMetadata metadata, {String? responseId}) {
    if (_metadata != null) throw const ProtocolError('Generation started more than once.');
    _metadata = metadata;
    _responseId = responseId;
    return GenerationStarted(responseId: responseId, metadata: metadata);
  }

  /// Starts one indexed part and assigns a stable provider-independent ID.
  PartStarted startPart({
    required int index,
    required GenerationPartKind kind,
    GenerationPartOwner owner = GenerationPartOwner.application,
  }) {
    _requireStarted();
    if (index < 0 || _parts.containsKey(index)) {
      throw ProtocolError(
        'Part index $index started more than once.',
        partialOutput: partialMessage,
      );
    }
    final state = _PartState(index: index, kind: kind, owner: owner);
    _parts[index] = state;
    return PartStarted(partId: state.partId, index: index, kind: kind, owner: owner);
  }

  /// Appends text to a text or reasoning part.
  PartDelta appendText(int index, String text) {
    final state = _openPart(index);
    _addBytes(text);
    state.text.write(text);
    return switch (state.kind) {
      GenerationPartKind.text => TextPartDelta(
        partId: state.partId,
        index: index,
        text: text,
      ),
      GenerationPartKind.refusal => RefusalPartDelta(
        partId: state.partId,
        index: index,
        text: text,
      ),
      GenerationPartKind.reasoning => ReasoningPartDelta(
        partId: state.partId,
        index: index,
        text: text,
      ),
      GenerationPartKind.applicationToolCall => ToolArgumentsPartDelta(
        partId: state.partId,
        index: index,
        text: text,
      ),
      _ => throw ProtocolError(
        'Part $index does not accept text deltas.',
        partialOutput: partialMessage,
      ),
    };
  }

  /// Adds an opaque delta to a provider-owned part.
  OpaquePartDelta appendOpaque(int index, JsonObject data) {
    final state = _openPart(index);
    if (state.kind != GenerationPartKind.opaque && state.kind != GenerationPartKind.providerTool) {
      throw ProtocolError(
        'Part $index does not accept opaque deltas.',
        partialOutput: partialMessage,
      );
    }
    _addBytes(data.encode());
    return OpaquePartDelta(partId: state.partId, index: index, data: data);
  }

  /// Completes a part; native IDs, citations, signatures, and metadata may arrive here.
  PartFinished finishPart(int index, OutputPart part) {
    final state = _openPart(index);
    state.finished = part;
    return PartFinished(partId: state.partId, index: index, part: part);
  }

  /// Records and emits a cumulative provider usage snapshot.
  UsageUpdated updateUsage(Usage usage) {
    _validateUsage(usage, _usage);
    _usage = usage;
    return UsageUpdated(usage);
  }

  /// Retains one unknown native event without collecting known events.
  ProviderEvent providerEvent(String name, JsonObject data) => ProviderEvent(
    providerId: providerId,
    api: api,
    name: name,
    data: data,
  );

  /// Creates the sole terminal success event after the caller has cleaned up transport.
  GenerationFinished finish({
    required FinishReason finishReason,
    required JsonObject nativeResponse,
    String? nativeFinishReason,
    Iterable<ReplayItem> replay = const [],
  }) {
    if (_finished) throw const ProtocolError('Generation finished more than once.');
    _requireStarted();
    if (_parts.values.any((part) => part.finished == null)) {
      throw ProtocolError('Generation ended with unfinished parts.', partialOutput: partialMessage);
    }
    final nativeBytes = utf8.encode(nativeResponse.encode()).length;
    if (nativeBytes > maxAssembledBytes) {
      throw ResponseLimitError(
        'The assembled native response exceeded the configured byte limit.',
        limit: maxAssembledBytes,
        actual: nativeBytes,
        partialOutput: partialMessage,
      );
    }
    _finished = true;
    final message = AssistantMessage(
      (_parts.values.toList()..sort((left, right) => left.index.compareTo(right.index))).map(
        (part) => part.finished!,
      ),
      replay: ProviderReplay(
        providerId: providerId,
        api: api,
        modelId: modelId,
        items: replay,
      ),
    );
    final metadata = _metadata!;
    return GenerationFinished(
      GenerationResult(
        message: message,
        finishReason: finishReason,
        nativeFinishReason: nativeFinishReason,
        usage: _usage,
        responseId: _responseId,
        requestId: metadata.requestId,
        nativePayload: NativePayload(
          providerId: providerId,
          api: api,
          modelId: modelId,
          json: nativeResponse,
        ),
        metadata: metadata,
      ),
    );
  }

  void _requireStarted() {
    if (_metadata == null) throw const ProtocolError('Generation has not started.');
  }

  _PartState _openPart(int index) {
    _requireStarted();
    final state = _parts[index];
    if (state == null) {
      throw ProtocolError(
        'Part $index received data before its start.',
        partialOutput: partialMessage,
      );
    }
    if (state.finished != null) {
      throw ProtocolError(
        'Part $index received data after its finish.',
        partialOutput: partialMessage,
      );
    }
    return state;
  }

  void _addBytes(String value) {
    _assembledBytes += utf8.encode(value).length;
    if (_assembledBytes > maxAssembledBytes) {
      throw ResponseLimitError(
        'The assembled response exceeded the configured byte limit.',
        limit: maxAssembledBytes,
        actual: _assembledBytes,
        partialOutput: partialMessage,
      );
    }
  }
}

String _nonEmptyField(String value, String name) {
  if (value.isEmpty) throw ArgumentError.value(value, name, 'must not be empty');
  return value;
}

void _validateUsage(Usage current, Usage? previous) {
  for (final entry in <(String, int?, int?)>[
    ('inputTokens', current.inputTokens, previous?.inputTokens),
    ('outputTokens', current.outputTokens, previous?.outputTokens),
    ('totalTokens', current.totalTokens, previous?.totalTokens),
  ]) {
    final (name, value, prior) = entry;
    if (value != null && (value < 0 || (prior != null && value < prior))) {
      throw ProtocolError('Cumulative $name decreased or became negative.');
    }
  }
}

final class _PartState {
  _PartState({required this.index, required this.kind, required this.owner})
    : partId = 'part-$index';

  final int index;
  final String partId;
  final GenerationPartKind kind;
  final GenerationPartOwner owner;
  final StringBuffer text = StringBuffer();
  OutputPart? finished;

  OutputPart? get snapshot {
    if (finished case final part?) return part;
    if (text.isEmpty) return null;
    return switch (kind) {
      GenerationPartKind.text => TextOutputPart(text.toString()),
      GenerationPartKind.reasoning => ReasoningSummaryPart(text.toString()),
      GenerationPartKind.refusal => RefusalPart(text.toString()),
      _ => null,
    };
  }
}
