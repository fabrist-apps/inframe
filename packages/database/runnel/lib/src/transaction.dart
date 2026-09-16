import 'dart:async';

import 'package:conflux/option.dart';
import 'package:conflux/result.dart';
import 'package:runnel/src/batch.dart';
import 'package:runnel/src/command.dart';
import 'package:runnel/src/connection/redis_connection.dart';
import 'package:runnel/src/deadline.dart';
import 'package:runnel/src/errors.dart';
import 'package:runnel/src/resp/resp_value.dart';

/// Executes MULTI/EXEC on the dedicated connection owned by the client.
///
/// The client registers this connection for shutdown and releases it after execution.
Future<List<Result<Object?, RunnelError>>> executeTransaction(
  RedisConnection connection,
  List<RedisCommand<Object?>> commands,
  ConnectionDeadline deadline,
) async {
  final wireCommands = <RedisCommand<Object?>>[
    transactionFrame('MULTI'),
    for (final command in commands) _queuedCommand(command),
    transactionFrame('EXEC'),
  ];
  final replies = await settleBatch(
    connection.executeBatch(wireCommands, timeout: deadline.remaining),
  );
  _requireTransactionSuccess(replies.first, 'MULTI was rejected.');
  for (var index = 0; index < commands.length; index++) {
    _requireTransactionSuccess(replies[index + 1], 'A transaction command was rejected.');
  }
  final execReply = _requireTransactionSuccess(replies.last, 'EXEC was rejected.');
  if (execReply is RespNull) {
    throw RunnelTransactionError(
      'EXEC did not commit the transaction.',
      stackTrace: StackTrace.current,
    );
  }
  if (execReply is! RespArray || execReply.values.length != commands.length) {
    throw RunnelProtocolError(
      'EXEC returned an invalid result array.',
      deliveryStatus: const Some(RedisDeliveryStatus.outcomeUnknown),
      stackTrace: StackTrace.current,
    );
  }
  final results = List.generate(commands.length, (index) {
    _requireTransactionDeadline(deadline);
    final reply = execReply.values[index];
    if (reply case RespError(:final code, :final message)) {
      return Failure<Object?, RunnelError>(
        RunnelServerError(message, code: code, cause: reply, stackTrace: StackTrace.current),
      );
    }
    _requireTransactionDeadline(deadline);
    final result = commands[index].decode(reply);
    _requireTransactionDeadline(deadline);
    return result;
  }, growable: false);
  _requireTransactionDeadline(deadline);
  return results;
}

/// Constructs a transaction framing command without interpreting its reply.
RedisCommand<Object?> transactionFrame(String name) => builtInCommand<Object?>(
  [RedisArgument.text(name)],
  (reply) => reply,
);

RedisCommand<Object?> _queuedCommand(RedisCommand<Object?> command) => builtInCommand<Object?>(
  command.arguments,
  (reply) => reply,
);

Object? _requireTransactionSuccess(Result<Object?, RunnelError> outcome, String message) {
  return switch (outcome) {
    Success(:final value) => value,
    Failure(:final error) => throw switch (error) {
      RunnelServerError() => RunnelTransactionError(message, cause: error),
      _ => error,
    },
  };
}

void _requireTransactionDeadline(ConnectionDeadline deadline) {
  try {
    deadline.remaining;
  } on TimeoutException catch (error, stackTrace) {
    throw RunnelTimeoutError(
      'The Redis transaction deadline expired during reply decoding.',
      deliveryStatus: const Some(RedisDeliveryStatus.outcomeUnknown),
      cause: error,
      stackTrace: stackTrace,
    );
  }
}
