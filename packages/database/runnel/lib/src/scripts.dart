import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:runnel/src/command.dart';
import 'package:runnel/src/resp/resp_value.dart';

/// An immutable Lua source program and its typed result decoder.
final class RedisScript<T> {
  /// Creates a script whose accessed keys and arguments are supplied at execution.
  RedisScript(String source, T Function(RespValue reply) decode)
    : source = source,
      sha1 = _sha1Hash(source),
      _decode = decode;

  /// Lua source sent by [evalCommand] when Redis does not have the script cached.
  final String source;

  /// Lowercase hexadecimal SHA-1 digest used by [evalshaCommand].
  final String sha1;

  final T Function(RespValue reply) _decode;

  /// Converts one successful script reply into the caller's result type.
  T decode(RespValue reply) => _decode(reply);
}

/// Builds an EVAL command that keeps the script in its pipeline or transaction position.
RedisCommand<T> evalCommand<T>(
  RedisScript<T> script, {
  required List<String> keys,
  required List<RedisArgument> arguments,
}) => _scriptCommand('EVAL', script.source, script, keys, arguments);

/// Builds an EVALSHA command for an ordinarily cached script execution.
RedisCommand<T> evalshaCommand<T>(
  RedisScript<T> script, {
  required List<String> keys,
  required List<RedisArgument> arguments,
}) => _scriptCommand('EVALSHA', script.sha1, script, keys, arguments);

RedisCommand<T> _scriptCommand<T>(
  String command,
  String scriptIdentifier,
  RedisScript<T> script,
  List<String> keys,
  List<RedisArgument> arguments,
) {
  final ownedKeys = List<String>.of(keys);
  final ownedArguments = List<RedisArgument>.of(arguments);
  return RedisCommand<T>.internal([
    RedisArgument.text(command),
    RedisArgument.text(scriptIdentifier),
    RedisArgument.text('${ownedKeys.length}'),
    for (final key in ownedKeys) RedisArgument.text(key),
    ...ownedArguments,
  ], script.decode);
}

String _sha1Hash(String source) => sha1.convert(utf8.encode(source)).toString();
