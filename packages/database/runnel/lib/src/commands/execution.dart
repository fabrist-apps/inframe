import 'package:conflux/effect.dart';
import 'package:runnel/src/client.dart';
import 'package:runnel/src/command.dart';
import 'package:runnel/src/connection/operation.dart';
import 'package:runnel/src/errors.dart';

/// Execution boundary for built-in commands whose arguments were already captured.
extension RunnelCommandExecution on Runnel {
  /// Validates the command only when run, then submits a fresh ordinary request.
  Effect<T, RunnelError> deferCommand<T>(
    RedisCommand<T> Function() create, {
    Duration? timeout,
  }) => Effect.defer((_) {
    try {
      return execute(RunnelOperation.validate(create), timeout: timeout);
    } on RunnelInputError catch (error) {
      return Effect.fail(error);
    }
  });
}
