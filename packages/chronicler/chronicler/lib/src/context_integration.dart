import 'package:chronicler/src/models.dart';
import 'package:chronicler/src/runtime.dart';
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
  Context withIdentity({
    String? userId,
    String? anonymousId,
    String? sessionId,
  }) => withBinding(
    _chroniclerKey.bind(
      require(_chroniclerKey).withIdentity(
        userId: userId,
        anonymousId: anonymousId,
        sessionId: sessionId,
      ),
    ),
  );
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
