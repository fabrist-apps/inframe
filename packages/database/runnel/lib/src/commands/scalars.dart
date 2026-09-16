import 'dart:typed_data';

import 'package:conflux/effect.dart';
import 'package:conflux/option.dart';
import 'package:runnel/src/client.dart';
import 'package:runnel/src/command.dart';
import 'package:runnel/src/commands/reply_decoding.dart';
import 'package:runnel/src/errors.dart';
import 'package:runnel/src/resp/resp_value.dart';

/// Controls whether Redis applies a SET operation.
enum SetCondition {
  /// Apply the write regardless of whether the key exists.
  always,

  /// Apply the write only when the key does not exist.
  ifAbsent,

  /// Apply the write only when the key already exists.
  ifPresent,
}

/// Expiration behavior for a SET operation.
sealed class Expiry {
  const Expiry._();

  /// Expires the key after a positive whole-millisecond [duration].
  factory Expiry.after(Duration duration) {
    _requireWholeMilliseconds(duration, 'duration', positive: true);
    return _AfterExpiry(duration.inMilliseconds);
  }

  /// Expires the key at a positive whole-millisecond Unix [instant].
  factory Expiry.at(DateTime instant) {
    final microseconds = instant.microsecondsSinceEpoch;
    if (microseconds <= 0 || microseconds % Duration.microsecondsPerMillisecond != 0) {
      throw ArgumentError.value(
        instant,
        'instant',
        'must be a positive whole-millisecond Unix timestamp',
      );
    }
    return _AtExpiry(instant.millisecondsSinceEpoch);
  }

  /// Retains the key's existing expiration.
  const factory Expiry.keep() = _KeepExpiry;
}

final class _AfterExpiry extends Expiry {
  const _AfterExpiry(this.milliseconds) : super._();

  final int milliseconds;
}

final class _AtExpiry extends Expiry {
  const _AtExpiry(this.millisecondsSinceEpoch) : super._();

  final int millisecondsSinceEpoch;
}

final class _KeepExpiry extends Expiry {
  const _KeepExpiry() : super._();
}

/// One decoded SCAN page.
final class ScanPage {
  /// Creates an immutable cursor and key page.
  ScanPage({required this.cursor, required Iterable<String> keys}) : keys = List.unmodifiable(keys);

  /// Cursor to supply to the next SCAN request, or `0` when iteration is complete.
  final String cursor;

  /// Keys returned in wire order, including duplicates.
  final List<String> keys;
}

/// Builds a typed GET command for strict UTF-8 text.
RedisCommand<Option<String>> getCommand(String key) => Get(key);

/// A typed GET command for strict UTF-8 text.
final class Get extends RedisCommand<Option<String>> {
  /// Creates a GET command for [key].
  Get(String key)
    : super.internal(
        [RedisArgument.text('GET'), RedisArgument.text(key)],
        (reply) => reply is RespNull ? const None() : Some(respText(reply)),
      );
}

/// Builds a typed binary GET command.
RedisCommand<Uint8List?> getBytesCommand(String key) => RedisCommand<Uint8List?>.internal(
  [RedisArgument.text('GET'), RedisArgument.text(key)],
  _decodeNullableBytes,
);

/// Builds a typed text SET command.
RedisCommand<bool> setCommand(
  String key,
  String value, {
  SetCondition condition = SetCondition.always,
  Expiry? expiry,
}) => _setCommand(
  key,
  RedisArgument.text(value),
  condition: condition,
  expiry: expiry,
);

/// Builds a typed binary SET command and snapshots [value].
RedisCommand<bool> setBytesCommand(
  String key,
  Uint8List value, {
  SetCondition condition = SetCondition.always,
  Expiry? expiry,
}) => _setCommand(
  key,
  RedisArgument.bytes(value),
  condition: condition,
  expiry: expiry,
);

/// Builds an MGET command that preserves key order and duplicates.
RedisCommand<List<String?>> mgetCommand(Iterable<String> keys) {
  final snapshot = _nonEmpty(keys, 'keys');
  return RedisCommand<List<String?>>.internal(
    [RedisArgument.text('MGET'), ...snapshot.map(RedisArgument.text)],
    (reply) => reply.nullableTextList,
  );
}

/// Builds an MSET command that snapshots entries in iteration order.
RedisCommand<void> msetCommand(Map<String, String> values) {
  if (values.isEmpty) throw ArgumentError.value(values, 'values', 'must not be empty');
  final entries = List<MapEntry<String, String>>.of(values.entries);
  return RedisCommand<void>.internal([
    RedisArgument.text('MSET'),
    for (final entry in entries) ...[
      RedisArgument.text(entry.key),
      RedisArgument.text(entry.value),
    ],
  ], (reply) => reply.requireOkay(message: 'Expected an OK status reply.'));
}

/// Builds an INCR command.
RedisCommand<int> incrCommand(String key) => Incr(key);

/// A typed INCR command.
final class Incr extends RedisCommand<int> {
  /// Creates an INCR command for [key].
  Incr(String key)
    : super.internal([
        RedisArgument.text('INCR'),
        RedisArgument.text(key),
      ], (reply) => reply.integer);
}

/// Builds an INCRBY command.
RedisCommand<int> incrbyCommand(String key, int increment) =>
    _integerCommand('INCRBY', [key, '$increment']);

/// Builds a DECR command.
RedisCommand<int> decrCommand(String key) => _integerCommand('DECR', [key]);

/// Builds a DECRBY command.
RedisCommand<int> decrbyCommand(String key, int decrement) =>
    _integerCommand('DECRBY', [key, '$decrement']);

/// Builds a DEL command that preserves key order and duplicates.
RedisCommand<int> delCommand(Iterable<String> keys) => _keysCommand('DEL', keys);

/// Builds an UNLINK command that preserves key order and duplicates.
RedisCommand<int> unlinkCommand(Iterable<String> keys) => _keysCommand('UNLINK', keys);

/// Builds an EXISTS command that preserves key order and duplicates.
RedisCommand<int> existsCommand(Iterable<String> keys) => _keysCommand('EXISTS', keys);

/// Builds a PERSIST command.
RedisCommand<bool> persistCommand(String key) => _predicateCommand('PERSIST', [key]);

/// Builds a PEXPIRE command, including immediate zero or negative expiration.
RedisCommand<bool> expireCommand(String key, Duration duration) {
  _requireWholeMilliseconds(duration, 'duration');
  return _predicateCommand('PEXPIRE', [key, '${duration.inMilliseconds}']);
}

/// Builds a PTTL command that preserves Redis's `-1` and `-2` sentinels.
RedisCommand<int> pttlCommand(String key) => _integerCommand('PTTL', [key]);

/// Builds a TYPE command.
RedisCommand<String> typeCommand(String key) => RedisCommand<String>.internal(
  [RedisArgument.text('TYPE'), RedisArgument.text(key)],
  respText,
);

/// Builds one SCAN page request.
RedisCommand<ScanPage> scanCommand(
  String cursor, {
  String? match,
  int? count,
}) {
  if (count != null && count <= 0) {
    throw ArgumentError.value(count, 'count', 'must be positive');
  }
  return RedisCommand<ScanPage>.internal([
    RedisArgument.text('SCAN'),
    RedisArgument.text(cursor),
    if (match != null) ...[RedisArgument.text('MATCH'), RedisArgument.text(match)],
    if (count != null) ...[RedisArgument.text('COUNT'), RedisArgument.text('$count')],
  ], _decodeScanPage);
}

/// Scalar and key conveniences for [Runnel].
extension RunnelScalarCommands on Runnel {
  /// Reads strict UTF-8 text, returning null when [key] is missing.
  Effect<Option<String>, RunnelError> get(String key, {Duration? timeout}) =>
      execute(getCommand(key), timeout: timeout);

  /// Reads binary data, returning null when [key] is missing.
  Future<Uint8List?> getBytes(String key, {Duration? timeout}) =>
      executeFuture(getBytesCommand(key), timeout: timeout);

  /// Stores text and reports whether Redis applied the write.
  Effect<bool, RunnelError> set(
    String key,
    String value, {
    SetCondition condition = SetCondition.always,
    Expiry? expiry,
    Duration? timeout,
  }) => execute(
    setCommand(key, value, condition: condition, expiry: expiry),
    timeout: timeout,
  );

  /// Stores binary data and reports whether Redis applied the write.
  Future<bool> setBytes(
    String key,
    Uint8List value, {
    SetCondition condition = SetCondition.always,
    Expiry? expiry,
    Duration? timeout,
  }) => executeFuture(
    setBytesCommand(key, value, condition: condition, expiry: expiry),
    timeout: timeout,
  );

  /// Reads multiple strict UTF-8 values in key order.
  Future<List<String?>> mget(Iterable<String> keys, {Duration? timeout}) =>
      executeFuture(mgetCommand(keys), timeout: timeout);

  /// Stores multiple text values atomically.
  Future<void> mset(Map<String, String> values, {Duration? timeout}) =>
      executeFuture(msetCommand(values), timeout: timeout);

  /// Increments the integer value at [key] by one.
  Future<int> incr(String key, {Duration? timeout}) =>
      executeFuture(incrCommand(key), timeout: timeout);

  /// Increments the integer value at [key] by [increment].
  Future<int> incrby(String key, int increment, {Duration? timeout}) =>
      executeFuture(incrbyCommand(key, increment), timeout: timeout);

  /// Decrements the integer value at [key] by one.
  Future<int> decr(String key, {Duration? timeout}) =>
      executeFuture(decrCommand(key), timeout: timeout);

  /// Decrements the integer value at [key] by [decrement].
  Future<int> decrby(String key, int decrement, {Duration? timeout}) =>
      executeFuture(decrbyCommand(key, decrement), timeout: timeout);

  /// Deletes [keys] synchronously and returns the number removed.
  Future<int> del(Iterable<String> keys, {Duration? timeout}) =>
      executeFuture(delCommand(keys), timeout: timeout);

  /// Schedules [keys] for asynchronous deletion and returns the number removed.
  Future<int> unlink(Iterable<String> keys, {Duration? timeout}) =>
      executeFuture(unlinkCommand(keys), timeout: timeout);

  /// Counts how many of [keys] exist, preserving duplicate-key Redis semantics.
  Future<int> exists(Iterable<String> keys, {Duration? timeout}) =>
      executeFuture(existsCommand(keys), timeout: timeout);

  /// Removes the expiration from [key].
  Future<bool> persist(String key, {Duration? timeout}) =>
      executeFuture(persistCommand(key), timeout: timeout);

  /// Applies a whole-millisecond expiration to [key].
  ///
  /// Zero and negative durations retain Redis's immediate-deletion behavior.
  Future<bool> expire(String key, Duration duration, {Duration? timeout}) =>
      executeFuture(expireCommand(key, duration), timeout: timeout);

  /// Returns the remaining expiration in milliseconds, including `-1` and `-2`.
  Future<int> pttl(String key, {Duration? timeout}) =>
      executeFuture(pttlCommand(key), timeout: timeout);

  /// Returns Redis's type name for [key], including `none` when it is missing.
  Future<String> type(String key, {Duration? timeout}) =>
      executeFuture(typeCommand(key), timeout: timeout);

  /// Iterates SCAN pages as requested by the listener.
  ///
  /// SCAN is not a snapshot and can emit duplicate keys. Each page receives its own [timeout].
  /// Cancelling stops new page requests but cannot retract a page already sent to Redis.
  Stream<String> scan({String? match, int? count, Duration? timeout}) async* {
    var cursor = '0';
    do {
      final page = await executeFuture(
        scanCommand(cursor, match: match, count: count),
        timeout: timeout,
      );
      cursor = page.cursor;
      for (final key in page.keys) {
        yield key;
      }
    } while (cursor != '0');
  }
}

RedisCommand<bool> _setCommand(
  String key,
  RedisArgument value, {
  required SetCondition condition,
  required Expiry? expiry,
}) => RedisCommand<bool>.internal([
  RedisArgument.text('SET'),
  RedisArgument.text(key),
  value,
  ..._expiryArguments(expiry),
  if (condition == SetCondition.ifAbsent) RedisArgument.text('NX'),
  if (condition == SetCondition.ifPresent) RedisArgument.text('XX'),
], _decodeSet);

Iterable<RedisArgument> _expiryArguments(Expiry? expiry) => switch (expiry) {
  null => const [],
  _AfterExpiry(:final milliseconds) => [
    RedisArgument.text('PX'),
    RedisArgument.text('$milliseconds'),
  ],
  _AtExpiry(:final millisecondsSinceEpoch) => [
    RedisArgument.text('PXAT'),
    RedisArgument.text('$millisecondsSinceEpoch'),
  ],
  _KeepExpiry() => [RedisArgument.text('KEEPTTL')],
};

RedisCommand<int> _keysCommand(String name, Iterable<String> keys) {
  final snapshot = _nonEmpty(keys, 'keys');
  return _integerCommand(name, snapshot);
}

RedisCommand<int> _integerCommand(String name, Iterable<String> arguments) =>
    RedisCommand<int>.internal([
      RedisArgument.text(name),
      ...arguments.map(RedisArgument.text),
    ], (reply) => reply.integer);

RedisCommand<bool> _predicateCommand(String name, Iterable<String> arguments) =>
    RedisCommand<bool>.internal([
      RedisArgument.text(name),
      ...arguments.map(RedisArgument.text),
    ], _decodePredicate);

List<String> _nonEmpty(Iterable<String> values, String name) {
  final snapshot = List<String>.of(values);
  if (snapshot.isEmpty) throw ArgumentError.value(values, name, 'must not be empty');
  return snapshot;
}

Uint8List? _decodeNullableBytes(RespValue reply) => switch (reply) {
  RespNull() => null,
  RespBlobString(:final value) => Uint8List.fromList(value),
  _ => throw FormatException('Expected a binary or null reply, received ${reply.runtimeType}.'),
};

bool _decodeSet(RespValue reply) => switch (reply) {
  RespNull() => false,
  RespSimpleString(value: 'OK') || RespBlobString(value: [79, 75]) => true,
  _ => throw FormatException('Expected an OK or null SET reply, received ${reply.runtimeType}.'),
};

bool _decodePredicate(RespValue reply) => switch (reply) {
  RespInteger(value: 0) => false,
  RespInteger(value: 1) => true,
  _ => throw FormatException('Expected a zero-or-one reply, received ${reply.runtimeType}.'),
};

ScanPage _decodeScanPage(RespValue reply) {
  if (reply case RespArray(values: [final cursorReply, RespArray(:final values)])) {
    final cursor = respText(cursorReply);
    if (!_isDecimal(cursor)) throw const FormatException('Expected a decimal SCAN cursor.');
    return ScanPage(cursor: cursor, keys: values.map(respText));
  }
  throw FormatException(
    'Expected a cursor and key-array SCAN reply, received ${reply.runtimeType}.',
  );
}

bool _isDecimal(String value) {
  if (value.isEmpty) return false;
  for (final codeUnit in value.codeUnits) {
    if (codeUnit < 48 || codeUnit > 57) return false;
  }
  return true;
}

void _requireWholeMilliseconds(Duration duration, String name, {bool positive = false}) {
  if (duration.inMicroseconds % Duration.microsecondsPerMillisecond != 0 ||
      (positive && duration <= Duration.zero)) {
    throw ArgumentError.value(
      duration,
      name,
      positive ? 'must be positive whole milliseconds' : 'must use whole milliseconds',
    );
  }
}
