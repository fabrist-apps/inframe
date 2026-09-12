import 'dart:convert';
import 'dart:typed_data';

import 'package:runnel/src/resp/resp_value.dart';

/// One explicitly encoded Redis command argument.
final class RedisArgument {
  RedisArgument._(List<int> bytes) : _bytes = Uint8List.fromList(bytes);

  /// Encodes text as UTF-8.
  factory RedisArgument.text(String value) => RedisArgument._(utf8.encode(value));

  /// Snapshots arbitrary binary data.
  factory RedisArgument.bytes(Uint8List value) => RedisArgument._(value);

  final Uint8List _bytes;

  /// An owned copy of the wire bytes.
  Uint8List get bytes => Uint8List.fromList(_bytes);
}

/// A typed ordinary one-command/one-reply operation.
base class RedisCommand<T> {
  /// Creates a custom typed command from explicit arguments and a reply decoder.
  RedisCommand(List<RedisArgument> arguments, T Function(RespValue reply) decode)
    : arguments = List.unmodifiable(arguments),
      _decode = decode {
    if (arguments.isEmpty) throw ArgumentError.value(arguments, 'arguments', 'must not be empty');
  }

  /// Immutable command arguments, including the command name.
  final List<RedisArgument> arguments;
  final T Function(RespValue reply) _decode;

  /// Converts one non-error reply into the command result.
  T decode(RespValue reply) => _decode(reply);
}

/// Encodes a command as one RESP array of bulk-string arguments.
Uint8List encodeCommand(RedisCommand<Object?> command) {
  final output = BytesBuilder(copy: false)..add(ascii.encode('*${command.arguments.length}\r\n'));
  for (final argument in command.arguments) {
    final bytes = argument.bytes;
    output
      ..add(
        ascii.encode(
          r'$'
          '${bytes.length}\r\n',
        ),
      )
      ..add(bytes)
      ..add(const [13, 10]);
  }
  return output.takeBytes();
}
