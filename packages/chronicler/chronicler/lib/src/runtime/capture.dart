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
import 'package:chronicler/src/runtime/attribution.dart';
import 'package:chronicler/src/runtime/configuration.dart';
import 'package:chronicler/src/runtime/delivery_queue.dart';
import 'package:chronicler/src/runtime/record_processing.dart';
import 'package:chronicler/src/runtime/tracing.dart';
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

  /// Trace lifetime owner used by borrowed recorder callbacks.
  TraceController get tracing => _tracing;

  late final TraceController _tracing = TraceController(
    appId: appId,
    release: release,
    source: source,
    buildId: buildId,
    options: options,
    validator: validator,
    codec: codec,
    diagnostics: diagnostics,
    processor: _processor,
    canStart: _canStartSpan,
    collectionEnabled: () => _enabledSignals.contains(ChroniclerSignal.traces),
    propagationEnabled: () => _propagationEnabled,
    now: () => _now,
    elapsed: () => _elapsedNow,
    nextRandom: () => _random.nextDouble(),
    nextSecureByte: () => _secureRandom.nextInt(256),
    finalize: _finalizeAndEnqueue,
  );

  bool _canStartSpan() {
    if (_state != ChroniclerRuntimeState.running) {
      diagnostics.record(DiagnosticReason.runtimeClosed);
      return false;
    }
    if (_processor.insideHook || diagnostics.insideCallback) {
      diagnostics.record(DiagnosticReason.reentrantRecording);
      return false;
    }
    return true;
  }

  Random _secureRandom;
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

  /// Validates replacement identity while preserving operation correlation.
  RecorderAttribution withIdentity(
    RecorderAttribution attribution, {
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
    return RecorderAttribution(
      userId: userId,
      anonymousId: anonymousId,
      sessionId: sessionId,
      traceId: attribution.traceId,
      spanId: attribution.spanId,
      span: attribution.span,
    );
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
      _tracing.disableCollection();
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

  /// Validates and captures a structured log with borrowed attribution.
  void recordLog(
    RecorderAttribution attribution,
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

  /// Snapshots an explicit error occurrence and its supplied causes.
  void recordError(
    RecorderAttribution attribution,
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

  /// Validates and captures a named product event.
  void recordEvent(
    RecorderAttribution attribution,
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

  /// Captures an explicit anonymous-to-user association.
  void recordIdentityLink(
    RecorderAttribution attribution, {
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

  /// Captures a nonempty explicit user-property update.
  void recordUserPropertiesSet(
    RecorderAttribution attribution, {
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

  /// Captures distinct explicit user-property removal keys.
  void recordUserPropertiesUnset(
    RecorderAttribution attribution, {
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

  RecordEnvelope _envelope(RecorderAttribution attribution) => RecordEnvelope(
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

/// Narrow test controls used by the existing fixture entrypoints.
final class RuntimeTestAccess {
  const RuntimeTestAccess._();

  /// Replaces wall and monotonic clocks for span and metric tests.
  static void overrideClocks(
    ChroniclerRuntime runtime, {
    required DateTime Function() now,
    required Duration Function() elapsed,
  }) {
    runtime
      .._nowOverride = now
      .._elapsedOverride = elapsed;
  }

  /// Replaces the ID source after startup validation.
  static void overrideSecureRandom(ChroniclerRuntime runtime, Random random) {
    runtime._secureRandom = random;
  }

  /// Replaces shared sampling and retry randomness.
  static void overrideSamplingRandom(ChroniclerRuntime runtime, Random random) {
    runtime._random = random;
  }

  /// Selects deterministic retry delays.
  static void selectRetryDelay(
    ChroniclerRuntime runtime,
    Duration Function(int attempt, Duration ceiling) selector,
  ) {
    runtime._delivery.selectRetryDelay(selector);
  }

  /// Queues internal records for the next synchronous finalization.
  static void finalizeOnNextFlush(
    ChroniclerRuntime runtime,
    Iterable<ChroniclerRecord> records,
  ) {
    runtime._flushFinalizations.add(List.unmodifiable(records));
  }

  /// Rotates metric state and cancels the next interval timer.
  static void rotate(ChroniclerRuntime runtime) {
    runtime._metrics.rotateForTesting();
  }

  /// Fails the next metric record construction, then restores it.
  static void failNextRecordCreation(ChroniclerRuntime runtime) {
    runtime._metricRecordOverride = (payload) {
      runtime._metricRecordOverride = null;
      throw StateError('metric record construction failed');
    };
  }

  /// Places an existing counter at an arithmetic boundary.
  static void setCounterAggregate(
    ChroniclerRuntime runtime, {
    required int count,
    required String name,
    required double sum,
    Map<String, Object?> attributes = const {},
  }) {
    runtime._metrics.setCounterAggregateForTesting(
      name: name,
      attributes: attributes,
      count: count,
      sum: sum,
    );
  }

  /// Places an existing series at an observation-count boundary.
  static void setSeriesCount(
    ChroniclerRuntime runtime, {
    required int count,
    required String name,
    Map<String, Object?> attributes = const {},
  }) {
    runtime._metrics.setSeriesCountForTesting(
      name: name,
      attributes: attributes,
      count: count,
    );
  }

  /// Places an existing histogram at aggregate arithmetic boundaries.
  static void setHistogramAggregate(
    ChroniclerRuntime runtime, {
    required List<int> bucketCounts,
    required int count,
    required double max,
    required double min,
    required String name,
    required double sum,
    Map<String, Object?> attributes = const {},
  }) {
    runtime._metrics.setHistogramAggregateForTesting(
      name: name,
      attributes: attributes,
      count: count,
      bucketCounts: bucketCounts,
      sum: sum,
      min: min,
      max: max,
    );
  }

  /// Current propagation switch for collection tests.
  static bool propagationEnabled(ChroniclerRuntime runtime) => runtime._propagationEnabled;

  /// Number of independently waiting flush snapshots.
  static int activeFlushes(ChroniclerRuntime runtime) => runtime._delivery.activeFlushes;

  /// Submits prebuilt records through ordinary signal capture policy.
  static void capture(ChroniclerRuntime runtime, ChroniclerRecord record) =>
      runtime._captureFixture(record);
}
