import 'package:chrono_id/chrono_id.dart';

/// Validated Chronicler parent metadata accepted at an explicit trace boundary.
final class RemoteTraceParent {
  const RemoteTraceParent._({
    required this.traceId,
    required this.parentSpanId,
    required this.sampled,
  });

  /// Incoming Chrono ID with the `trc` prefix.
  final String traceId;

  /// Incoming parent span's Chrono ID with the `spn` prefix.
  final String parentSpanId;

  /// Whether the upstream trace was sampled.
  final bool sampled;
}

/// Decodes Chronicler correlation headers, not W3C Trace Context.
///
/// IDs use chrono_id's default body size with `trc` and `spn` prefixes.
/// Header names are case-insensitive; duplicate or malformed values are rejected.
/// These headers carry correlation only, never identity or authorization.
abstract final class TracePropagation {
  /// Header carrying the shared trace ID.
  static const traceIdHeader = 'chronicler-trace-id';

  /// Header carrying the sending span's ID, used as the receiver's parent.
  static const spanIdHeader = 'chronicler-span-id';

  /// Header carrying `1` for sampled or `0` for unsampled.
  static const sampledHeader = 'chronicler-sampled';

  /// Returns a remote parent, or null for missing, duplicate, or invalid metadata.
  static RemoteTraceParent? extract(Map<String, String> headers) {
    final traceId = headers.find(traceIdHeader);
    if (traceId == null || !ChronoID.isValid(traceId, prefix: 'trc')) return null;

    final parentSpanId = headers.find(spanIdHeader);
    if (parentSpanId == null || !ChronoID.isValid(parentSpanId, prefix: 'spn')) return null;

    final sampled = headers.find(sampledHeader);
    if (sampled != '0' && sampled != '1') return null;

    return RemoteTraceParent._(
      traceId: traceId,
      parentSpanId: parentSpanId,
      sampled: sampled == '1',
    );
  }
}

extension on Map<String, String> {
  String? find(String name) {
    String? result;
    for (final MapEntry(:key, :value) in entries) {
      if (key.toLowerCase() != name) continue;
      if (result != null) return null;
      result = value;
    }
    return result;
  }
}
