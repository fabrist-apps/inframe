import 'dart:convert';
import 'dart:typed_data';

import 'package:conflux/effect.dart';
import 'package:runnel/src/client.dart';
import 'package:runnel/src/command.dart';
import 'package:runnel/src/commands/execution.dart';
import 'package:runnel/src/commands/reply_decoding.dart';
import 'package:runnel/src/errors.dart';
import 'package:runnel/src/resp/resp_value.dart';

final BigInt _maximumStreamIdComponent = (BigInt.one << 64) - BigInt.one;
final RegExp _streamIdPattern = RegExp(r'^(\d+)-(\d+)$');

/// One exact Redis Stream entry ID.
final class StreamId implements Comparable<StreamId> {
  /// Creates an ID from unsigned 64-bit millisecond and sequence components.
  StreamId(this.milliseconds, this.sequence) {
    _checkComponent(milliseconds, 'milliseconds');
    _checkComponent(sequence, 'sequence');
  }

  /// Parses the decimal `milliseconds-sequence` wire representation.
  factory StreamId.parse(String value) {
    final match = _streamIdPattern.firstMatch(value);
    if (match == null) {
      throw FormatException('Invalid Stream ID: $value');
    }
    final milliseconds = BigInt.parse(match[1]!);
    final sequence = BigInt.parse(match[2]!);
    if (milliseconds > _maximumStreamIdComponent || sequence > _maximumStreamIdComponent) {
      throw FormatException('Stream ID components must be unsigned 64-bit integers: $value');
    }
    return StreamId(milliseconds, sequence);
  }

  /// The unsigned 64-bit Unix time component in milliseconds.
  final BigInt milliseconds;

  /// The unsigned 64-bit sequence component.
  final BigInt sequence;

  @override
  int compareTo(StreamId other) {
    final timeOrder = milliseconds.compareTo(other.milliseconds);
    return timeOrder == 0 ? sequence.compareTo(other.sequence) : timeOrder;
  }

  @override
  bool operator ==(Object other) =>
      other is StreamId && milliseconds == other.milliseconds && sequence == other.sequence;

  @override
  int get hashCode => Object.hash(milliseconds, sequence);

  @override
  String toString() => '$milliseconds-$sequence';

  static void _checkComponent(BigInt value, String name) {
    if (value < BigInt.zero || value > _maximumStreamIdComponent) {
      throw RangeError('$name must be an unsigned 64-bit integer: $value');
    }
  }
}

/// An inclusive bound for an ordinary Stream range read.
sealed class StreamBound {
  const StreamBound();

  /// A concrete inclusive Stream ID bound.
  factory StreamBound.id(StreamId id) = _StreamIdBound;

  /// The unbounded minimum (`-`).
  static const StreamBound minimum = _MinimumStreamBound();

  /// The unbounded maximum (`+`).
  static const StreamBound maximum = _MaximumStreamBound();
}

final class _MinimumStreamBound extends StreamBound {
  const _MinimumStreamBound();
}

final class _MaximumStreamBound extends StreamBound {
  const _MaximumStreamBound();
}

final class _StreamIdBound extends StreamBound {
  const _StreamIdBound(this.id);

  final StreamId id;
}

/// One explicit trimming strategy for [RunnelStreamCommands.xtrim].
sealed class StreamTrim {
  const StreamTrim._({required this.approximate});

  /// Creates a maximum-entry-count trim, where zero removes every entry.
  factory StreamTrim.maxLength(int count, {bool approximate = false}) {
    if (count < 0) throw RangeError.range(count, 0, null, 'count');
    return _MaxLengthStreamTrim(count, approximate: approximate);
  }

  /// Creates a trim that removes entries older than [id].
  factory StreamTrim.minId(StreamId id, {bool approximate = false}) =>
      _MinIdStreamTrim(id, approximate: approximate);

  /// Whether Redis may trim at a nearby radix-tree boundary.
  final bool approximate;
}

final class _MaxLengthStreamTrim extends StreamTrim {
  const _MaxLengthStreamTrim(this.count, {required super.approximate}) : super._();

  final int count;
}

final class _MinIdStreamTrim extends StreamTrim {
  const _MinIdStreamTrim(this.id, {required super.approximate}) : super._();

  final StreamId id;
}

/// One ordered binary field/value pair in a Stream entry.
final class StreamField {
  /// Snapshots a binary field name and value.
  StreamField(Uint8List field, Uint8List value)
    : _field = Uint8List.fromList(field),
      _value = Uint8List.fromList(value);

  /// Encodes a field name and value as UTF-8.
  factory StreamField.text(String field, String value) =>
      StreamField(Uint8List.fromList(utf8.encode(field)), Uint8List.fromList(utf8.encode(value)));

  final Uint8List _field;
  final Uint8List _value;

  /// An owned copy of the field-name bytes.
  Uint8List get field => Uint8List.fromList(_field);

  /// An owned copy of the field-value bytes.
  Uint8List get value => Uint8List.fromList(_value);
}

/// One Stream entry with its ordered field/value pairs.
final class StreamEntry {
  /// Creates an immutable entry snapshot.
  StreamEntry({required this.id, required Iterable<StreamField> fields})
    : fields = List.unmodifiable(fields);

  /// The exact entry ID.
  final StreamId id;

  /// Ordered binary fields, including duplicate field names.
  final List<StreamField> fields;
}

/// The entries returned for one key by XREAD.
final class StreamRead {
  /// Creates an immutable per-key read result.
  StreamRead({required this.key, required Iterable<StreamEntry> entries})
    : entries = List.unmodifiable(entries);

  /// The Stream key as returned by Redis.
  final String key;

  /// Ordered entries for [key].
  final List<StreamEntry> entries;
}

/// Builds an XADD command, snapshotting every binary field and value.
RedisCommand<StreamId> xaddCommand(
  String key,
  List<StreamField> fields, {
  StreamId? id,
  int? maxLength,
  bool approximate = false,
}) {
  if (fields.isEmpty) {
    throw ArgumentError.value(fields, 'fields', 'must not be empty');
  }
  if (maxLength != null && maxLength < 0) {
    throw RangeError.range(maxLength, 0, null, 'maxLength');
  }
  if (maxLength == null && approximate) {
    throw ArgumentError.value(approximate, 'approximate', 'requires maxLength');
  }

  return RedisCommand<StreamId>.internal([
    RedisArgument.text('XADD'),
    RedisArgument.text(key),
    if (maxLength != null) ...[
      RedisArgument.text('MAXLEN'),
      if (approximate) RedisArgument.text('~'),
      RedisArgument.text('$maxLength'),
    ],
    RedisArgument.text(id?.toString() ?? '*'),
    for (final field in fields) ...[
      RedisArgument.bytes(field.field),
      RedisArgument.bytes(field.value),
    ],
  ], (reply) => StreamId.parse(respText(reply)));
}

/// Builds an XRANGE command with inclusive lower and upper bounds.
RedisCommand<List<StreamEntry>> xrangeCommand(
  String key, {
  StreamBound start = StreamBound.minimum,
  StreamBound end = StreamBound.maximum,
  int? count,
}) => _rangeCommand(
  command: 'XRANGE',
  key: key,
  firstWireBound: start,
  secondWireBound: end,
  count: count,
);

/// Builds an XREVRANGE command with inclusive lower and upper bounds.
RedisCommand<List<StreamEntry>> xrevrangeCommand(
  String key, {
  StreamBound start = StreamBound.minimum,
  StreamBound end = StreamBound.maximum,
  int? count,
}) => _rangeCommand(
  command: 'XREVRANGE',
  key: key,
  firstWireBound: end,
  secondWireBound: start,
  count: count,
);

/// Builds an XTRIM command for an explicit trimming strategy.
RedisCommand<int> xtrimCommand(String key, StreamTrim trim) => RedisCommand<int>.internal([
  RedisArgument.text('XTRIM'),
  RedisArgument.text(key),
  ..._trimArguments(trim),
], (reply) => reply.integer);

/// Builds an XLEN command.
RedisCommand<int> xlenCommand(String key) => RedisCommand<int>.internal([
  RedisArgument.text('XLEN'),
  RedisArgument.text(key),
], (reply) => reply.integer);

/// Builds a nonblocking XREAD command from concrete per-key cursors.
RedisCommand<List<StreamRead>> xreadCommand(Map<String, StreamId> after, {int? count}) {
  if (after.isEmpty) {
    throw ArgumentError.value(after, 'after', 'must not be empty');
  }
  _checkCount(count);
  final cursors = after.entries.toList(growable: false);
  return RedisCommand<List<StreamRead>>.internal([
    RedisArgument.text('XREAD'),
    if (count != null) ...[
      RedisArgument.text('COUNT'),
      RedisArgument.text('$count'),
    ],
    RedisArgument.text('STREAMS'),
    for (final cursor in cursors) RedisArgument.text(cursor.key),
    for (final cursor in cursors) RedisArgument.text(cursor.value.toString()),
  ], _streamReadsReply);
}

/// Typed ordinary Redis Stream commands.
extension RunnelStreamCommands on Runnel {
  /// Appends [fields] and returns the generated or supplied entry ID.
  Effect<StreamId, RunnelError> xadd(
    String key,
    List<StreamField> fields, {
    StreamId? id,
    int? maxLength,
    bool approximate = false,
    Duration? timeout,
  }) {
    final snapshot = List<StreamField>.of(fields);
    return deferCommand(
      () => xaddCommand(
        key,
        snapshot,
        id: id,
        maxLength: maxLength,
        approximate: approximate,
      ),
      timeout: timeout,
    );
  }

  /// Reads entries in ascending ID order between inclusive bounds.
  Effect<List<StreamEntry>, RunnelError> xrange(
    String key, {
    StreamBound start = StreamBound.minimum,
    StreamBound end = StreamBound.maximum,
    int? count,
    Duration? timeout,
  }) => deferCommand(
    () => xrangeCommand(key, start: start, end: end, count: count),
    timeout: timeout,
  );

  /// Reads entries in descending ID order between inclusive bounds.
  Effect<List<StreamEntry>, RunnelError> xrevrange(
    String key, {
    StreamBound start = StreamBound.minimum,
    StreamBound end = StreamBound.maximum,
    int? count,
    Duration? timeout,
  }) => deferCommand(
    () => xrevrangeCommand(key, start: start, end: end, count: count),
    timeout: timeout,
  );

  /// Trims a Stream and returns the number of entries removed.
  Effect<int, RunnelError> xtrim(String key, StreamTrim trim, {Duration? timeout}) =>
      deferCommand(() => xtrimCommand(key, trim), timeout: timeout);

  /// Returns the number of entries in a Stream.
  Effect<int, RunnelError> xlen(String key, {Duration? timeout}) =>
      deferCommand(() => xlenCommand(key), timeout: timeout);

  /// Reads entries newer than each concrete cursor without blocking.
  Effect<List<StreamRead>, RunnelError> xread(
    Map<String, StreamId> after, {
    int? count,
    Duration? timeout,
  }) {
    final snapshot = Map<String, StreamId>.of(after);
    return deferCommand(() => xreadCommand(snapshot, count: count), timeout: timeout);
  }
}

RedisCommand<List<StreamEntry>> _rangeCommand({
  required String command,
  required String key,
  required StreamBound firstWireBound,
  required StreamBound secondWireBound,
  required int? count,
}) {
  _checkCount(count);
  return RedisCommand<List<StreamEntry>>.internal([
    RedisArgument.text(command),
    RedisArgument.text(key),
    RedisArgument.text(_boundArgument(firstWireBound)),
    RedisArgument.text(_boundArgument(secondWireBound)),
    if (count != null) ...[
      RedisArgument.text('COUNT'),
      RedisArgument.text('$count'),
    ],
  ], _entriesReply);
}

String _boundArgument(StreamBound bound) => switch (bound) {
  _MinimumStreamBound() => '-',
  _MaximumStreamBound() => '+',
  _StreamIdBound(:final id) => id.toString(),
};

List<RedisArgument> _trimArguments(StreamTrim trim) => switch (trim) {
  _MaxLengthStreamTrim(:final count, :final approximate) => [
    RedisArgument.text('MAXLEN'),
    if (approximate) RedisArgument.text('~'),
    RedisArgument.text('$count'),
  ],
  _MinIdStreamTrim(:final id, :final approximate) => [
    RedisArgument.text('MINID'),
    if (approximate) RedisArgument.text('~'),
    RedisArgument.text(id.toString()),
  ],
};

void _checkCount(int? count) {
  if (count != null && count <= 0) {
    throw RangeError.range(count, 1, null, 'count');
  }
}

List<StreamEntry> _entriesReply(RespValue reply) =>
    List.unmodifiable(_arrayValues(reply, 'Stream entries').map(_streamEntry));

StreamEntry _streamEntry(RespValue reply) {
  final entry = _arrayValues(reply, 'Stream entry');
  if (entry.length != 2) {
    throw const FormatException('Expected a Stream entry with an ID and fields.');
  }
  final fields = _arrayValues(entry[1], 'Stream fields');
  if (fields.isEmpty || fields.length.isOdd) {
    throw const FormatException('Expected one or more Stream field/value pairs.');
  }
  return StreamEntry(
    id: StreamId.parse(respText(entry[0])),
    fields: [
      for (var index = 0; index < fields.length; index += 2)
        StreamField(_binaryReply(fields[index]), _binaryReply(fields[index + 1])),
    ],
  );
}

List<StreamRead> _streamReadsReply(RespValue reply) => switch (reply) {
  const RespNull() => const [],
  RespMap(:final entries) => List.unmodifiable(
    entries.map(
      (entry) => StreamRead(key: respText(entry.key), entries: _entriesReply(entry.value)),
    ),
  ),
  _ => throw FormatException('Expected an XREAD reply, received ${reply.runtimeType}.'),
};

List<RespValue> _arrayValues(RespValue reply, String name) => switch (reply) {
  RespArray(:final values) => values,
  _ => throw FormatException('Expected $name as an array, received ${reply.runtimeType}.'),
};

Uint8List _binaryReply(RespValue reply) => switch (reply) {
  RespBlobString(:final value) => Uint8List.fromList(value),
  RespSimpleString(:final value) => Uint8List.fromList(utf8.encode(value)),
  _ => throw FormatException('Expected a binary field, received ${reply.runtimeType}.'),
};
