import 'package:chronicler/src/runtime/tracing.dart';

/// Immutable analytics identity and borrowed operation correlation.
final class RecorderAttribution {
  /// Creates attribution without retaining request or application objects.
  const RecorderAttribution({
    this.userId,
    this.anonymousId,
    this.sessionId,
    this.traceId,
    this.spanId,
    this.span,
  });

  /// Known End User identifier.
  final String? userId;

  /// Anonymous End User identifier.
  final String? anonymousId;

  /// App session identifier.
  final String? sessionId;

  /// Trace correlation retained by this recorder.
  final String? traceId;

  /// Span correlation retained by this recorder.
  final String? spanId;

  /// Borrowed span handle; mutable lifecycle belongs to TraceController.
  final ActiveSpan? span;
}
