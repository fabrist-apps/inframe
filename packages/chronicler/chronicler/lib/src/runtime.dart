import 'dart:async';
import 'dart:collection';
import 'dart:math';

import 'package:chronicler/src/codec.dart';
import 'package:chronicler/src/configuration.dart';
import 'package:chronicler/src/diagnostics.dart';
import 'package:chronicler/src/lifecycle.dart';
import 'package:chronicler/src/metrics.dart';
import 'package:chronicler/src/metrics/aggregation.dart';
import 'package:chronicler/src/models.dart';
import 'package:chronicler/src/record_validation.dart';
import 'package:chronicler/src/runtime/configuration.dart';
import 'package:chronicler/src/runtime/delivery_queue.dart';
import 'package:chronicler/src/runtime/record_processing.dart';
import 'package:chronicler/src/trace_propagation.dart';
import 'package:chronicler/src/transport.dart';
import 'package:chrono_id/chrono_id.dart';

/// One caller-supplied cause to snapshot during error capture.
final class ChroniclerCause {
  /// Creates an explicit cause from an arbitrary Dart [error] and optional stack.
  const ChroniclerCause(this.error, {this.stackTrace});

  /// Error value converted during capture.
  final Object error;

  /// Optional application stack converted during capture.
  final StackTrace? stackTrace;
}

/// Configured owner of capture and export resources.
final class Chronicler {
  /// Creates a runtime and transfers ownership of [exporter] to it.
  Chronicler({
    required String appId,
    required String release,
    required ChroniclerSource source,
    required ChroniclerExporter exporter,
    String? buildId,
    ChroniclerOptions options = const ChroniclerOptions(),
  }) : _runtime = ChroniclerRuntime.create(
         appId: appId,
         release: release,
         source: source,
         exporter: exporter,
         buildId: buildId,
         options: options,
       );

  Chronicler._fromRuntime(this._runtime);

  /// Default field-name terms replaced before buffering.
  static const Set<String> defaultSensitiveFieldTerms =
      ChroniclerOptions.defaultSensitiveFieldTerms;

  final ChroniclerRuntime _runtime;

  /// A borrowed recorder suitable for binding to a request context.
  ChroniclerRecorder get recorder => ChroniclerRecorder._(
    _runtime,
    const _RecorderAttribution(),
  );

  /// An immutable snapshot of exact runtime diagnostic counts.
  Map<DiagnosticReason, BigInt> get diagnosticCounts => _runtime.diagnosticCounts;

  /// Waits for the records owned when this call begins to reach a disposition.
  Future<DeliveryReport> flush({Duration? timeout}) =>
      _runtime.flush(timeout ?? _runtime.options.delivery.flushTimeout);

  /// Stops recording, drains bounded work, and releases the owned exporter.
  Future<DeliveryReport> close() => _runtime.close();

  /// Whether collection currently accepts [signal].
  bool isCollectionEnabled(ChroniclerSignal signal) => _runtime.isCollectionEnabled(signal);

  /// Enables or disables collection for [signal] synchronously.
  // API contract uses a positional boolean for symmetric runtime toggles.
  // ignore: avoid_positional_boolean_parameters
  void setCollectionEnabled(ChroniclerSignal signal, bool enabled) =>
      _runtime.setCollectionEnabled(signal, enabled);

  /// Enables or disables trace-context propagation independently of collection.
  // API contract uses a positional boolean for symmetric runtime toggles.
  // ignore: avoid_positional_boolean_parameters
  void setPropagationEnabled(bool enabled) => _runtime.setPropagationEnabled(enabled);
}

/// Borrowed immutable attribution view over one Chronicler runtime.
final class ChroniclerRecorder {
  const ChroniclerRecorder._(this._runtime, this._attribution);

  final ChroniclerRuntime _runtime;
  final _RecorderAttribution _attribution;

  /// Metric instruments shared by this recorder's application runtime.
  ChroniclerMetrics get metrics => _runtime.metrics;

  /// Runs [run] in a new root trace and records its callback lifetime.
  Future<T> trace<T>(
    String name, {
    required FutureOr<T> Function(ChroniclerRecorder recorder) run,
    RemoteTraceParent? parent,
    SpanKind kind = SpanKind.internal,
    Map<String, Object?> attributes = const {},
  }) => _runtime._runSpan(
    this,
    name,
    kind: kind,
    attributes: attributes,
    forceRoot: true,
    remoteParent: parent,
    run: run,
  );

  /// Runs [run] synchronously in a new root trace.
  T traceSync<T>(
    String name, {
    required T Function(ChroniclerRecorder recorder) run,
    RemoteTraceParent? parent,
    SpanKind kind = SpanKind.internal,
    Map<String, Object?> attributes = const {},
  }) => _runtime._runSpanSync(
    this,
    name,
    kind: kind,
    attributes: attributes,
    forceRoot: true,
    remoteParent: parent,
    run: run,
  );

  /// Runs [run] in a child span, or a new root when no span is active.
  Future<T> span<T>(
    String name, {
    required FutureOr<T> Function(ChroniclerRecorder recorder) run,
    SpanKind kind = SpanKind.internal,
    Map<String, Object?> attributes = const {},
  }) => _runtime._runSpan(
    this,
    name,
    kind: kind,
    attributes: attributes,
    forceRoot: false,
    remoteParent: null,
    run: run,
  );

  /// Runs [run] synchronously in a child span, or a new root when inactive.
  T spanSync<T>(
    String name, {
    required T Function(ChroniclerRecorder recorder) run,
    SpanKind kind = SpanKind.internal,
    Map<String, Object?> attributes = const {},
  }) => _runtime._runSpanSync(
    this,
    name,
    kind: kind,
    attributes: attributes,
    forceRoot: false,
    remoteParent: null,
    run: run,
  );

  /// Marks the active callback-managed span as failed.
  void setSpanError() => _runtime._setSpanError(_attribution.span);

  /// Replaces one attribute on the active callback-managed span.
  void setSpanAttribute(String key, Object? value) =>
      _runtime._setSpanAttributes(_attribution.span, {key: value});

  /// Atomically merges [attributes] into the active callback-managed span.
  void setSpanAttributes(Map<String, Object?> attributes) =>
      _runtime._setSpanAttributes(_attribution.span, attributes);

  /// Returns a cleaned carrier containing this active span's W3C metadata.
  Map<String, String> injectTrace(Map<String, String> headers) =>
      _runtime._injectTrace(_attribution.span, headers);

  /// Returns a recorder whose analytics identity is exactly the supplied IDs.
  ///
  /// Omitted IDs are cleared. Runtime configuration and operation correlation
  /// remain shared with this recorder.
  ChroniclerRecorder withIdentity({
    String? userId,
    String? anonymousId,
    String? sessionId,
  }) => _runtime._withIdentity(
    this,
    userId: userId,
    anonymousId: anonymousId,
    sessionId: sessionId,
  );

  /// Records a structured log without waiting for transport work.
  void recordLog(
    LogSeverity severity,
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?> attributes = const {},
  }) => _runtime._recordLog(
    _attribution,
    severity,
    message,
    error: error,
    stackTrace: stackTrace,
    attributes: attributes,
  );

  /// Records an ordinary named product event without waiting for transport.
  void recordEvent(
    String name, {
    Map<String, Object?> properties = const {},
  }) => _runtime._recordEvent(_attribution, name, properties: properties);

  /// Records an explicit error occurrence without waiting for transport.
  void recordError(
    Object error, {
    StackTrace? stackTrace,
    bool handled = true,
    List<ChroniclerCause> causes = const [],
    Map<String, Object?> attributes = const {},
  }) => _runtime._recordError(
    _attribution,
    error,
    stackTrace: stackTrace,
    handled: handled,
    causes: causes,
    attributes: attributes,
  );

  /// Records an explicit anonymous-to-user association.
  void identify({required String anonymousId, required String userId}) =>
      _runtime._recordIdentityLink(
        _attribution,
        anonymousId: anonymousId,
        userId: userId,
      );

  /// Records explicit user properties to set for [userId].
  void setUserProperties({
    required String userId,
    required Map<String, Object?> properties,
  }) => _runtime._recordUserPropertiesSet(
    _attribution,
    userId: userId,
    properties: properties,
  );

  /// Records explicit user-property removals for [userId].
  void unsetUserProperties({
    required String userId,
    required List<String> keys,
  }) => _runtime._recordUserPropertiesUnset(
    _attribution,
    userId: userId,
    keys: keys,
  );
}

final class _RecorderAttribution {
  const _RecorderAttribution({
    this.userId,
    this.anonymousId,
    this.sessionId,
    this.traceId,
    this.spanId,
    this.span,
  });

  final String? userId;
  final String? anonymousId;
  final String? sessionId;
  final String? traceId;
  final String? spanId;
  final _SpanState? span;
}

/// Coordinates capture and tracing with metric aggregation and delivery.
///
/// Record processing owns hook execution and redaction; delivery owns queue
/// state, flush snapshots, and exporter shutdown.
final class ChroniclerRuntime {
  ChroniclerRuntime._({
    required this.appId,
    required this.release,
    required this.source,
    required this.exporter,
    required this.buildId,
    required this.options,
    required this._secureRandom,
  }) : validator = RecordValidator(
         options.limits,
         maxSnapshotBytes: options.delivery.maxRecordBytes,
       ),
       codec = ChroniclerCodec(
         limits: options.limits,
         metricOptions: options.metrics,
         maxRecordBytes: options.delivery.maxRecordBytes,
         maxBatchBytes: options.delivery.maxBatchBytes,
         maxBatchRecords: options.delivery.maxBatchRecords,
       ),
       diagnostics = DiagnosticChannel(options.diagnostics);

  /// Validates [options] and creates a running delivery state machine.
  factory ChroniclerRuntime.create({
    required String appId,
    required String release,
    required ChroniclerSource source,
    required ChroniclerExporter exporter,
    required String? buildId,
    required ChroniclerOptions options,
    Random Function()? secureRandomFactory,
  }) {
    final snapshot = validateAndSnapshotOptions(options);
    final validator = RecordValidator(snapshot.limits);
    validateConfiguredLabel(validator, appId, 'appId', snapshot.limits.maxIdBytes);
    validateConfiguredLabel(validator, release, 'release', snapshot.limits.maxLabelBytes);
    if (buildId != null) {
      validateConfiguredLabel(validator, buildId, 'buildId', snapshot.limits.maxLabelBytes);
    }
    final secureRandom = createSecureRandom(secureRandomFactory);
    return ChroniclerRuntime._(
      appId: appId,
      release: release,
      source: source,
      exporter: exporter,
      buildId: buildId,
      options: snapshot,
      secureRandom: secureRandom,
    );
  }

  /// Application identifier copied into every record envelope.
  final String appId;

  /// Application release copied into every record envelope.
  final String release;

  /// Runtime source copied into every record envelope.
  final ChroniclerSource source;

  /// Application exporter owned by this runtime.
  final ChroniclerExporter exporter;

  /// Optional build identifier copied into every record envelope.
  final String? buildId;

  /// Validated immutable runtime options.
  final ChroniclerOptions options;

  /// Validator used before records enter delivery.
  final RecordValidator validator;

  /// Canonical codec used for size accounting and transport values.
  final ChroniclerCodec codec;

  /// Payload-free runtime diagnostic channel.
  final DiagnosticChannel diagnostics;

  /// Runtime-owned metric registry.
  late final MetricAggregation _metrics = MetricAggregation(
    options: options.metrics,
    limits: options.limits,
    canRecord: () => _canRecord(ChroniclerSignal.metrics, null),
    diagnose: diagnostics.record,
    redact: _processor.redactAttributes,
    createRecord: _metricRecord,
    finalize: _finalizeAndEnqueue,
    startEnabled: _enabledSignals.contains(ChroniclerSignal.metrics),
    now: () => _now,
    elapsed: () => _elapsedNow,
  );

  /// Metric instrument contracts borrowed by recorders and Context.
  ChroniclerMetrics get metrics => _metrics;
  late final RecordProcessor _processor = RecordProcessor(
    codec: codec,
    redaction: options.redaction,
    maxRecordBytes: options.delivery.maxRecordBytes,
  );

  late final DeliveryQueue _delivery = DeliveryQueue(
    options: options.delivery,
    exporter: exporter,
    diagnostics: diagnostics,
    elapsed: () => _elapsed.elapsed,
    nextRandom: () => _random.nextDouble(),
  );

  ChroniclerRuntimeState get _state => _delivery.state;

  Random _secureRandom;
  final _liveSpans = <_SpanState>{};
  final _flushFinalizations = Queue<List<ChroniclerRecord>>();
  final _elapsed = Stopwatch()..start();
  DateTime Function()? _nowOverride;
  Duration Function()? _elapsedOverride;
  late final Set<ChroniclerSignal> _enabledSignals = Set.of(options.enabledSignals);
  late bool _propagationEnabled = options.tracing.propagationEnabled;
  Random _random = Random();
  MetricRecord Function(MetricPayload payload)? _metricRecordOverride;

  /// An immutable snapshot of exact diagnostic counts.
  Map<DiagnosticReason, BigInt> get diagnosticCounts => diagnostics.counts;

  DateTime get _now => (_nowOverride?.call() ?? DateTime.now()).toUtc();

  Duration get _elapsedNow => _elapsedOverride?.call() ?? _elapsed.elapsed;

  ChroniclerRecorder _withIdentity(
    ChroniclerRecorder recorder, {
    String? userId,
    String? anonymousId,
    String? sessionId,
  }) {
    try {
      for (final MapEntry(:key, :value) in {
        'userId': userId,
        'anonymousId': anonymousId,
        'sessionId': sessionId,
      }.entries) {
        if (value != null) _validateRequiredId(value, key);
      }
    } on RecordValidationException catch (error) {
      throw ChroniclerConfigurationException('identity', error.reason);
    }
    return ChroniclerRecorder._(
      this,
      _RecorderAttribution(
        userId: userId,
        anonymousId: anonymousId,
        sessionId: sessionId,
        traceId: recorder._attribution.traceId,
        spanId: recorder._attribution.spanId,
        span: recorder._attribution.span,
      ),
    );
  }

  Future<T> _runSpan<T>(
    ChroniclerRecorder recorder,
    String name, {
    required SpanKind kind,
    required Map<String, Object?> attributes,
    required bool forceRoot,
    required RemoteTraceParent? remoteParent,
    required FutureOr<T> Function(ChroniclerRecorder recorder) run,
  }) async {
    final started = _startSpan(
      recorder,
      name,
      kind: kind,
      attributes: attributes,
      forceRoot: forceRoot,
      remoteParent: remoteParent,
    );
    try {
      final result = run(started.recorder);
      final value = await result;
      _finishSpan(started.state, SpanStatus.success);
      return value;
    } on Object catch (error) {
      _finishSpan(started.state, _failureStatus(error));
      rethrow;
    }
  }

  T _runSpanSync<T>(
    ChroniclerRecorder recorder,
    String name, {
    required SpanKind kind,
    required Map<String, Object?> attributes,
    required bool forceRoot,
    required RemoteTraceParent? remoteParent,
    required T Function(ChroniclerRecorder recorder) run,
  }) {
    final started = _startSpan(
      recorder,
      name,
      kind: kind,
      attributes: attributes,
      forceRoot: forceRoot,
      remoteParent: remoteParent,
    );
    try {
      final result = run(started.recorder);
      if (result is Future) {
        diagnostics.record(DiagnosticReason.syncCallbackReturnedFuture);
      }
      _finishSpan(started.state, SpanStatus.success);
      return result;
    } on Object catch (error) {
      _finishSpan(started.state, _failureStatus(error));
      rethrow;
    }
  }

  SpanStatus _failureStatus(Object error) {
    final classifier = options.tracing.isCancellation;
    if (classifier == null) return SpanStatus.error;
    try {
      return classifier(error) ? SpanStatus.cancelled : SpanStatus.error;
    } on Object {
      diagnostics.record(DiagnosticReason.cancellationClassifierFailed);
      return SpanStatus.error;
    }
  }

  _StartedSpan _startSpan(
    ChroniclerRecorder recorder,
    String name, {
    required SpanKind kind,
    required Map<String, Object?> attributes,
    required bool forceRoot,
    required RemoteTraceParent? remoteParent,
  }) {
    if (_state != ChroniclerRuntimeState.running) {
      diagnostics.record(DiagnosticReason.runtimeClosed);
      return _StartedSpan(null, recorder);
    }
    if (_processor.insideHook || diagnostics.insideCallback) {
      diagnostics.record(DiagnosticReason.reentrantRecording);
      return _StartedSpan(null, recorder);
    }
    final acceptedRemote = forceRoot && _propagationEnabled ? remoteParent : null;
    final current = recorder._attribution.span;
    final activeParent = !forceRoot && current != null && !current.ended ? current : null;
    late final String traceId;
    late final String spanId;
    try {
      traceId = acceptedRemote?.traceId ?? activeParent?.traceId ?? _traceId();
      spanId = _spanId();
    } on Object {
      diagnostics.record(DiagnosticReason.invalidRecord);
      return _StartedSpan(null, recorder);
    }
    final collectionEnabled = _enabledSignals.contains(ChroniclerSignal.traces);
    late final bool sampled;
    try {
      sampled = activeParent == null
          ? _selectBoundarySampling(acceptedRemote, collectionEnabled)
          : activeParent.lineageRecording && activeParent.sampled;
    } on Object {
      diagnostics.record(DiagnosticReason.invalidRecord);
      return _StartedSpan(null, recorder);
    }
    final lineageRecording = activeParent?.lineageRecording ?? (collectionEnabled && sampled);
    _SpanRecordingState? recording;
    if (lineageRecording) {
      try {
        validator.validateString(name, options.limits.maxLabelBytes, 'span name');
        if (name.isEmpty) {
          throw const RecordValidationException('span name must be nonempty');
        }
        recording = _SpanRecordingState(
          eventId: ChronoID.generate(prefix: 'evt'),
          name: name,
          kind: kind,
          attributes: _processor.redactAttributes(validator.snapshotAttributes(attributes)),
          startedAt: _elapsedNow,
          timestamp: _now,
          attribution: recorder._attribution,
        );
      } on Object {
        diagnostics.record(DiagnosticReason.invalidRecord);
      }
    }
    final state = _SpanState(
      traceId: traceId,
      spanId: spanId,
      parentSpanId: acceptedRemote?.parentSpanId ?? activeParent?.spanId,
      lineageRecording: lineageRecording,
      sampled: sampled,
      tracestate: acceptedRemote?.tracestate ?? activeParent?.tracestate ?? const [],
      recording: recording,
    );
    _liveSpans.add(state);
    return _StartedSpan(
      state,
      ChroniclerRecorder._(
        this,
        _RecorderAttribution(
          userId: recorder._attribution.userId,
          anonymousId: recorder._attribution.anonymousId,
          sessionId: recorder._attribution.sessionId,
          traceId: traceId,
          spanId: spanId,
          span: state,
        ),
      ),
    );
  }

  void _finishSpan(_SpanState? span, SpanStatus status) {
    if (span == null) return;
    if (span.ended) return;
    span.ended = true;
    _liveSpans.remove(span);
    final recording = span.recording;
    if (recording == null) return;
    final finalStatus = status == SpanStatus.success && span.explicitError
        ? SpanStatus.error
        : status;
    final durationMicros = (_elapsedNow - recording.startedAt).inMicroseconds;
    _finalizeAndEnqueue(
      _spanRecord(
        span,
        recording,
        status: finalStatus,
        durationMicros: durationMicros,
        attributes: recording.attributes,
      ),
    );
  }

  void _setSpanError(_SpanState? span) {
    if (!_canUpdateSpan(span)) return;
    span!.explicitError = true;
  }

  void _setSpanAttributes(_SpanState? span, Map<String, Object?> update) {
    if (!_canUpdateSpan(span)) return;
    final recording = span!.recording;
    if (recording == null) return;
    try {
      final proposed = <String, Object?>{...recording.attributes, ...update};
      final snapshot = _processor.redactAttributes(validator.snapshotAttributes(proposed));
      final reserved = _spanRecord(
        span,
        recording,
        status: SpanStatus.cancelled,
        durationMicros: 9007199254740991,
        attributes: snapshot,
      );
      codec
        ..validateRecord(reserved)
        ..encodeRecord(reserved);
      recording.attributes = snapshot;
    } on Object {
      diagnostics.record(DiagnosticReason.invalidSpanUpdate);
    }
  }

  bool _canUpdateSpan(_SpanState? span) {
    if (span == null) {
      diagnostics.record(DiagnosticReason.noActiveSpan);
      return false;
    }
    if (span.ended) {
      diagnostics.record(DiagnosticReason.invalidSpanUpdate);
      return false;
    }
    return true;
  }

  SpanRecord _spanRecord(
    _SpanState span,
    _SpanRecordingState recording, {
    required SpanStatus status,
    required int durationMicros,
    required Map<String, Object?> attributes,
  }) {
    final attribution = recording.attribution;
    return SpanRecord(
      envelope: RecordEnvelope(
        eventId: recording.eventId,
        appId: appId,
        release: release,
        source: source,
        timestamp: recording.timestamp,
        buildId: buildId,
        userId: attribution.userId,
        anonymousId: attribution.anonymousId,
        sessionId: attribution.sessionId,
        traceId: span.traceId,
        spanId: span.spanId,
        parentSpanId: span.parentSpanId,
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
    final rate = options.sampling.traces;
    final sampled = rate == 1 || rate > 0 && _random.nextDouble() < rate;
    if (!sampled) diagnostics.record(DiagnosticReason.sampledOut);
    return sampled;
  }

  bool _selectBoundarySampling(RemoteTraceParent? parent, bool collectionEnabled) {
    if (!collectionEnabled) return false;
    if (parent == null || !options.tracing.honorRemoteSampling) {
      return _selectLocalTraceSampling();
    }
    if (!parent.sampled) diagnostics.record(DiagnosticReason.sampledOut);
    return parent.sampled;
  }

  Map<String, String> _injectTrace(_SpanState? span, Map<String, String> headers) {
    final result = <String, String>{
      for (final MapEntry(:key, :value) in headers.entries)
        if (key.toLowerCase() != 'traceparent' && key.toLowerCase() != 'tracestate') key: value,
    };
    if (!_propagationEnabled || span == null || span.ended) return result;
    result['traceparent'] = '00-${span.traceId}-${span.spanId}-${span.sampled ? '01' : '00'}';
    if (span.tracestate.isNotEmpty) result['tracestate'] = span.tracestate.join(',');
    return result;
  }

  String _randomHex(int byteCount) {
    for (var attempt = 0; attempt < 8; attempt++) {
      final bytes = List<int>.generate(byteCount, (_) => _secureRandom.nextInt(256));
      if (bytes.any((byte) => byte != 0)) {
        return bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
      }
    }
    throw StateError('Secure randomness produced only zero identifiers');
  }

  /// Flushes the current record snapshot within [timeout].
  Future<DeliveryReport> flush(Duration timeout) {
    _requireOutsideCallback('flush');
    return _delivery.flush(timeout, finalize: () => _sealRecords(closing: false));
  }

  /// Stops recording and closes the owned exporter within one deadline.
  Future<DeliveryReport> close() {
    _requireOutsideCallback('close');
    return _delivery.close(finalize: () => _sealRecords(closing: true));
  }

  List<DeliveryDisposition> _sealRecords({required bool closing}) {
    final finalized = <DeliveryDisposition>[];
    final finalize = closing ? _finalizeForClose : _finalizeForFlush;
    for (final record in _metrics.seal(scheduleNext: !closing)) {
      finalized.add(finalize(record));
    }
    while (_flushFinalizations.isNotEmpty) {
      for (final record in _flushFinalizations.removeFirst()) {
        finalized.add(finalize(record));
      }
    }
    return finalized;
  }

  /// Whether collection currently accepts [signal].
  bool isCollectionEnabled(ChroniclerSignal signal) => _enabledSignals.contains(signal);

  /// Enables or disables collection for [signal].
  // API contract uses a positional boolean for symmetric runtime toggles.
  // ignore: avoid_positional_boolean_parameters
  void setCollectionEnabled(ChroniclerSignal signal, bool enabled) {
    _requireRunningConfiguration();
    if (enabled == _enabledSignals.contains(signal)) return;
    if (enabled) {
      _enabledSignals.add(signal);
      if (signal == ChroniclerSignal.metrics) _metrics.enable();
      return;
    }
    _enabledSignals.remove(signal);
    if (signal == ChroniclerSignal.metrics) _metrics.disable();
    if (signal == ChroniclerSignal.traces) {
      for (final span in _liveSpans) {
        span
          ..recording = null
          ..lineageRecording = false;
      }
    }
    _delivery.disableCollection(signal);
  }

  /// Enables or disables trace-context propagation.
  // API contract uses a positional boolean for symmetric runtime toggles.
  // ignore: avoid_positional_boolean_parameters
  void setPropagationEnabled(bool enabled) {
    _requireRunningConfiguration();
    _propagationEnabled = enabled;
  }

  void _requireRunningConfiguration() {
    _requireOutsideCallback('configuration');
    if (_state != ChroniclerRuntimeState.running) {
      throw const ChroniclerConfigurationException(
        'lifecycle',
        'does not allow configuration changes',
      );
    }
  }

  void _requireOutsideCallback(String operation) {
    if (_processor.insideHook || diagnostics.insideCallback) {
      throw ChroniclerConfigurationException(
        operation,
        'cannot be called from a Chronicler callback',
      );
    }
  }

  void _recordLog(
    _RecorderAttribution attribution,
    LogSeverity severity,
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?> attributes = const {},
  }) {
    if (!_canRecord(ChroniclerSignal.logs, options.sampling.logs)) return;
    try {
      validator.validateString(message, options.limits.maxStringBytes, 'message');
      final snapshot = validator.snapshotAttributes(attributes);
      final details = error == null ? null : _convertError(error, stackTrace);
      final standaloneStack = error == null && stackTrace != null
          ? _safeText(stackTrace.toString, '[Stack trace unavailable]')
          : null;
      if (standaloneStack != null) {
        validator.validateString(
          standaloneStack,
          options.limits.maxStackTraceBytes,
          'stackTrace',
        );
      }
      final record = LogRecord(
        envelope: _envelope(attribution),
        payload: LogPayload(
          severity: severity,
          message: message,
          attributes: snapshot,
          error: details,
          stackTrace: standaloneStack,
        ),
      );
      _finalizeAndEnqueue(record);
    } on RecordValidationException {
      diagnostics.record(DiagnosticReason.invalidRecord);
    } on Object {
      diagnostics.record(DiagnosticReason.invalidRecord);
    }
  }

  void _recordError(
    _RecorderAttribution attribution,
    Object error, {
    StackTrace? stackTrace,
    bool handled = true,
    List<ChroniclerCause> causes = const [],
    Map<String, Object?> attributes = const {},
  }) {
    if (!_canRecord(ChroniclerSignal.errors, null)) return;
    try {
      if (causes.length > options.limits.maxCauses) {
        throw const RecordValidationException('too many causes');
      }
      final record = ErrorRecord(
        envelope: _envelope(attribution),
        payload: ErrorPayload(
          error: _convertError(error, stackTrace),
          handled: handled,
          causes: causes.map(
            (cause) => _convertError(cause.error, cause.stackTrace),
          ),
          attributes: validator.snapshotAttributes(attributes),
        ),
      );
      _finalizeAndEnqueue(record);
    } on RecordValidationException {
      diagnostics.record(DiagnosticReason.invalidRecord);
    } on Object {
      diagnostics.record(DiagnosticReason.invalidRecord);
    }
  }

  void _recordEvent(
    _RecorderAttribution attribution,
    String name, {
    Map<String, Object?> properties = const {},
  }) {
    if (!_canRecord(ChroniclerSignal.events, options.sampling.events)) return;
    try {
      validator.validateString(name, options.limits.maxLabelBytes, 'event name');
      if (name.isEmpty) {
        throw const RecordValidationException('event name must be nonempty');
      }
      final snapshot = validator.snapshotAttributes(properties);
      _finalizeAndEnqueue(
        ProductEventRecord(
          envelope: _envelope(attribution),
          payload: ProductEventPayload(name: name, properties: snapshot),
        ),
      );
    } on RecordValidationException {
      diagnostics.record(DiagnosticReason.invalidRecord);
    } on Object {
      diagnostics.record(DiagnosticReason.invalidRecord);
    }
  }

  void _recordIdentityLink(
    _RecorderAttribution attribution, {
    required String anonymousId,
    required String userId,
  }) {
    _recordEventControl(() {
      _validateRequiredId(anonymousId, 'anonymousId');
      _validateRequiredId(userId, 'userId');
      return IdentityLinkRecord(
        envelope: _envelope(attribution),
        payload: IdentityLinkPayload(anonymousId: anonymousId, userId: userId),
      );
    });
  }

  void _recordUserPropertiesSet(
    _RecorderAttribution attribution, {
    required String userId,
    required Map<String, Object?> properties,
  }) {
    if (properties.isEmpty) return;
    _recordEventControl(() {
      _validateRequiredId(userId, 'userId');
      final snapshot = validator.snapshotAttributes(properties);
      return UserPropertiesSetRecord(
        envelope: _envelope(attribution),
        payload: UserPropertiesSetPayload(userId: userId, properties: snapshot),
      );
    });
  }

  void _recordUserPropertiesUnset(
    _RecorderAttribution attribution, {
    required String userId,
    required List<String> keys,
  }) {
    if (keys.isEmpty) return;
    _recordEventControl(() {
      _validateRequiredId(userId, 'userId');
      final distinctKeys = <String>{};
      for (final key in keys) {
        validator.validateString(key, options.limits.maxKeyBytes, 'property key');
        if (key.isEmpty) {
          throw const RecordValidationException('property key must be nonempty');
        }
        distinctKeys.add(key);
      }
      if (distinctKeys.length > options.limits.maxListItems) {
        throw const RecordValidationException('property key list item limit exceeded');
      }
      return UserPropertiesUnsetRecord(
        envelope: _envelope(attribution),
        payload: UserPropertiesUnsetPayload(userId: userId, keys: distinctKeys),
      );
    });
  }

  void _recordEventControl(ChroniclerRecord Function() createRecord) {
    if (!_canRecord(ChroniclerSignal.events, null)) return;
    try {
      _finalizeAndEnqueue(createRecord());
    } on RecordValidationException {
      diagnostics.record(DiagnosticReason.invalidRecord);
    } on Object {
      diagnostics.record(DiagnosticReason.invalidRecord);
    }
  }

  void _validateRequiredId(String value, String name) {
    validator.validateString(value, options.limits.maxIdBytes, name);
    if (value.isEmpty) throw RecordValidationException('$name must be nonempty');
  }

  bool _canRecord(ChroniclerSignal signal, double? sampleRate) {
    if (_state != ChroniclerRuntimeState.running) {
      diagnostics.record(DiagnosticReason.runtimeClosed);
      return false;
    }
    if (diagnostics.insideCallback || _processor.insideHook) {
      diagnostics.record(DiagnosticReason.reentrantRecording);
      return false;
    }
    return _allowsCapture(signal, sampleRate);
  }

  RecordEnvelope _envelope(_RecorderAttribution attribution) => RecordEnvelope(
    eventId: ChronoID.generate(prefix: 'evt'),
    appId: appId,
    release: release,
    source: source,
    timestamp: DateTime.now().toUtc(),
    buildId: buildId,
    userId: attribution.userId,
    anonymousId: attribution.anonymousId,
    sessionId: attribution.sessionId,
    traceId: attribution.traceId,
    spanId: attribution.spanId,
  );

  MetricRecord _metricRecord(MetricPayload payload) =>
      _metricRecordOverride?.call(payload) ??
      MetricRecord(
        envelope: RecordEnvelope(
          eventId: ChronoID.generate(prefix: 'evt'),
          appId: appId,
          release: release,
          source: source,
          timestamp: payload.intervalEnd,
          buildId: buildId,
        ),
        payload: payload,
      );

  bool _allowsCapture(ChroniclerSignal signal, double? sampleRate) {
    if (!_enabledSignals.contains(signal)) {
      diagnostics.record(DiagnosticReason.collectionDisabled);
      return false;
    }
    if (sampleRate != null &&
        (sampleRate == 0 || sampleRate < 1 && _random.nextDouble() >= sampleRate)) {
      diagnostics.record(DiagnosticReason.sampledOut);
      return false;
    }
    return true;
  }

  void _captureFixture(ChroniclerRecord record) {
    if (_state != ChroniclerRuntimeState.running) {
      diagnostics.record(DiagnosticReason.runtimeClosed);
      return;
    }
    final signal = _signalFor(record);
    final sampleRate = switch (record) {
      LogRecord() => options.sampling.logs,
      ProductEventRecord() => options.sampling.events,
      SpanRecord() => options.sampling.traces,
      _ => null,
    };
    if (_allowsCapture(signal, sampleRate)) _finalizeAndEnqueue(record);
  }

  ChroniclerSignal _signalFor(ChroniclerRecord record) => switch (record.signalKind) {
    ChroniclerSignalKind.logs => ChroniclerSignal.logs,
    ChroniclerSignalKind.events => ChroniclerSignal.events,
    ChroniclerSignalKind.traces => ChroniclerSignal.traces,
    ChroniclerSignalKind.errors => ChroniclerSignal.errors,
    ChroniclerSignalKind.metrics => ChroniclerSignal.metrics,
  };

  DeliveryDisposition _finalizeForFlush(ChroniclerRecord record) {
    if (!_enabledSignals.contains(_signalFor(record))) {
      return _delivery.dropped(DropReason.collectionDisabled);
    }
    return _finalizeAndEnqueue(record);
  }

  DeliveryDisposition _finalizeForClose(ChroniclerRecord record) {
    if (!_enabledSignals.contains(_signalFor(record))) {
      return _delivery.dropped(DropReason.collectionDisabled);
    }
    return _finalizeAndEnqueue(record, allowDuringClosing: true);
  }

  DeliveryDisposition _finalizeAndEnqueue(
    ChroniclerRecord original, {
    bool allowDuringClosing = false,
  }) {
    if (_state != ChroniclerRuntimeState.running && !allowDuringClosing) {
      return _delivery.dropped(DropReason.runtimeClosed);
    }
    try {
      return switch (_processor.prepare(original)) {
        PreparedRecord(:final record, :final encodedBytes) => _delivery.enqueue(
          record,
          encodedBytes,
          allowDuringClosing: allowDuringClosing,
        ),
        RejectedRecord(:final reason) => _delivery.dropped(reason),
      };
    } on Object {
      return _delivery.dropped(DropReason.invalidRecord);
    }
  }

  ErrorDetails _convertError(Object error, StackTrace? stackTrace) {
    final type = _safeText(() => error.runtimeType.toString(), '[Unknown error type]');
    final message = _safeText(error.toString, '[Error message unavailable]');
    final stack = stackTrace == null
        ? null
        : _safeText(stackTrace.toString, '[Stack trace unavailable]');
    validator
      ..validateString(type, options.limits.maxLabelBytes, 'error type')
      ..validateString(message, options.limits.maxErrorMessageBytes, 'error message');
    if (stack != null) {
      validator.validateString(stack, options.limits.maxStackTraceBytes, 'error stackTrace');
    }
    return ErrorDetails(type: type, message: message, stackTrace: stack);
  }

  String _safeText(String Function() convert, String fallback) {
    try {
      return convert();
    } on Object {
      diagnostics.record(DiagnosticReason.textConversionFailed);
      return fallback;
    }
  }
}

/// Internal fixture bridge used by sibling-signal contract tests.
final class ChroniclerCaptureFixture {
  const ChroniclerCaptureFixture._();

  /// Submits a finalized sibling-signal [record] through capture policy.
  static void capture(Chronicler chronicler, ChroniclerRecord record) =>
      chronicler._runtime._captureFixture(record);

  /// Returns a recorder with valid operation correlation for identity tests.
  static ChroniclerRecorder withCorrelation(
    ChroniclerRecorder recorder, {
    required String traceId,
    required String spanId,
  }) => ChroniclerRecorder._(
    recorder._runtime,
    _RecorderAttribution(
      userId: recorder._attribution.userId,
      anonymousId: recorder._attribution.anonymousId,
      sessionId: recorder._attribution.sessionId,
      traceId: traceId,
      spanId: spanId,
    ),
  );
}

/// Internal fixture bridge for deterministic tracing tests.
final class ChroniclerTracingFixture {
  const ChroniclerTracingFixture._();

  /// Creates a runtime using [secureRandom] for startup validation and IDs.
  static Chronicler create({
    required String appId,
    required String release,
    required ChroniclerSource source,
    required ChroniclerExporter exporter,
    required Random Function() secureRandom,
    ChroniclerOptions options = const ChroniclerOptions(),
  }) => Chronicler._fromRuntime(
    ChroniclerRuntime.create(
      appId: appId,
      release: release,
      source: source,
      exporter: exporter,
      buildId: null,
      options: options,
      secureRandomFactory: secureRandom,
    ),
  );

  /// Replaces wall and monotonic clocks for span-lifetime tests.
  static void overrideClocks(
    Chronicler chronicler, {
    required DateTime Function() now,
    required Duration Function() elapsed,
  }) {
    chronicler._runtime
      .._nowOverride = now
      .._elapsedOverride = elapsed;
  }

  /// Replaces the ID source after setup for recording-failure tests.
  static void overrideSecureRandom(Chronicler chronicler, Random random) {
    chronicler._runtime._secureRandom = random;
  }

  /// Replaces the root sampling source for whole-trace tests.
  static void overrideSamplingRandom(Chronicler chronicler, Random random) {
    chronicler._runtime._random = random;
  }

  /// Returns the number of payload attributes retained by [recorder]'s span.
  static int retainedAttributeCount(ChroniclerRecorder recorder) =>
      recorder._attribution.span?.recording?.attributes.length ?? 0;
}

final class _StartedSpan {
  const _StartedSpan(this.state, this.recorder);

  final _SpanState? state;
  final ChroniclerRecorder recorder;
}

final class _SpanState {
  _SpanState({
    required this.traceId,
    required this.spanId,
    required this.parentSpanId,
    required this.lineageRecording,
    required this.sampled,
    required this.tracestate,
    required this.recording,
  });

  final String traceId;
  final String spanId;
  final String? parentSpanId;
  bool lineageRecording;
  final bool sampled;
  final List<String> tracestate;
  _SpanRecordingState? recording;
  bool ended = false;
  bool explicitError = false;
}

final class _SpanRecordingState {
  _SpanRecordingState({
    required this.eventId,
    required this.name,
    required this.kind,
    required this.attributes,
    required this.startedAt,
    required this.timestamp,
    required this.attribution,
  });

  final String eventId;
  final String name;
  final SpanKind kind;
  Map<String, Object?> attributes;
  final Duration startedAt;
  final DateTime timestamp;
  final _RecorderAttribution attribution;
}

/// Internal fixture bridge for deterministic delivery tests.
final class ChroniclerDeliveryFixture {
  const ChroniclerDeliveryFixture._();

  /// Replaces retry jitter selection for deterministic delivery tests.
  static void selectRetryDelay(
    Chronicler chronicler,
    Duration Function(int attempt, Duration ceiling) selector,
  ) {
    chronicler._runtime._delivery.selectRetryDelay(selector);
  }

  /// Returns the current trace propagation switch.
  static bool propagationEnabled(Chronicler chronicler) => chronicler._runtime._propagationEnabled;

  /// Queues [records] for internal finalization during the next flush.
  static void finalizeOnNextFlush(
    Chronicler chronicler,
    Iterable<ChroniclerRecord> records,
  ) {
    chronicler._runtime._flushFinalizations.add(List.unmodifiable(records));
  }

  /// Returns the number of flush calls waiting on record dispositions.
  static int activeFlushes(Chronicler chronicler) => chronicler._runtime._delivery.activeFlushes;
}

/// Internal fixture bridge for deterministic metric aggregation tests.
final class ChroniclerMetricFixture {
  const ChroniclerMetricFixture._();

  /// Replaces wall and monotonic clocks before accessing metric instruments.
  static void overrideClocks(
    Chronicler chronicler, {
    required DateTime Function() now,
    required Duration Function() elapsed,
  }) {
    chronicler._runtime
      .._nowOverride = now
      .._elapsedOverride = elapsed;
  }

  /// Rotates the current interval synchronously and stops its next timer.
  static void rotate(Chronicler chronicler) {
    chronicler._runtime._metrics.rotateForTesting();
  }

  /// Makes the next metric record construction fail.
  static void failNextRecordCreation(Chronicler chronicler) {
    chronicler._runtime._metricRecordOverride = (payload) {
      chronicler._runtime._metricRecordOverride = null;
      throw StateError('metric record construction failed');
    };
  }

  /// Places an existing counter series at an arithmetic boundary.
  static void setCounterAggregate(
    Chronicler chronicler, {
    required int count,
    required String name,
    required double sum,
    Map<String, Object?> attributes = const {},
  }) {
    chronicler._runtime._metrics.setCounterAggregateForTesting(
      name: name,
      attributes: attributes,
      count: count,
      sum: sum,
    );
  }

  /// Places an existing series at the portable observation-count boundary.
  static void setSeriesCount(
    Chronicler chronicler, {
    required int count,
    required String name,
    Map<String, Object?> attributes = const {},
  }) {
    chronicler._runtime._metrics.setSeriesCountForTesting(
      name: name,
      attributes: attributes,
      count: count,
    );
  }

  /// Places an existing histogram at an aggregate arithmetic boundary.
  static void setHistogramAggregate(
    Chronicler chronicler, {
    required List<int> bucketCounts,
    required int count,
    required double max,
    required double min,
    required String name,
    required double sum,
    Map<String, Object?> attributes = const {},
  }) {
    chronicler._runtime._metrics.setHistogramAggregateForTesting(
      name: name,
      attributes: attributes,
      count: count,
      bucketCounts: bucketCounts,
      sum: sum,
      min: min,
      max: max,
    );
  }
}
