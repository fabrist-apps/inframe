import 'package:conflux/effect.dart';
import 'package:conflux/option.dart';
import 'package:runnel/src/client.dart';
import 'package:runnel/src/command.dart';
import 'package:runnel/src/commands/execution.dart';
import 'package:runnel/src/commands/reply_decoding.dart';
import 'package:runnel/src/errors.dart';
import 'package:runnel/src/resp/resp_value.dart';

/// A sorted-set member paired with its Redis score.
typedef ScoredMember = ({String member, double score});

/// Builds an HSET command and snapshots [fields] in map iteration order.
RedisCommand<int> hsetCommand(String key, Map<String, String> fields) {
  final entries = _nonEmptyMapEntries(fields, 'fields');
  return _command('HSET', [
    key,
    for (final entry in entries) ...[entry.key, entry.value],
  ], (reply) => reply.integer);
}

/// Builds an HGET command for one optional field value.
RedisCommand<Option<String>> hgetCommand(String key, String field) =>
    _command('HGET', [key, field], (reply) => reply.optionalText);

/// Builds an HMGET command that preserves field order and duplicates.
RedisCommand<List<Option<String>>> hmgetCommand(String key, List<String> fields) {
  final snapshot = _nonEmptyList(fields, 'fields');
  return _command('HMGET', [key, ...snapshot], (reply) => reply.optionalTextList);
}

/// Builds an HGETALL command returning an immutable field map.
RedisCommand<Map<String, String>> hgetallCommand(String key) =>
    _command('HGETALL', [key], _textMap);

/// Builds an HDEL command that preserves field order and duplicates.
RedisCommand<int> hdelCommand(String key, List<String> fields) {
  final snapshot = _nonEmptyList(fields, 'fields');
  return _command('HDEL', [key, ...snapshot], (reply) => reply.integer);
}

/// Builds an HEXISTS command for one field predicate.
RedisCommand<bool> hexistsCommand(String key, String field) =>
    _command('HEXISTS', [key, field], _predicate);

/// Builds an HLEN command.
RedisCommand<int> hlenCommand(String key) => _command('HLEN', [key], (reply) => reply.integer);

/// Builds an HINCRBY command.
RedisCommand<int> hincrbyCommand(String key, String field, int increment) =>
    _command('HINCRBY', [key, field, '$increment'], (reply) => reply.integer);

/// Builds an SADD command that preserves member order and duplicates.
RedisCommand<int> saddCommand(String key, List<String> members) {
  final snapshot = _nonEmptyList(members, 'members');
  return _command('SADD', [key, ...snapshot], (reply) => reply.integer);
}

/// Builds an SREM command that preserves member order and duplicates.
RedisCommand<int> sremCommand(String key, List<String> members) {
  final snapshot = _nonEmptyList(members, 'members');
  return _command('SREM', [key, ...snapshot], (reply) => reply.integer);
}

/// Builds an SISMEMBER command for one member predicate.
RedisCommand<bool> sismemberCommand(String key, String member) =>
    _command('SISMEMBER', [key, member], _predicate);

/// Builds an SMEMBERS command returning an immutable set.
RedisCommand<Set<String>> smembersCommand(String key) => _command('SMEMBERS', [key], _textSet);

/// Builds an SCARD command.
RedisCommand<int> scardCommand(String key) => _command('SCARD', [key], (reply) => reply.integer);

/// Builds an LPUSH command that preserves element order and duplicates.
RedisCommand<int> lpushCommand(String key, List<String> elements) {
  final snapshot = _nonEmptyList(elements, 'elements');
  return _command('LPUSH', [key, ...snapshot], (reply) => reply.integer);
}

/// Builds an RPUSH command that preserves element order and duplicates.
RedisCommand<int> rpushCommand(String key, List<String> elements) {
  final snapshot = _nonEmptyList(elements, 'elements');
  return _command('RPUSH', [key, ...snapshot], (reply) => reply.integer);
}

/// Builds a scalar LPOP command.
RedisCommand<Option<String>> lpopCommand(String key) =>
    _command('LPOP', [key], (reply) => reply.optionalText);

/// Builds a scalar RPOP command.
RedisCommand<Option<String>> rpopCommand(String key) =>
    _command('RPOP', [key], (reply) => reply.optionalText);

/// Builds an LRANGE command with inclusive rank endpoints.
RedisCommand<List<String>> lrangeCommand(String key, int start, int stop) =>
    _command('LRANGE', [key, '$start', '$stop'], _textList);

/// Builds an LLEN command.
RedisCommand<int> llenCommand(String key) => _command('LLEN', [key], (reply) => reply.integer);

/// Builds an LTRIM command with inclusive rank endpoints.
RedisCommand<void> ltrimCommand(String key, int start, int stop) =>
    _command('LTRIM', [key, '$start', '$stop'], (reply) => reply.requireOkay());

/// Builds a default add-or-update ZADD command and snapshots [members].
RedisCommand<int> zaddCommand(String key, Map<String, double> members) {
  final entries = _nonEmptyMapEntries(members, 'members');
  for (final entry in entries) {
    _finite(entry.value, 'members');
  }
  return _command('ZADD', [
    key,
    for (final entry in entries) ...['${entry.value}', entry.key],
  ], (reply) => reply.integer);
}

/// Builds a ZREM command that preserves member order and duplicates.
RedisCommand<int> zremCommand(String key, List<String> members) {
  final snapshot = _nonEmptyList(members, 'members');
  return _command('ZREM', [key, ...snapshot], (reply) => reply.integer);
}

/// Builds a ZCARD command.
RedisCommand<int> zcardCommand(String key) => _command('ZCARD', [key], (reply) => reply.integer);

/// Builds a ZSCORE command for one optional member score.
RedisCommand<Option<double>> zscoreCommand(String key, String member) =>
    _command('ZSCORE', [key, member], _optionalDouble);

/// Builds a ZINCRBY command with a finite increment.
RedisCommand<double> zincrbyCommand(String key, double increment, String member) {
  _finite(increment, 'increment');
  return _command('ZINCRBY', [key, '$increment', member], _double);
}

/// Builds a rank-based ZRANGE command with inclusive endpoints.
RedisCommand<List<String>> zrangeCommand(String key, int start, int stop) =>
    _command('ZRANGE', [key, '$start', '$stop'], _textList);

/// Builds a rank-based ZRANGE command returning member-score records.
RedisCommand<List<ScoredMember>> zrangeWithScoresCommand(
  String key,
  int start,
  int stop,
) => _command('ZRANGE', [key, '$start', '$stop', 'WITHSCORES'], _scoredMembers);

/// Builds a ZRANGEBYSCORE command with inclusive finite bounds.
RedisCommand<List<String>> zrangebyscoreCommand(
  String key,
  double minimum,
  double maximum,
) {
  _finite(minimum, 'minimum');
  _finite(maximum, 'maximum');
  return _command('ZRANGEBYSCORE', [key, '$minimum', '$maximum'], _textList);
}

/// Builds a ZREMRANGEBYSCORE command with inclusive finite bounds.
RedisCommand<int> zremrangebyscoreCommand(
  String key,
  double minimum,
  double maximum,
) {
  _finite(minimum, 'minimum');
  _finite(maximum, 'maximum');
  return _command('ZREMRANGEBYSCORE', [key, '$minimum', '$maximum'], (reply) => reply.integer);
}

/// Typed hash, set, list, and sorted-set commands.
extension RunnelCollectionCommands on Runnel {
  /// Sets [fields] and returns the number of newly added fields.
  Effect<int, RunnelError> hset(
    String key,
    Map<String, String> fields, {
    Duration? timeout,
  }) {
    final snapshot = Map<String, String>.of(fields);
    return deferCommand(() => hsetCommand(key, snapshot), timeout: timeout);
  }

  /// Reads one hash field, returning None when it does not exist.
  Effect<Option<String>, RunnelError> hget(String key, String field, {Duration? timeout}) =>
      deferCommand(() => hgetCommand(key, field), timeout: timeout);

  /// Reads hash [fields] in input order, preserving missing entries as None.
  Effect<List<Option<String>>, RunnelError> hmget(
    String key,
    List<String> fields, {
    Duration? timeout,
  }) {
    final snapshot = List<String>.of(fields);
    return deferCommand(() => hmgetCommand(key, snapshot), timeout: timeout);
  }

  /// Reads every field and value from a hash.
  Effect<Map<String, String>, RunnelError> hgetall(String key, {Duration? timeout}) =>
      deferCommand(() => hgetallCommand(key), timeout: timeout);

  /// Deletes [fields] and returns the number removed.
  Effect<int, RunnelError> hdel(
    String key,
    List<String> fields, {
    Duration? timeout,
  }) {
    final snapshot = List<String>.of(fields);
    return deferCommand(() => hdelCommand(key, snapshot), timeout: timeout);
  }

  /// Reports whether [field] exists in the hash.
  Effect<bool, RunnelError> hexists(String key, String field, {Duration? timeout}) =>
      deferCommand(() => hexistsCommand(key, field), timeout: timeout);

  /// Returns the number of fields in the hash.
  Effect<int, RunnelError> hlen(String key, {Duration? timeout}) =>
      deferCommand(() => hlenCommand(key), timeout: timeout);

  /// Adds [increment] to an integer hash field and returns its new value.
  Effect<int, RunnelError> hincrby(
    String key,
    String field,
    int increment, {
    Duration? timeout,
  }) => deferCommand(() => hincrbyCommand(key, field, increment), timeout: timeout);

  /// Adds [members] and returns the number newly added.
  Effect<int, RunnelError> sadd(
    String key,
    List<String> members, {
    Duration? timeout,
  }) {
    final snapshot = List<String>.of(members);
    return deferCommand(() => saddCommand(key, snapshot), timeout: timeout);
  }

  /// Removes [members] and returns the number removed.
  Effect<int, RunnelError> srem(
    String key,
    List<String> members, {
    Duration? timeout,
  }) {
    final snapshot = List<String>.of(members);
    return deferCommand(() => sremCommand(key, snapshot), timeout: timeout);
  }

  /// Reports whether [member] belongs to the set.
  Effect<bool, RunnelError> sismember(String key, String member, {Duration? timeout}) =>
      deferCommand(() => sismemberCommand(key, member), timeout: timeout);

  /// Reads the set's members as an immutable snapshot.
  Effect<Set<String>, RunnelError> smembers(String key, {Duration? timeout}) =>
      deferCommand(() => smembersCommand(key), timeout: timeout);

  /// Returns the set's member count.
  Effect<int, RunnelError> scard(String key, {Duration? timeout}) =>
      deferCommand(() => scardCommand(key), timeout: timeout);

  /// Prepends [elements] and returns the list's new length.
  Effect<int, RunnelError> lpush(
    String key,
    List<String> elements, {
    Duration? timeout,
  }) {
    final snapshot = List<String>.of(elements);
    return deferCommand(() => lpushCommand(key, snapshot), timeout: timeout);
  }

  /// Appends [elements] and returns the list's new length.
  Effect<int, RunnelError> rpush(
    String key,
    List<String> elements, {
    Duration? timeout,
  }) {
    final snapshot = List<String>.of(elements);
    return deferCommand(() => rpushCommand(key, snapshot), timeout: timeout);
  }

  /// Removes and returns the first element, or None when the list is empty.
  Effect<Option<String>, RunnelError> lpop(String key, {Duration? timeout}) =>
      deferCommand(() => lpopCommand(key), timeout: timeout);

  /// Removes and returns the last element, or None when the list is empty.
  Effect<Option<String>, RunnelError> rpop(String key, {Duration? timeout}) =>
      deferCommand(() => rpopCommand(key), timeout: timeout);

  /// Reads the inclusive rank range from [start] through [stop].
  Effect<List<String>, RunnelError> lrange(
    String key,
    int start,
    int stop, {
    Duration? timeout,
  }) => deferCommand(() => lrangeCommand(key, start, stop), timeout: timeout);

  /// Returns the list length.
  Effect<int, RunnelError> llen(String key, {Duration? timeout}) =>
      deferCommand(() => llenCommand(key), timeout: timeout);

  /// Keeps the inclusive rank range.
  Effect<void, RunnelError> ltrim(
    String key,
    int start,
    int stop, {
    Duration? timeout,
  }) => deferCommand(() => ltrimCommand(key, start, stop), timeout: timeout);

  /// Adds or updates [members] and returns the number newly added.
  Effect<int, RunnelError> zadd(
    String key,
    Map<String, double> members, {
    Duration? timeout,
  }) {
    final snapshot = Map<String, double>.of(members);
    return deferCommand(() => zaddCommand(key, snapshot), timeout: timeout);
  }

  /// Removes [members] and returns the number removed.
  Effect<int, RunnelError> zrem(
    String key,
    List<String> members, {
    Duration? timeout,
  }) {
    final snapshot = List<String>.of(members);
    return deferCommand(() => zremCommand(key, snapshot), timeout: timeout);
  }

  /// Returns the sorted set's member count.
  Effect<int, RunnelError> zcard(String key, {Duration? timeout}) =>
      deferCommand(() => zcardCommand(key), timeout: timeout);

  /// Reads [member]'s score, returning None when it does not exist.
  Effect<Option<double>, RunnelError> zscore(String key, String member, {Duration? timeout}) =>
      deferCommand(() => zscoreCommand(key, member), timeout: timeout);

  /// Adds [increment] to [member]'s score and returns its new score.
  Effect<double, RunnelError> zincrby(
    String key,
    double increment,
    String member, {
    Duration? timeout,
  }) => deferCommand(() => zincrbyCommand(key, increment, member), timeout: timeout);

  /// Reads members in the inclusive rank range from [start] through [stop].
  Effect<List<String>, RunnelError> zrange(
    String key,
    int start,
    int stop, {
    Duration? timeout,
  }) => deferCommand(() => zrangeCommand(key, start, stop), timeout: timeout);

  /// Reads members and scores in the inclusive rank range.
  Effect<List<ScoredMember>, RunnelError> zrangeWithScores(
    String key,
    int start,
    int stop, {
    Duration? timeout,
  }) => deferCommand(() => zrangeWithScoresCommand(key, start, stop), timeout: timeout);

  /// Reads members whose scores are within the inclusive finite bounds.
  Effect<List<String>, RunnelError> zrangebyscore(
    String key,
    double minimum,
    double maximum, {
    Duration? timeout,
  }) => deferCommand(() => zrangebyscoreCommand(key, minimum, maximum), timeout: timeout);

  /// Removes members whose scores are within the inclusive finite bounds.
  Effect<int, RunnelError> zremrangebyscore(
    String key,
    double minimum,
    double maximum, {
    Duration? timeout,
  }) => deferCommand(() => zremrangebyscoreCommand(key, minimum, maximum), timeout: timeout);
}

RedisCommand<T> _command<T>(
  String name,
  List<String> arguments,
  T Function(RespValue reply) decode,
) => RedisCommand<T>.internal([
  RedisArgument.text(name),
  for (final argument in arguments) RedisArgument.text(argument),
], decode);

List<T> _nonEmptyList<T>(List<T> values, String name) {
  if (values.isEmpty) {
    throw ArgumentError.value(values, name, 'must not be empty');
  }
  return List<T>.unmodifiable(values);
}

List<MapEntry<K, V>> _nonEmptyMapEntries<K, V>(Map<K, V> values, String name) {
  if (values.isEmpty) {
    throw ArgumentError.value(values, name, 'must not be empty');
  }
  return List<MapEntry<K, V>>.unmodifiable(values.entries);
}

void _finite(double value, String name) {
  if (!value.isFinite) {
    throw ArgumentError.value(value, name, 'must be finite');
  }
}

bool _predicate(RespValue reply) => switch (reply) {
  RespInteger(value: 0) => false,
  RespInteger(value: 1) => true,
  RespBoolean(:final value) => value,
  _ => throw FormatException('Expected a predicate reply, received ${reply.runtimeType}.'),
};

Option<double> _optionalDouble(RespValue reply) => switch (reply) {
  const RespNull() => const None(),
  _ => Some(_double(reply)),
};

double _double(RespValue reply) {
  if (reply is! RespDouble || !reply.value.isFinite) {
    throw FormatException('Expected a finite score reply, received ${reply.runtimeType}.');
  }
  return reply.value;
}

List<String> _textList(RespValue reply) => List<String>.unmodifiable(reply.array.map(respText));

Set<String> _textSet(RespValue reply) {
  final values = switch (reply) {
    RespSet(:final values) => values,
    _ => throw FormatException('Expected a set reply, received ${reply.runtimeType}.'),
  };
  return Set<String>.unmodifiable(values.map(respText));
}

Map<String, String> _textMap(RespValue reply) {
  if (reply is! RespMap) {
    throw FormatException('Expected a map reply, received ${reply.runtimeType}.');
  }
  final entries = reply.entries
      .map((entry) => MapEntry(respText(entry.key), respText(entry.value)))
      .toList(growable: false);
  return Map<String, String>.unmodifiable(Map.fromEntries(entries));
}

List<ScoredMember> _scoredMembers(RespValue reply) {
  final values = reply.array;
  return List<ScoredMember>.unmodifiable(
    values.map((value) {
      if (value is! RespArray || value.values.length != 2) {
        throw const FormatException('Expected a member and score pair.');
      }
      return (member: respText(value.values[0]), score: _double(value.values[1]));
    }),
  );
}
