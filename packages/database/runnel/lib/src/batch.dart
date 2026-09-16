import 'dart:async';

import 'package:conflux/effect.dart';
import 'package:conflux/result.dart';
import 'package:runnel/src/command.dart';
import 'package:runnel/src/command_validation.dart';
import 'package:runnel/src/connection/operation.dart';
import 'package:runnel/src/errors.dart';

/// A typed reference to one entry in a batch.
final class BatchRef<T> {
  BatchRef._(this._owner, this._index);
  final Object _owner;
  final int _index;
}

/// Immutable heterogeneous results from one batch execution.
final class BatchResults {
  BatchResults._(this._owner, this._outcomes);
  final Object _owner;
  final List<Result<Object?, RunnelError>> _outcomes;

  /// Retrieves the exact entry type, preserving nullable values and nested Options.
  ///
  /// References from another batch are programmer errors. Bind a Result through
  /// `$.sync(results.outcome(reference))` to propagate its expected failure.
  Result<T, RunnelError> outcome<T>(BatchRef<T> reference) {
    if (!identical(reference._owner, _owner)) {
      throw ArgumentError.value(reference, 'reference', 'belongs to another batch');
    }
    return _outcomes[reference._index].map((value) => value as T);
  }
}

/// Builds a single-use typed pipeline or transaction without performing I/O.
final class RedisBatch {
  /// Internal composition boundary for Runnel's transport executors.
  RedisBatch.internal({
    required this._maxCommands,
    required this._maxBytes,
    required this._reservedCommands,
    required int reservedBytes,
    required this._defaultTimeout,
    required this._executor,
  }) : _encodedBytes = reservedBytes;

  final int _maxCommands;
  final int _maxBytes;
  final int _reservedCommands;
  final Duration _defaultTimeout;
  final Future<List<Result<Object?, RunnelError>>> Function(
    List<RedisCommand<Object?>> commands,
    Duration timeout,
    RunnelOperation operation,
  )
  _executor;
  final Object _owner = Object();
  final List<RedisCommand<Object?>> _commands = [];
  int _encodedBytes;
  bool _frozen = false;
  bool _claimed = false;

  /// Adds a command until [exec] freezes this builder; invalid builder usage throws.
  BatchRef<T> add<T>(RedisCommand<T> command) {
    if (_frozen) throw StateError('This batch is frozen.');
    validateOrdinaryCommand(command as RedisCommand<Object?>);
    final encodedBytes = command.encodedLength;
    if (_commands.length + _reservedCommands >= _maxCommands) {
      throw StateError('The batch would exceed the configured command limit.');
    }
    if (_encodedBytes + encodedBytes > _maxBytes) {
      throw StateError('The batch would exceed the configured encoded-byte limit.');
    }
    final reference = BatchRef<T>._(_owner, _commands.length);
    _commands.add(command);
    _encodedBytes += encodedBytes;
    return reference;
  }

  /// Freezes now and claims the batch only when the returned Effect starts.
  ///
  /// Once claimed, failure or interruption never makes a batch reusable.
  Effect<BatchResults, RunnelError> exec({Duration? timeout}) {
    _frozen = true;
    final commands = List<RedisCommand<Object?>>.unmodifiable(_commands);
    final duration = timeout ?? _defaultTimeout;
    return RunnelOperation.run((operation) async {
      if (_claimed) throw const RunnelUsageError('This batch has already executed.');
      _claimed = true;
      if (commands.isEmpty)
        throw const RunnelUsageError('A batch must contain at least one command.');
      if (duration <= Duration.zero)
        throw const RunnelInputError('Batch timeout must be positive.');
      final results = await _executor(commands, duration, operation);
      return BatchResults._(_owner, List.unmodifiable(results));
    });
  }
}

/// Observes every accepted request, retaining expected errors as entry Results.
///
/// Unexpected decoder throws fail the outer operation after observing the other
/// requests. This is an internal transport boundary, not a public Result type.
Future<List<Result<Object?, RunnelError>>> settleBatch(List<Future<Object?>> futures) =>
    Future.wait(
      futures.map((future) async {
        try {
          return Success<Object?, RunnelError>(await future);
        } on Object catch (error, stack) {
          if (error is CommandDecoderDefect) rethrow;
          return Failure<Object?, RunnelError>(RunnelOperation.expected(error, stack));
        }
      }),
    );
