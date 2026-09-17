import 'dart:async';

import 'package:chronicler/src/metrics.dart';
import 'package:chronicler/src/models.dart';
import 'package:chronicler/src/runtime.dart';
import 'package:chronicler/src/trace_propagation.dart';
import 'package:context/context.dart';

final _chroniclerKey = ContextKey<ChroniclerRecorder>('chronicler');

/// Binds a borrowed Chronicler recorder to a [Context].
extension ChroniclerContextBinding on Context {
  /// Returns a child context bound to [recorder].
  Context withChronicler(ChroniclerRecorder recorder) => withBinding(_chroniclerKey.bind(recorder));

  /// Returns a child context with complete replacement analytics identity.
  ///
  /// Omitted fields are absent on records captured through the returned
  /// context. This affects telemetry attribution only; callers remain
  /// responsible for authentication and identity lifecycle.
  Context withIdentity({String? userId, String? anonymousId, String? sessionId}) => withBinding(
    _chroniclerKey.bind(
      require(_chroniclerKey)
          .withIdentity(userId: userId, anonymousId: anonymousId, sessionId: sessionId),
    ),
  );
}

/// Exposes runtime-owned metric instruments from a configured [Context].
extension ChroniclerContextMetrics on Context {
  /// Metric instruments shared by every recorder for this runtime.
  ChroniclerMetrics get metrics => require(_chroniclerKey).metrics;
}

/// Exposes structured log capture from a configured [Context].
extension ChroniclerContextLogs on Context {
  /// Structured logging backed by the recorder bound to this context.
  ChroniclerLogs get logs => ChroniclerLogs(require(_chroniclerKey));
}

/// Exposes product-event capture from a configured [Context].
extension ChroniclerContextEvents on Context {
  /// Product events backed by the recorder bound to this context.
  ChroniclerEvents get events => ChroniclerEvents(require(_chroniclerKey));
}

/// Exposes error-occurrence capture from a configured [Context].
extension ChroniclerContextErrors on Context {
  /// Error occurrences backed by the recorder bound to this context.
  ChroniclerErrors get errors => ChroniclerErrors(require(_chroniclerKey));
}

/// Runs callback-managed tracing operations from a configured [Context].
extension ChroniclerContextTracing on Context {
  /// Active-span updates and propagation backed by this Context's recorder.
  ChroniclerTracing get tracing => ChroniclerTracing(require(_chroniclerKey));

  /// Runs [run] in a new root trace and returns its result asynchronously.
  Future<T> trace<T>(
    String name,
    FutureOr<T> Function(Context context) run, {
    RemoteTraceParent? parent,
    SpanKind kind = SpanKind.internal,
    Map<String, Object?> attributes = const {},
  }) => require(_chroniclerKey).trace(
    name,
    (recorder) => run(withChronicler(recorder)),
    parent: parent,
    kind: kind,
    attributes: attributes,
  );

  /// Runs [run] synchronously in a new root trace.
  T traceSync<T>(
    String name,
    T Function(Context context) run, {
    RemoteTraceParent? parent,
    SpanKind kind = SpanKind.internal,
    Map<String, Object?> attributes = const {},
  }) => require(_chroniclerKey).traceSync(
    name,
    (recorder) => run(withChronicler(recorder)),
    parent: parent,
    kind: kind,
    attributes: attributes,
  );

  /// Runs [run] in a child span, or a new root when no span is active.
  Future<T> span<T>(
    String name,
    FutureOr<T> Function(Context context) run, {
    SpanKind kind = SpanKind.internal,
    Map<String, Object?> attributes = const {},
  }) => require(_chroniclerKey).span(
    name,
    (recorder) => run(withChronicler(recorder)),
    kind: kind,
    attributes: attributes,
  );

  /// Runs [run] synchronously in a child span, or a root when no span is active.
  T spanSync<T>(
    String name,
    T Function(Context context) run, {
    SpanKind kind = SpanKind.internal,
    Map<String, Object?> attributes = const {},
  }) => require(_chroniclerKey).spanSync(
    name,
    (recorder) => run(withChronicler(recorder)),
    kind: kind,
    attributes: attributes,
  );
}

/// Updates the active callback-managed span reached through a [Context].
final class ChroniclerTracing {
  /// Creates a tracing view over a borrowed recorder.
  const ChroniclerTracing(this._recorder);

  final ChroniclerRecorder _recorder;

  /// Starts a child span, or a root when this Context has no active span.
  ChroniclerSpan startSpan(
    String name, {
    SpanKind kind = SpanKind.internal,
    Map<String, Object?> attributes = const {},
  }) => _recorder.startSpan(name, kind: kind, attributes: attributes);

  /// Starts an explicit root boundary, optionally continuing [parent].
  ChroniclerSpan startRootSpan(
    String name, {
    RemoteTraceParent? parent,
    SpanKind kind = SpanKind.internal,
    Map<String, Object?> attributes = const {},
  }) => _recorder.startRootSpan(
    name,
    parent: parent,
    kind: kind,
    attributes: attributes,
  );

  /// Marks the active span as failed without changing the callback result.
  void setError() => _recorder.setSpanError();

  /// Replaces one active-span attribute after atomic validation.
  void setAttribute(String key, Object? value) => _recorder.setSpanAttribute(key, value);

  /// Atomically merges [attributes] into the active span.
  void setAttributes(Map<String, Object?> attributes) => _recorder.setSpanAttributes(attributes);

  /// Returns a new carrier with stale tracing headers replaced for this span.
  Map<String, String> inject(Map<String, String> headers) => _recorder.injectTrace(headers);
}

/// Records product events without waiting for transport work.
final class ChroniclerEvents {
  /// Creates an event view over a borrowed recorder.
  const ChroniclerEvents(this._recorder);

  final ChroniclerRecorder _recorder;

  /// Records a named product event with an immutable property snapshot.
  void track(
    String name, {
    Map<String, Object?> properties = const {},
  }) => _recorder.recordEvent(name, properties: properties);

  /// Records an explicit association between an anonymous ID and a user ID.
  ///
  /// This does not change identity on this Context or confirm downstream
  /// profile processing.
  void identify({required String anonymousId, required String userId}) =>
      _recorder.identify(anonymousId: anonymousId, userId: userId);

  /// Records explicit user properties to set for [userId].
  ///
  /// An empty [properties] map is a no-op. Null is retained as a value; use an
  /// explicit unset operation to express deletion.
  void setUserProperties({
    required String userId,
    required Map<String, Object?> properties,
  }) => _recorder.setUserProperties(userId: userId, properties: properties);

  /// Records explicit user-property removals for [userId].
  ///
  /// Duplicate [keys] collapse in first-appearance order. An empty list is a
  /// no-op, and sensitive field names remain intact as deletion intent.
  void unsetUserProperties({
    required String userId,
    required List<String> keys,
  }) => _recorder.unsetUserProperties(userId: userId, keys: keys);
}

/// Captures explicit error occurrences without waiting for transport work.
final class ChroniclerErrors {
  /// Creates an error-capture view over a borrowed recorder.
  const ChroniclerErrors(this._recorder);

  final ChroniclerRecorder _recorder;

  /// Captures one handled or unhandled error occurrence.
  void capture(
    Object error, {
    StackTrace? stackTrace,
    bool handled = true,
    List<ChroniclerCause> causes = const [],
    Map<String, Object?> attributes = const {},
  }) => _recorder.recordError(
    error,
    stackTrace: stackTrace,
    handled: handled,
    causes: causes,
    attributes: attributes,
  );
}

/// Records structured logs without waiting for transport work.
final class ChroniclerLogs {
  /// Creates a logging view over a borrowed recorder.
  const ChroniclerLogs(this._recorder);

  final ChroniclerRecorder _recorder;

  /// Records a debug log.
  void debug(
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?> attributes = const {},
  }) => _recorder.recordLog(
    LogSeverity.debug,
    message,
    error: error,
    stackTrace: stackTrace,
    attributes: attributes,
  );

  /// Records an informational log.
  void info(
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?> attributes = const {},
  }) => _recorder.recordLog(
    LogSeverity.info,
    message,
    error: error,
    stackTrace: stackTrace,
    attributes: attributes,
  );

  /// Records a warning log.
  void warning(
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?> attributes = const {},
  }) => _recorder.recordLog(
    LogSeverity.warning,
    message,
    error: error,
    stackTrace: stackTrace,
    attributes: attributes,
  );

  /// Records an error log without creating a separate error occurrence.
  void error(
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?> attributes = const {},
  }) => _recorder.recordLog(
    LogSeverity.error,
    message,
    error: error,
    stackTrace: stackTrace,
    attributes: attributes,
  );
}
