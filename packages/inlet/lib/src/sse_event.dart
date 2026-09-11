part of 'inlet.dart';

/// A text event delivered by [Response.sse].
final class SseEvent {
  /// Creates a text event containing [data].
  SseEvent({required String data}) : _encoded = _encodeData(data);

  final List<int> _encoded;
}

List<int> _encodeData(String data) {
  final normalized = data.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  final encoded = StringBuffer();
  for (final line in normalized.split('\n')) {
    encoded
      ..write('data:')
      ..write(line.isEmpty ? '\n' : ' $line\n');
  }
  encoded.writeln();
  return utf8.encode(encoded.toString());
}
