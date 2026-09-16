import 'dart:convert';
import 'dart:typed_data';

import 'package:conflux/result.dart';
import 'package:runnel/src/errors.dart';
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
  RedisCommand(
    List<RedisArgument> arguments,
    Result<T, RunnelError> Function(RespValue reply) decode,
  ) : arguments = List.unmodifiable(arguments),
      _decode = decode {
    if (arguments.isEmpty) throw ArgumentError.value(arguments, 'arguments', 'must not be empty');
  }

  /// Internal built-in decoder boundary: reply-shape and UTF-8 errors are expected.
  RedisCommand.internal(List<RedisArgument> arguments, T Function(RespValue reply) decode)
    : this(arguments, (reply) {
        try {
          return Success(decode(reply));
        } on FormatException catch (error, stack) {
          return Failure(RunnelDecodingError(error.message, cause: error, stackTrace: stack));
        }
      });

  /// Immutable command arguments, including the command name.
  final List<RedisArgument> arguments;
  final Result<T, RunnelError> Function(RespValue reply) _decode;

  /// Converts one non-error reply into the command result.
  Result<T, RunnelError> decode(RespValue reply) {
    try {
      return _decode(reply);
    } on Object catch (error, stack) {
      throw CommandDecoderDefect(error, stack);
    }
  }

  /// Exact RESP wire size without allocating the encoded command.
  int get encodedLength {
    var length = 1 + '${arguments.length}'.length + 2;
    for (final argument in arguments) {
      final byteLength = argument._bytes.length;
      // Bulk header ($length\r\n), payload, and trailing CRLF.
      length += 1 + '$byteLength'.length + 2 + byteLength + 2;
    }
    return length;
  }
}

/// Encodes a command as one RESP array of bulk-string arguments.
Uint8List encodeCommand(RedisCommand<Object?> command) {
  final output = BytesBuilder(copy: false)..add(ascii.encode('*${command.arguments.length}\r\n'));
  for (final argument in command.arguments) {
    final bytes = argument._bytes;
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

/// Internal distinction between returned expected failures and thrown callbacks.
final class CommandDecoderDefect {
  /// Retains the original callback error and stack without classifying it as expected.
  const CommandDecoderDefect(this.error, this.stackTrace);

  /// The object thrown by the callback.
  final Object error;

  /// The callback stack, before crossing the Future boundary.
  final StackTrace stackTrace;
}
