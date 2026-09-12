import 'dart:async';
import 'dart:math';

import 'package:chronicler/src/configuration.dart';
import 'package:chronicler/src/lifecycle.dart';
import 'package:chronicler/src/metrics.dart';
import 'package:chronicler/src/models.dart';
import 'package:chronicler/src/runtime/attribution.dart';
import 'package:chronicler/src/runtime/capture.dart';
import 'package:chronicler/src/runtime/tracing.dart';
import 'package:chronicler/src/trace_propagation.dart';
import 'package:chronicler/src/transport.dart';

export 'package:chronicler/src/runtime/capture.dart' show ChroniclerCause, ChroniclerRuntime;

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
    const RecorderAttribution(),
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
  final RecorderAttribution _attribution;

  /// Metric instruments shared by this recorder's application runtime.
  ChroniclerMetrics get metrics => _runtime.metrics;

  /// Runs [run] in a new root trace and records its callback lifetime.
  Future<T> trace<T>(
    String name, {
    required FutureOr<T> Function(ChroniclerRecorder recorder) run,
    RemoteTraceParent? parent,
    SpanKind kind = SpanKind.internal,
    Map<String, Object?> attributes = const {},
  }) => _runSpan(
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
  }) => _runSpanSync(
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
  }) => _runSpan(
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
  }) => _runSpanSync(
    name,
    kind: kind,
    attributes: attributes,
    forceRoot: false,
    remoteParent: null,
    run: run,
  );

  /// Marks the active callback-managed span as failed.
  void setSpanError() => _runtime.tracing.setError(_attribution.span);

  /// Replaces one attribute on the active callback-managed span.
  void setSpanAttribute(String key, Object? value) =>
      _runtime.tracing.setAttributes(_attribution.span, {key: value});

  /// Atomically merges [attributes] into the active callback-managed span.
  void setSpanAttributes(Map<String, Object?> attributes) =>
      _runtime.tracing.setAttributes(_attribution.span, attributes);

  /// Returns a cleaned carrier containing this active span's W3C metadata.
  Map<String, String> injectTrace(Map<String, String> headers) =>
      _runtime.tracing.inject(_attribution.span, headers);

  /// Returns a recorder whose analytics identity is exactly the supplied IDs.
  ///
  /// Omitted IDs are cleared. Runtime configuration and operation correlation
  /// remain shared with this recorder.
  ChroniclerRecorder withIdentity({
    String? userId,
    String? anonymousId,
    String? sessionId,
  }) => ChroniclerRecorder._(
    _runtime,
    _runtime.withIdentity(
      _attribution,
      userId: userId,
      anonymousId: anonymousId,
      sessionId: sessionId,
    ),
  );

  /// Records a structured log without waiting for transport work.
  void recordLog(
    LogSeverity severity,
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?> attributes = const {},
  }) => _runtime.recordLog(
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
  }) => _runtime.recordEvent(_attribution, name, properties: properties);

  /// Records an explicit error occurrence without waiting for transport.
  void recordError(
    Object error, {
    StackTrace? stackTrace,
    bool handled = true,
    List<ChroniclerCause> causes = const [],
    Map<String, Object?> attributes = const {},
  }) => _runtime.recordError(
    _attribution,
    error,
    stackTrace: stackTrace,
    handled: handled,
    causes: causes,
    attributes: attributes,
  );

  /// Records an explicit anonymous-to-user association.
  void identify({required String anonymousId, required String userId}) =>
      _runtime.recordIdentityLink(
        _attribution,
        anonymousId: anonymousId,
        userId: userId,
      );

  /// Records explicit user properties to set for [userId].
  void setUserProperties({
    required String userId,
    required Map<String, Object?> properties,
  }) => _runtime.recordUserPropertiesSet(
    _attribution,
    userId: userId,
    properties: properties,
  );

  /// Records explicit user-property removals for [userId].
  void unsetUserProperties({
    required String userId,
    required List<String> keys,
  }) => _runtime.recordUserPropertiesUnset(
    _attribution,
    userId: userId,
    keys: keys,
  );

  Future<T> _runSpan<T>(
    String name, {
    required SpanKind kind,
    required Map<String, Object?> attributes,
    required bool forceRoot,
    required RemoteTraceParent? remoteParent,
    required FutureOr<T> Function(ChroniclerRecorder recorder) run,
  }) async {
    final started = _startSpan(
      name,
      kind: kind,
      attributes: attributes,
      forceRoot: forceRoot,
      remoteParent: remoteParent,
    );
    try {
      final result = run(started.recorder);
      final value = await result;
      _runtime.tracing.finish(started.state, SpanStatus.success);
      return value;
    } on Object catch (error) {
      _runtime.tracing.finish(started.state, _runtime.tracing.failureStatus(error));
      rethrow;
    }
  }

  T _runSpanSync<T>(
    String name, {
    required SpanKind kind,
    required Map<String, Object?> attributes,
    required bool forceRoot,
    required RemoteTraceParent? remoteParent,
    required T Function(ChroniclerRecorder recorder) run,
  }) {
    final started = _startSpan(
      name,
      kind: kind,
      attributes: attributes,
      forceRoot: forceRoot,
      remoteParent: remoteParent,
    );
    try {
      final result = run(started.recorder);
      if (result is Future) {
        _runtime.diagnostics.record(DiagnosticReason.syncCallbackReturnedFuture);
      }
      _runtime.tracing.finish(started.state, SpanStatus.success);
      return result;
    } on Object catch (error) {
      _runtime.tracing.finish(started.state, _runtime.tracing.failureStatus(error));
      rethrow;
    }
  }

  _StartedSpan _startSpan(
    String name, {
    required SpanKind kind,
    required Map<String, Object?> attributes,
    required bool forceRoot,
    required RemoteTraceParent? remoteParent,
  }) {
    final attribution = _attribution;
    final state = _runtime.tracing.start(
      attribution.span,
      name,
      kind: kind,
      attributes: attributes,
      forceRoot: forceRoot,
      remoteParent: remoteParent,
      userId: attribution.userId,
      anonymousId: attribution.anonymousId,
      sessionId: attribution.sessionId,
    );
    if (state == null) return _StartedSpan(null, this);
    return _StartedSpan(
      state,
      ChroniclerRecorder._(
        _runtime,
        RecorderAttribution(
          userId: attribution.userId,
          anonymousId: attribution.anonymousId,
          sessionId: attribution.sessionId,
          traceId: state.traceId,
          spanId: state.spanId,
          span: state,
        ),
      ),
    );
  }
}

/// Internal fixture bridge used by sibling-signal contract tests.
final class ChroniclerCaptureFixture {
  const ChroniclerCaptureFixture._();

  /// Submits a finalized sibling-signal [record] through capture policy.
  static void capture(Chronicler chronicler, ChroniclerRecord record) =>
      RuntimeTestAccess.capture(chronicler._runtime, record);

  /// Returns a recorder with valid operation correlation for identity tests.
  static ChroniclerRecorder withCorrelation(
    ChroniclerRecorder recorder, {
    required String traceId,
    required String spanId,
  }) => ChroniclerRecorder._(
    recorder._runtime,
    RecorderAttribution(
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
    RuntimeTestAccess.overrideClocks(chronicler._runtime, now: now, elapsed: elapsed);
  }

  /// Replaces the ID source after setup for recording-failure tests.
  static void overrideSecureRandom(Chronicler chronicler, Random random) {
    RuntimeTestAccess.overrideSecureRandom(chronicler._runtime, random);
  }

  /// Replaces the root sampling source for whole-trace tests.
  static void overrideSamplingRandom(Chronicler chronicler, Random random) {
    RuntimeTestAccess.overrideSamplingRandom(chronicler._runtime, random);
  }

  /// Returns the number of payload attributes retained by [recorder]'s span.
  static int retainedAttributeCount(ChroniclerRecorder recorder) =>
      recorder._attribution.span?.retainedAttributeCount ?? 0;
}

final class _StartedSpan {
  const _StartedSpan(this.state, this.recorder);

  final ActiveSpan? state;
  final ChroniclerRecorder recorder;
}

/// Internal fixture bridge for deterministic delivery tests.
final class ChroniclerDeliveryFixture {
  const ChroniclerDeliveryFixture._();

  /// Replaces retry jitter selection for deterministic delivery tests.
  static void selectRetryDelay(
    Chronicler chronicler,
    Duration Function(int attempt, Duration ceiling) selector,
  ) {
    RuntimeTestAccess.selectRetryDelay(chronicler._runtime, selector);
  }

  /// Returns the current trace propagation switch.
  static bool propagationEnabled(Chronicler chronicler) =>
      RuntimeTestAccess.propagationEnabled(chronicler._runtime);

  /// Queues [records] for internal finalization during the next flush.
  static void finalizeOnNextFlush(
    Chronicler chronicler,
    Iterable<ChroniclerRecord> records,
  ) {
    RuntimeTestAccess.finalizeOnNextFlush(chronicler._runtime, records);
  }

  /// Returns the number of flush calls waiting on record dispositions.
  static int activeFlushes(Chronicler chronicler) =>
      RuntimeTestAccess.activeFlushes(chronicler._runtime);
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
    RuntimeTestAccess.overrideClocks(chronicler._runtime, now: now, elapsed: elapsed);
  }

  /// Rotates the current interval synchronously and stops its next timer.
  static void rotate(Chronicler chronicler) {
    RuntimeTestAccess.rotate(chronicler._runtime);
  }

  /// Makes the next metric record construction fail.
  static void failNextRecordCreation(Chronicler chronicler) {
    RuntimeTestAccess.failNextRecordCreation(chronicler._runtime);
  }

  /// Places an existing counter series at an arithmetic boundary.
  static void setCounterAggregate(
    Chronicler chronicler, {
    required int count,
    required String name,
    required double sum,
    Map<String, Object?> attributes = const {},
  }) {
    RuntimeTestAccess.setCounterAggregate(
      chronicler._runtime,
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
    RuntimeTestAccess.setSeriesCount(
      chronicler._runtime,
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
    RuntimeTestAccess.setHistogramAggregate(
      chronicler._runtime,
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
