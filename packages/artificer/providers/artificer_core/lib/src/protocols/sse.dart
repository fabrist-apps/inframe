import 'dart:convert';
import 'dart:typed_data';

import 'package:artificer_core/src/errors.dart';
import 'package:dart_mappable/dart_mappable.dart';

part 'sse.mapper.dart';

/// One SSE data event, preserving its event name and transport identifiers.
@MappableClass()
class SseEvent with SseEventMappable {
  /// Creates a framing value without interpreting native provider JSON.
  const SseEvent({required this.data, this.event, this.id, this.retry});

  /// Joined data lines, including unknown provider fields or event payloads.
  final String data;

  /// Explicit event name, or null when the server omitted it.
  final String? event;

  /// Last valid event identifier supplied by the stream.
  final String? id;

  /// Advertised reconnect delay; the SDK never automatically reconnects.
  final int? retry;

  /// Decodes the generated persistence representation.
  static const fromMap = SseEventMapper.fromMap;

  /// Decodes the generated JSON representation.
  static const fromJson = SseEventMapper.fromJson;

  @override
  String toString() => 'SseEvent';
}

/// Incrementally frames UTF-8 SSE without expanding a chunk into a frame list.
class SseParser {
  /// Bounds raw bytes per frame, independently of decoded Flow capacity.
  SseParser({this.maxEventBytes = 8 * 1024 * 1024}) {
    if (maxEventBytes <= 0) throw ArgumentError.value(maxEventBytes, 'maxEventBytes');
  }

  /// Maximum UTF-8 frame bytes, counting CRLF as one newline.
  final int maxEventBytes;

  /// Decodes one event at a time and honors downstream pause and cancellation.
  Stream<SseEvent> decode(Stream<List<int>> source) async* {
    final frame = _SseFrame(maxEventBytes);
    var afterCarriageReturn = false;
    await for (final chunk in source) {
      for (final byte in chunk) {
        if (afterCarriageReturn && byte == 10) {
          afterCarriageReturn = false;
          continue;
        }
        afterCarriageReturn = byte == 13;
        frame.addByte(byte);
        if (byte == 10 || byte == 13) {
          final event = frame.endLine();
          if (event != null) yield event;
        }
      }
    }
    frame.endStream();
  }
}

class _SseFrame {
  _SseFrame(this.limit);
  final int limit;
  final BytesBuilder _line = BytesBuilder(copy: false);
  StringBuffer _data = StringBuffer();
  String? _event;
  String? _id;
  int? _retry;
  int _bytes = 0;
  bool _firstLine = true;
  bool _hasData = false;

  void addByte(int byte) {
    if (++_bytes > limit) {
      throw ResponseLimitError('SSE event exceeds byte limit.', limit: limit);
    }
    if (byte != 10 && byte != 13) _line.addByte(byte);
  }

  SseEvent? endLine() {
    String line;
    try {
      line = utf8.decode(_line.takeBytes());
    } on FormatException {
      throw const ProtocolError('SSE contains invalid UTF-8.');
    }
    if (_firstLine && line.startsWith('\ufeff')) line = line.substring(1);
    _firstLine = false;
    if (line.isEmpty) {
      final event = _hasData
          ? SseEvent(data: _data.toString(), event: _event, id: _id, retry: _retry)
          : null;
      _data = StringBuffer();
      _event = null;
      _hasData = false;
      _bytes = 0;
      return event;
    }
    if (line.startsWith(':')) return null;
    final colon = line.indexOf(':');
    final field = colon < 0 ? line : line.substring(0, colon);
    var value = colon < 0 ? '' : line.substring(colon + 1);
    if (value.startsWith(' ')) value = value.substring(1);
    switch (field) {
      case 'data':
        if (_hasData) _data.write('\n');
        _data.write(value);
        _hasData = true;
      case 'event':
        _event = value;
      case 'id':
        if (!value.contains('\u0000')) _id = value;
      case 'retry':
        if (RegExp(r'^\d+$').hasMatch(value)) _retry = int.tryParse(value);
    }
    return null;
  }

  void endStream() {
    if (_line.isNotEmpty || _hasData) {
      throw const ProtocolError('SSE ended inside an unfinished frame.');
    }
  }
}
