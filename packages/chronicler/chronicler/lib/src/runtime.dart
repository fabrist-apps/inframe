import 'dart:async';

import 'package:chronicler/src/configuration.dart';
import 'package:chronicler/src/lifecycle.dart';
import 'package:chronicler/src/metrics.dart';
import 'package:chronicler/src/models.dart';
import 'package:chronicler/src/runtime/attribution.dart';
import 'package:chronicler/src/runtime/capture.dart';
import 'package:chronicler/src/runtime/tracing.dart';
import 'package:chronicler/src/trace_propagation.dart';
import 'package:chronicler/src/transport.dart';
import 'package:conflux/effect.dart';

export 'package:chronicler/src/runtime/capture.dart' show ChroniclerCause;

/// Configured owner of capture and export resources.
final class Chronicler {
  /// Creates a runtime and transfers ownership of [exporter] to it.
  ///
  /// [clock] is borrowed by the owned Conflux runtime. It controls timestamps,
  /// intervals, retries, and shutdown deadlines; defaults to [SystemClock].
  /// Recording snapshots values immediately; callers need not execute an Effect.
  Chronicler({
    required String appId,
    required String release,
    required ChroniclerSource source,
    required ChroniclerExporter exporter,
    String? buildId,
    ChroniclerOptions options = const ChroniclerOptions(),
    Clock? clock,
  }) : _runtime = ChroniclerRuntime.create(
         appId: appId,
         release: release,
         source: source,
         exporter: exporter,
         buildId: buildId,
         options: options,
         clock: clock,
       );

  /// Default field-name terms replaced before buffering.
  static const Set<String> defaultSensitiveFieldTerms =
      ChroniclerOptions.defaultSensitiveFieldTerms;

  final ChroniclerRuntime _runtime;

  /// A borrowed recorder suitable for binding to a request context.
  ChroniclerRecorder get recorder => ChroniclerRecorder._(_runtime, const RecorderAttribution());

  /// An immutable snapshot of exact runtime diagnostic counts.
  Map<DiagnosticReason, BigInt> get diagnosticCounts => _runtime.diagnosticCounts;

  /// Waits for the records owned when this call begins to reach a disposition.
  Future<DeliveryReport> flush({Duration? timeout}) =>
      _runtime.flush(timeout ?? _runtime.options.delivery.flushTimeout);

  /// Stops recording, drains bounded work, and releases the owned exporter.
  Future<DeliveryReport> close() => _runtime.close();

  /// Lazily flushes the snapshot captured when this Effect executes.
  ///
  /// Interrupting the caller stops waiting, not delivery of its records.
  Effect<DeliveryReport, Never> flushEffect({Duration? timeout}) => Effect.tryFuture(
    (_) => flush(timeout: timeout),
    onError: (error, stackTrace, _) => Error.throwWithStackTrace(error, stackTrace),
  );

  /// Lazily starts the shared, bounded shutdown operation.
  ///
  /// Safe as a scope finalizer: uncooperative exporter work is reported through
  /// [DeliveryReport.cleanupIncomplete] rather than awaited indefinitely.
  /// Interrupting a caller does not undo shutdown once it has started.
  Effect<DeliveryReport, Never> closeEffect() => Effect.tryFuture(
    (_) => close(),
    onError: (error, stackTrace, _) => Error.throwWithStackTrace(error, stackTrace),
  );

  /// Whether collection currently accepts [signal].
  bool isCollectionEnabled(ChroniclerSignal signal) => _runtime.isCollectionEnabled(signal);

  /// Enables or disables collection for [signal] synchronously.
  void setCollectionEnabled(ChroniclerSignal signal, {required bool enabled}) =>
      _runtime.setCollectionEnabled(signal, enabled: enabled);

  /// Enables or disables trace-context propagation independently of collection.
  void setPropagationEnabled({required bool enabled}) =>
      _runtime.setPropagationEnabled(enabled: enabled);
}

/// Borrowed immutable attribution view over one Chronicler runtime.
final class ChroniclerRecorder {
  const ChroniclerRecorder._(this._runtime, this._attribution);

  final ChroniclerRuntime _runtime;
  final RecorderAttribution _attribution;

  /// Metric instruments shared by this recorder's application runtime.
  ChroniclerMetrics get metrics => _runtime.metrics;

  /// Starts a child span, or a root when this recorder has no active span.
  ChroniclerSpan startSpan(
    String name, {
    SpanKind kind = SpanKind.internal,
    Map<String, Object?> attributes = const {},
  }) => _startSpanHandle(
    name,
    kind: kind,
    attributes: attributes,
    forceRoot: false,
    remoteParent: null,
  );

  /// Starts an explicit root boundary, optionally continuing [parent].
  ChroniclerSpan startRootSpan(
    String name, {
    RemoteTraceParent? parent,
    SpanKind kind = SpanKind.internal,
    Map<String, Object?> attributes = const {},
  }) => _startSpanHandle(
    name,
    kind: kind,
    attributes: attributes,
    forceRoot: true,
    remoteParent: parent,
  );

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

  /// Returns a cleaned carrier containing this active span's Chronicler headers.
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
    final span = _startSpanHandle(
      name,
      kind: kind,
      attributes: attributes,
      forceRoot: forceRoot,
      remoteParent: remoteParent,
    );
    try {
      final result = run(span.recorder);
      final value = await result;
      span.end(SpanStatus.success);
      return value;
    } on Object catch (error) {
      span.end(_runtime.tracing.failureStatus(error));
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
    final span = _startSpanHandle(
      name,
      kind: kind,
      attributes: attributes,
      forceRoot: forceRoot,
      remoteParent: remoteParent,
    );
    try {
      final result = run(span.recorder);
      if (result is Future) {
        _runtime.diagnostics.record(DiagnosticReason.syncCallbackReturnedFuture);
      }
      span.end(SpanStatus.success);
      return result;
    } on Object catch (error) {
      span.end(_runtime.tracing.failureStatus(error));
      rethrow;
    }
  }

  ChroniclerSpan _startSpanHandle(
    String name, {
    required SpanKind kind,
    required Map<String, Object?> attributes,
    required bool forceRoot,
    required RemoteTraceParent? remoteParent,
  }) {
    try {
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
      final recorder = state == null
          ? this
          : ChroniclerRecorder._(
              _runtime,
              RecorderAttribution(
                userId: attribution.userId,
                anonymousId: attribution.anonymousId,
                sessionId: attribution.sessionId,
                traceId: state.traceId,
                spanId: state.spanId,
                span: state,
              ),
            );
      return ChroniclerSpan._(_runtime, state, recorder);
    } on Object {
      _runtime.diagnostics.record(DiagnosticReason.spanStartFailed);
      return ChroniclerSpan._(_runtime, null, this);
    }
  }
}

/// A borrowed SDK span whose first explicit completion wins.
final class ChroniclerSpan {
  ChroniclerSpan._(this._runtime, this._state, this.recorder);

  final ChroniclerRuntime _runtime;
  final ActiveSpan? _state;

  /// Recorder carrying this span's correlation, or its original attribution
  /// when span acquisition failed.
  final ChroniclerRecorder recorder;

  bool _ended = false;

  /// Ends this span once with [status] without flushing borrowed runtime work.
  void end(SpanStatus status) {
    if (_ended) return;
    _ended = true;
    try {
      _runtime.tracing.finish(_state, status);
    } on Object {
      _runtime.diagnostics.record(DiagnosticReason.spanEndFailed);
    }
  }
}
