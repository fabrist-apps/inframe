import 'dart:convert';
import 'dart:typed_data';

import 'package:runnel/src/errors.dart';
import 'package:runnel/src/resp/resp_value.dart';

/// Incrementally decodes complete RESP3 top-level frames.
final class RespParser {
  /// Creates an incremental parser with per-frame byte and nesting limits.
  RespParser({required this.maxFrameBytes, required this.maxNestingDepth});

  /// Maximum encoded bytes accepted for one top-level frame.
  final int maxFrameBytes;

  /// Maximum aggregate depth, where a top-level aggregate has depth one.
  final int maxNestingDepth;
  Uint8List _buffer = Uint8List(0);

  /// Appends bytes and returns every complete value now available.
  List<RespValue> add(List<int> bytes) {
    if (bytes.isNotEmpty) {
      _buffer = Uint8List.fromList([..._buffer, ...bytes]);
    }
    final values = <RespValue>[];
    var offset = 0;
    while (offset < _buffer.length) {
      try {
        final result = _parse(offset, 0);
        final frameBytes = result.next - offset;
        if (frameBytes > maxFrameBytes) _limit();
        values.add(result.value);
        offset = result.next;
      } on _NeedMore {
        if (_buffer.length - offset > maxFrameBytes) _limit();
        break;
      }
    }
    if (offset > 0) _buffer = Uint8List.fromList(_buffer.sublist(offset));
    return values;
  }

  _Parsed _parse(int offset, int depth) {
    if (offset >= _buffer.length) throw const _NeedMore();
    final prefix = _buffer[offset];
    switch (prefix) {
      case 43: // +
        final line = _line(offset + 1);
        return _Parsed(RespSimpleString(_strictText(line.bytes)), line.next);
      case 45: // -
        final line = _line(offset + 1);
        return _Parsed(RespError.parse(_strictText(line.bytes)), line.next);
      case 58: // :
        final line = _line(offset + 1);
        return _Parsed(RespInteger(_integer(line.bytes)), line.next);
      case 36: // $
        return _blob(offset, false);
      case 42: // *
        return _aggregate(offset, depth, _Aggregate.array);
      case 95: // _
        final line = _line(offset + 1);
        if (line.bytes.isNotEmpty) _malformed('RESP null must have an empty payload.');
        return _Parsed(const RespNull(), line.next);
      case 35: // #
        final line = _line(offset + 1);
        if (line.bytes.length != 1 || (line.bytes.first != 116 && line.bytes.first != 102)) {
          _malformed('RESP boolean must be #t or #f.');
        }
        return _Parsed(RespBoolean(value: line.bytes.first == 116), line.next);
      case 44: // ,
        final line = _line(offset + 1);
        final text = ascii.decode(line.bytes);
        final value = switch (text) {
          'inf' => double.infinity,
          '-inf' => double.negativeInfinity,
          'nan' => double.nan,
          _ => double.tryParse(text),
        };
        if (value == null) _malformed('Invalid RESP double.');
        return _Parsed(RespDouble(value), line.next);
      case 40: // (
        final line = _line(offset + 1);
        final value = BigInt.tryParse(ascii.decode(line.bytes));
        if (value == null) _malformed('Invalid RESP big number.');
        return _Parsed(RespBigNumber(value), line.next);
      case 33: // !
        return _blob(offset, true);
      case 61: // =
        final blob = _readBlob(offset);
        if (blob.bytes.length < 4 || blob.bytes[3] != 58) {
          _malformed('RESP verbatim string requires a three-byte format.');
        }
        return _Parsed(
          RespVerbatimString(
            format: ascii.decode(blob.bytes.sublist(0, 3)),
            value: blob.bytes.sublist(4),
          ),
          blob.next,
        );
      case 37: // %
        return _aggregate(offset, depth, _Aggregate.map);
      case 126: // ~
        return _aggregate(offset, depth, _Aggregate.set);
      case 62: // >
        return _aggregate(offset, depth, _Aggregate.push);
      case 124: // |
        final attributes = _aggregate(offset, depth, _Aggregate.map);
        final map = attributes.value as RespMap;
        final value = _parse(attributes.next, depth);
        return _Parsed(RespAttributed(attributes: map.entries, value: value.value), value.next);
      default:
        _malformed('Unknown RESP prefix 0x${prefix.toRadixString(16)}.');
    }
  }

  _Parsed _blob(int offset, bool error) {
    final blob = _readBlob(offset);
    if (error) {
      return _Parsed(RespError.parse(_strictText(blob.bytes), blob: true), blob.next);
    }
    return _Parsed(RespBlobString(blob.bytes), blob.next);
  }

  _Blob _readBlob(int offset) {
    final line = _line(offset + 1);
    final length = _integer(line.bytes);
    if (length < 0) _malformed('RESP blob length cannot be negative.');
    if (length > maxFrameBytes || line.next - offset + length + 2 > maxFrameBytes) _limit();
    final end = line.next + length;
    if (end + 2 > _buffer.length) throw const _NeedMore();
    if (_buffer[end] != 13 || _buffer[end + 1] != 10) {
      _malformed('RESP blob is missing its trailing CRLF.');
    }
    return _Blob(Uint8List.fromList(_buffer.sublist(line.next, end)), end + 2);
  }

  _Parsed _aggregate(int offset, int depth, _Aggregate type) {
    final aggregateDepth = depth + 1;
    if (aggregateDepth > maxNestingDepth) _limit(depth: true);
    final line = _line(offset + 1);
    final count = _integer(line.bytes);
    if (count < 0) _malformed('RESP aggregate length cannot be negative.');
    final itemCount = type == _Aggregate.map ? count * 2 : count;
    if (itemCount > maxFrameBytes) _limit();
    var cursor = line.next;
    final values = <RespValue>[];
    for (var index = 0; index < itemCount; index++) {
      final value = _parse(cursor, aggregateDepth);
      values.add(value.value);
      cursor = value.next;
      if (cursor - offset > maxFrameBytes) _limit();
    }
    final result = switch (type) {
      _Aggregate.array => RespArray(values),
      _Aggregate.set => RespSet(values),
      _Aggregate.push => RespPush(values),
      _Aggregate.map => RespMap([
        for (var index = 0; index < values.length; index += 2)
          RespMapEntry(values[index], values[index + 1]),
      ]),
    };
    return _Parsed(result, cursor);
  }

  _Line _line(int start) {
    for (var index = start; index + 1 < _buffer.length; index++) {
      if (_buffer[index] == 13 && _buffer[index + 1] == 10) {
        return _Line(Uint8List.fromList(_buffer.sublist(start, index)), index + 2);
      }
      if (index - start + 1 > maxFrameBytes) _limit();
    }
    throw const _NeedMore();
  }

  int _integer(Uint8List bytes) {
    final value = int.tryParse(ascii.decode(bytes));
    if (value == null) _malformed('Invalid RESP integer.');
    return value;
  }

  String _strictText(Uint8List bytes) {
    try {
      return utf8.decode(bytes);
    } on FormatException catch (error) {
      throw RedisProtocolException(message: 'RESP text is not valid UTF-8.', cause: error);
    }
  }

  Never _limit({bool depth = false}) => throw RedisLimitException(
    message: depth
        ? 'RESP aggregate nesting exceeds $maxNestingDepth.'
        : 'RESP frame exceeds $maxFrameBytes bytes.',
    deliveryStatus: RedisDeliveryStatus.outcomeUnknown,
    limit: depth ? maxNestingDepth : maxFrameBytes,
  );

  Never _malformed(String message) => throw RedisProtocolException(message: message);
}

enum _Aggregate { array, map, set, push }

final class _Parsed {
  const _Parsed(this.value, this.next);
  final RespValue value;
  final int next;
}

final class _Line {
  const _Line(this.bytes, this.next);
  final Uint8List bytes;
  final int next;
}

final class _Blob {
  const _Blob(this.bytes, this.next);
  final Uint8List bytes;
  final int next;
}

final class _NeedMore implements Exception {
  const _NeedMore();
}
