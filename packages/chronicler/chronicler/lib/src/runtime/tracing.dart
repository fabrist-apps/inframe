import 'package:chronicler/src/codec.dart';
import 'package:chronicler/src/configuration.dart';
import 'package:chronicler/src/diagnostics.dart';
import 'package:chronicler/src/models.dart';
import 'package:chronicler/src/record_validation.dart';
import 'package:chronicler/src/runtime/record_processing.dart';
import 'package:chronicler/src/trace_propagation.dart';
import 'package:chrono_id/chrono_id.dart';

/// Owns active spans, sampling lineage, attribute updates, and finalization.
final class TraceController {
  /// Uses shared capture policy and runtime clocks without owning delivery.
  TraceController({
    required this._appId,
    required this._release,
    required this._source,
    required this._buildId,
    required this._options,
    required this._validator,
    required this._codec,
    required this._diagnostics,
    required this._processor,
    required this._canStart,
    required this._collectionEnabled,
    required this._propagationEnabled,
    required this._now,
    required this._elapsed,
    required this._nextRandom,
    required this._nextSecureByte,
    required this._finalize,
  });

  final String _appId;
  final String _release;
  final ChroniclerSource _source;
  final String? _buildId;
  final ChroniclerOptions _options;
  final RecordValidator _validator;
  final ChroniclerCodec _codec;
  final DiagnosticChannel _diagnostics;
  final RecordProcessor _processor;
  final bool Function() _canStart;
  final bool Function() _collectionEnabled;
  final bool Function() _propagationEnabled;
  final DateTime Function() _now;
  final Duration Function() _elapsed;
  final double Function() _nextRandom;
  final int Function() _nextSecureByte;
  final void Function(SpanRecord) _finalize;
  final _liveSpans = <ActiveSpan>{};
  bool _failNextStart = false;

  /// Makes the next start throw for deterministic containment tests.
  void failNextStartForTest() => _failNextStart = true;

  /// Discards live payloads and stops recording descendants of existing spans.
  void disableCollection() {
    for (final span in _liveSpans) {
      span
        .._recording = null
        .._lineageRecording = false;
    }
  }

  /// Classifies callback failures while containing classifier errors.
  SpanStatus failureStatus(Object error) {
    final classifier = _options.tracing.isCancellation;
    if (classifier == null) return SpanStatus.error;
    try {
      return classifier(error) ? SpanStatus.cancelled : SpanStatus.error;
    } on Object {
      _diagnostics.record(DiagnosticReason.cancellationClassifierFailed);
      return SpanStatus.error;
    }
  }

  /// Starts correlation and, when sampled, retains a validated span payload.
  ActiveSpan? start(
    ActiveSpan? current,
    String name, {
    required SpanKind kind,
    required String? userId,
    required String? anonymousId,
    required String? sessionId,
    required Map<String, Object?> attributes,
    required bool forceRoot,
    required RemoteTraceParent? remoteParent,
  }) {
    if (_failNextStart) {
      _failNextStart = false;
      throw StateError('Injected span start failure.');
    }
    if (!_canStart()) return null;
    final acceptedRemote = forceRoot && _propagationEnabled() ? remoteParent : null;
    final activeParent = !forceRoot && current != null && !current._ended ? current : null;
    late final String traceId;
    late final String spanId;
    try {
      traceId = acceptedRemote?.traceId ?? activeParent?.traceId ?? _traceId();
      spanId = _spanId();
    } on Object {
      _diagnostics.record(DiagnosticReason.invalidRecord);
      return null;
    }
    final collectionEnabled = _collectionEnabled();
    late final bool sampled;
    try {
      sampled = activeParent == null
          ? _selectBoundarySampling(acceptedRemote, collectionEnabled)
          : activeParent._lineageRecording && activeParent._sampled;
    } on Object {
      _diagnostics.record(DiagnosticReason.invalidRecord);
      return null;
    }
    final lineageRecording = activeParent?._lineageRecording ?? (collectionEnabled && sampled);
    _SpanRecordingState? recording;
    if (lineageRecording) {
      try {
        _validator.validateString(name, _options.limits.maxLabelBytes, 'span name');
        if (name.isEmpty) {
          throw const RecordValidationException('span name must be nonempty');
        }
        recording = _SpanRecordingState(
          eventId: ChronoID.generate(prefix: 'evt'),
          name: name,
          kind: kind,
          attributes: _processor.redactAttributes(_validator.snapshotAttributes(attributes)),
          startedAt: _elapsed(),
          timestamp: _now(),
          userId: userId,
          anonymousId: anonymousId,
          sessionId: sessionId,
        );
      } on Object {
        _diagnostics.record(DiagnosticReason.invalidRecord);
      }
    }
    final state = ActiveSpan._(
      traceId: traceId,
      spanId: spanId,
      parentSpanId: acceptedRemote?.parentSpanId ?? activeParent?.spanId,
      lineageRecording: lineageRecording,
      sampled: sampled,
      tracestate: acceptedRemote?.tracestate ?? activeParent?._tracestate ?? const [],
      recording: recording,
    );
    _liveSpans.add(state);
    return state;
  }

  /// Ends one callback lifetime and finalizes its retained payload once.
  void finish(ActiveSpan? span, SpanStatus status) {
    if (span == null) return;
    if (span._ended) return;
    span._ended = true;
    _liveSpans.remove(span);
    final recording = span._recording;
    if (recording == null) return;
    final finalStatus = status == SpanStatus.success && span._explicitError
        ? SpanStatus.error
        : status;
    final durationMicros = (_elapsed() - recording.startedAt).inMicroseconds;
    _finalize(
      _spanRecord(
        span,
        recording,
        status: finalStatus,
        durationMicros: durationMicros,
        attributes: recording.attributes,
      ),
    );
  }

  /// Marks an active span as failed without changing the callback result.
  void setError(ActiveSpan? span) {
    if (!_canUpdateSpan(span)) return;
    span!._explicitError = true;
  }

  /// Validates and sizes a proposed attribute merge before retaining it.
  void setAttributes(ActiveSpan? span, Map<String, Object?> update) {
    if (!_canUpdateSpan(span)) return;
    final recording = span!._recording;
    if (recording == null) return;
    try {
      final proposed = <String, Object?>{...recording.attributes, ...update};
      final snapshot = _processor.redactAttributes(_validator.snapshotAttributes(proposed));
      final reserved = _spanRecord(
        span,
        recording,
        status: SpanStatus.cancelled,
        durationMicros: 9007199254740991,
        attributes: snapshot,
      );
      _codec
        ..validateRecord(reserved)
        ..encodeRecord(reserved);
      recording.attributes = snapshot;
    } on Object {
      _diagnostics.record(DiagnosticReason.invalidSpanUpdate);
    }
  }

  bool _canUpdateSpan(ActiveSpan? span) {
    if (span == null) {
      _diagnostics.record(DiagnosticReason.noActiveSpan);
      return false;
    }
    if (span._ended) {
      _diagnostics.record(DiagnosticReason.invalidSpanUpdate);
      return false;
    }
    return true;
  }

  SpanRecord _spanRecord(
    ActiveSpan span,
    _SpanRecordingState recording, {
    required SpanStatus status,
    required int durationMicros,
    required Map<String, Object?> attributes,
  }) {
    return SpanRecord(
      envelope: RecordEnvelope(
        eventId: recording.eventId,
        appId: _appId,
        release: _release,
        source: _source,
        timestamp: recording.timestamp,
        buildId: _buildId,
        userId: recording.userId,
        anonymousId: recording.anonymousId,
        sessionId: recording.sessionId,
        traceId: span.traceId,
        spanId: span.spanId,
        parentSpanId: span._parentSpanId,
      ),
      payload: SpanPayload(
        name: recording.name,
        spanKind: recording.kind,
        status: status,
        durationMicros: durationMicros,
        attributes: attributes,
      ),
    );
  }

  String _traceId() => _randomHex(16);

  String _spanId() => _randomHex(8);

  bool _selectLocalTraceSampling() {
    final rate = _options.sampling.traces;
    final sampled = rate == 1 || rate > 0 && _nextRandom() < rate;
    if (!sampled) _diagnostics.record(DiagnosticReason.sampledOut);
    return sampled;
  }

  bool _selectBoundarySampling(RemoteTraceParent? parent, bool collectionEnabled) {
    if (!collectionEnabled) return false;
    if (parent == null || !_options.tracing.honorRemoteSampling) {
      return _selectLocalTraceSampling();
    }
    if (!parent.sampled) _diagnostics.record(DiagnosticReason.sampledOut);
    return parent.sampled;
  }

  /// Replaces stale headers with active correlation when propagation is enabled.
  Map<String, String> inject(ActiveSpan? span, Map<String, String> headers) {
    final result = <String, String>{
      for (final MapEntry(:key, :value) in headers.entries)
        if (key.toLowerCase() != 'traceparent' && key.toLowerCase() != 'tracestate') key: value,
    };
    if (!_propagationEnabled() || span == null || span._ended) return result;
    result['traceparent'] = '00-${span.traceId}-${span.spanId}-${span._sampled ? '01' : '00'}';
    if (span._tracestate.isNotEmpty) result['tracestate'] = span._tracestate.join(',');
    return result;
  }

  String _randomHex(int byteCount) {
    for (var attempt = 0; attempt < 8; attempt++) {
      final bytes = List<int>.generate(byteCount, (_) => _nextSecureByte());
      if (bytes.any((byte) => byte != 0)) {
        return bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
      }
    }
    throw StateError('Secure randomness produced only zero identifiers');
  }
}

/// Opaque active trace correlation; mutable lifecycle belongs to TraceController.
final class ActiveSpan {
  ActiveSpan._({
    required this.traceId,
    required this.spanId,
    required this._parentSpanId,
    required this._lineageRecording,
    required this._sampled,
    required this._tracestate,
    required this._recording,
  });

  /// Trace identifier inherited by correlated records.
  final String traceId;

  /// Span identifier inherited by correlated records.
  final String spanId;
  final String? _parentSpanId;
  bool _lineageRecording;
  final bool _sampled;
  final List<String> _tracestate;
  _SpanRecordingState? _recording;
  bool _ended = false;
  bool _explicitError = false;

  /// Attribute retention visible to internal lifecycle tests.
  int get retainedAttributeCount => _recording?.attributes.length ?? 0;
}

final class _SpanRecordingState {
  _SpanRecordingState({
    required this.eventId,
    required this.name,
    required this.kind,
    required this.attributes,
    required this.startedAt,
    required this.timestamp,
    required this.userId,
    required this.anonymousId,
    required this.sessionId,
  });

  final String eventId;
  final String name;
  final SpanKind kind;
  Map<String, Object?> attributes;
  final Duration startedAt;
  final DateTime timestamp;
  final String? userId;
  final String? anonymousId;
  final String? sessionId;
}
