part of 'inlet.dart';

/// An event or comment delivered by [Response.sse].
final class SseEvent {
  /// Creates a text event with optional event-stream metadata.
  SseEvent({
    required String data,
    String? event,
    String? id,
    Duration? retry,
  }) : _encoded = _encodeEvent(
         data: data,
         event: event,
         id: id,
         retry: retry,
       );

  /// Creates a text event from an immediate JSON snapshot of [data].
  factory SseEvent.json(
    Object? data, {
    String? event,
    String? id,
    Duration? retry,
  }) => SseEvent(
    data: jsonEncode(data),
    event: event,
    id: id,
    retry: retry,
  );

  /// Creates a single-line event-stream comment.
  SseEvent.comment(String value) : _encoded = _encodeComment(value);

  final List<int> _encoded;
}

List<int> _encodeEvent({
  required String data,
  required String? event,
  required String? id,
  required Duration? retry,
}) {
  if (event != null) {
    _validateMetadata(event, 'event');
  }
  if (id != null) {
    _validateMetadata(id, 'id');
  }
  if (retry != null &&
      (retry.isNegative || retry.inMicroseconds % Duration.microsecondsPerMillisecond != 0)) {
    throw ArgumentError.value(
      retry,
      'retry',
      'must be a nonnegative whole number of milliseconds',
    );
  }

  final normalized = data.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  final encoded = StringBuffer();
  if (event != null) {
    _writeField(encoded, 'event', event);
  }
  if (id != null) {
    _writeField(encoded, 'id', id);
  }
  if (retry != null) {
    _writeField(encoded, 'retry', retry.inMilliseconds.toString());
  }
  for (final line in normalized.split('\n')) {
    _writeField(encoded, 'data', line);
  }
  encoded.writeln();
  return utf8.encode(encoded.toString());
}

List<int> _encodeComment(String value) {
  if (value.contains('\r') || value.contains('\n')) {
    throw ArgumentError.value(value, 'value', 'must contain one line');
  }
  final encoded = StringBuffer();
  _writeField(encoded, '', value);
  encoded.writeln();
  return utf8.encode(encoded.toString());
}

void _validateMetadata(String value, String name) {
  if (value.contains('\r') || value.contains('\n') || value.contains('\u0000')) {
    throw ArgumentError.value(value, name, 'must not contain CR, LF, or NUL');
  }
}

void _writeField(StringBuffer target, String name, String value) {
  target
    ..write(name)
    ..write(':')
    ..write(value.isEmpty ? '\n' : ' $value\n');
}
