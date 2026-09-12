import 'package:chronicler/src/models.dart';
import 'package:chronicler/src/runtime.dart';
import 'package:context/context.dart';

final _chroniclerKey = ContextKey<ChroniclerRecorder>('chronicler');

/// Binds a borrowed Chronicler recorder to a [Context].
extension ChroniclerContextBinding on Context {
  /// Returns a child context bound to [recorder].
  Context withChronicler(ChroniclerRecorder recorder) => withBinding(_chroniclerKey.bind(recorder));
}

/// Exposes structured log capture from a configured [Context].
extension ChroniclerContextLogs on Context {
  /// Structured logging backed by the recorder bound to this context.
  ChroniclerLogs get logs => ChroniclerLogs(require(_chroniclerKey));
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
