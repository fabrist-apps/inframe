import 'dart:typed_data';

import 'package:conflux/effect.dart';
import 'package:runnel/src/client.dart';
import 'package:runnel/src/command.dart';
import 'package:runnel/src/commands/execution.dart';
import 'package:runnel/src/errors.dart';
import 'package:runnel/src/resp/resp_value.dart';

export 'pubsub/events.dart'
    show
        PubSubEvent,
        PubSubInterrupted,
        PubSubInterruptionCause,
        PubSubMessage,
        PubSubRestored,
        PubSubState;
export 'pubsub/session.dart' show PubSubConnectionConfiguration, PubSubLimits, PubSubSession;

/// Builds a PUBLISH command whose result is Redis's broker subscriber count.
RedisCommand<int> publishCommand(String channel, String message) =>
    _publishCommand(channel, RedisArgument.text(message));

/// Builds a binary PUBLISH command and snapshots [message].
RedisCommand<int> publishBytesCommand(String channel, Uint8List message) =>
    _publishCommand(channel, RedisArgument.bytes(message));

/// Publishing conveniences for [Runnel].
extension RunnelPublishingCommands on Runnel {
  /// Publishes text and returns the broker subscriber count.
  ///
  /// The count is not an end-client delivery acknowledgement or persistence proof.
  Effect<int, RunnelError> publish(String channel, String message, {Duration? timeout}) =>
      deferCommand(() => publishCommand(channel, message), timeout: timeout);

  /// Publishes exact bytes and returns the broker subscriber count.
  ///
  /// The count is not an end-client delivery acknowledgement or persistence proof.
  Effect<int, RunnelError> publishBytes(String channel, Uint8List message, {Duration? timeout}) {
    final captured = Uint8List.fromList(message);
    return deferCommand(() => publishBytesCommand(channel, captured), timeout: timeout);
  }
}

RedisCommand<int> _publishCommand(String channel, RedisArgument message) {
  if (channel.isEmpty) throw ArgumentError.value(channel, 'channel', 'must not be empty');
  return builtInCommand<int>(
    [
      RedisArgument.text('PUBLISH'),
      RedisArgument.text(channel),
      message,
    ],
    (reply) => switch (reply) {
      RespInteger(:final value) => value,
      _ => throw FormatException(
        'Expected an integer PUBLISH reply, received ${reply.runtimeType}.',
      ),
    },
  );
}
