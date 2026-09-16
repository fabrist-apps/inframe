import 'dart:typed_data';

import 'package:runnel/src/client.dart';
import 'package:runnel/src/command.dart';
import 'package:runnel/src/resp/resp_value.dart';

export 'pubsub/events.dart'
    show
        PubSubEvent,
        PubSubInterrupted,
        PubSubInterruptionCause,
        PubSubMessage,
        PubSubRestored,
        PubSubState,
        SubscriptionSupersededException;
export 'pubsub/session.dart';

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
  Future<int> publish(String channel, String message, {Duration? timeout}) =>
      execute(publishCommand(channel, message), timeout: timeout);

  /// Publishes exact bytes and returns the broker subscriber count.
  ///
  /// The count is not an end-client delivery acknowledgement or persistence proof.
  Future<int> publishBytes(String channel, Uint8List message, {Duration? timeout}) =>
      execute(publishBytesCommand(channel, message), timeout: timeout);
}

RedisCommand<int> _publishCommand(String channel, RedisArgument message) {
  if (channel.isEmpty) throw ArgumentError.value(channel, 'channel', 'must not be empty');
  return RedisCommand<int>(
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
