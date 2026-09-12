// Public construction is named for package-internal collaborators, so initializing
// formals would expose private parameter names across Dart libraries.
// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:runnel/src/command.dart';
import 'package:runnel/src/command_validation.dart';

/// A typed reference to one entry in a batch.
final class BatchRef<T> {
  BatchRef._(this._owner, this._index);

  final Object _owner;
  final int _index;
}

/// The settled outcome of one batch entry.
sealed class BatchOutcome<T> {
  const BatchOutcome();
}

/// A successfully decoded batch entry.
final class BatchSuccess<T> extends BatchOutcome<T> {
  /// Creates a successful outcome.
  const BatchSuccess(this.value);

  /// The decoded command value.
  final T value;
}

/// A failed batch entry.
final class BatchFailure<T> extends BatchOutcome<T> {
  /// Creates a failed outcome.
  const BatchFailure(this.error, this.stackTrace);

  /// The command-specific error.
  final Object error;

  /// The stack trace captured when the command failed.
  final StackTrace stackTrace;
}

/// Immutable heterogeneous results from one batch execution.
final class BatchResults {
  BatchResults._(this._owner, this._outcomes);

  final Object _owner;
  final List<BatchOutcome<Object?>> _outcomes;

  /// Returns an entry's decoded value or throws that entry's error.
  T value<T>(BatchRef<T> reference) {
    return switch (outcome(reference)) {
      BatchSuccess<T>(:final value) => value,
      BatchFailure<T>(:final error, :final stackTrace) => Error.throwWithStackTrace(
        error,
        stackTrace,
      ),
    };
  }

  /// Returns an entry's success or failure without throwing its individual error.
  BatchOutcome<T> outcome<T>(BatchRef<T> reference) {
    if (!identical(reference._owner, _owner)) {
      throw ArgumentError.value(reference, 'reference', 'belongs to another batch');
    }
    return switch (_outcomes[reference._index]) {
      BatchSuccess<Object?>(:final value) => BatchSuccess<T>(value as T),
      BatchFailure<Object?>(:final error, :final stackTrace) => BatchFailure<T>(error, stackTrace),
    };
  }
}

/// Builds a single-use typed pipeline or transaction without performing I/O.
final class RedisBatch {
  /// Creates a builder for Runnel's internal pipeline or transaction executor.
  RedisBatch.internal({
    required int maxCommands,
    required int maxBytes,
    required int reservedCommands,
    required int reservedBytes,
    required Duration defaultTimeout,
    required Future<List<BatchOutcome<Object?>>> Function(
      List<RedisCommand<Object?>> commands,
      Duration timeout,
    )
    executor,
  }) : _maxCommands = maxCommands,
       _maxBytes = maxBytes,
       _reservedCommands = reservedCommands,
       _encodedBytes = reservedBytes,
       _defaultTimeout = defaultTimeout,
       _executor = executor;

  final int _maxCommands;
  final int _maxBytes;
  final int _reservedCommands;
  final Duration _defaultTimeout;
  final Future<List<BatchOutcome<Object?>>> Function(
    List<RedisCommand<Object?>> commands,
    Duration timeout,
  )
  _executor;
  final Object _owner = Object();
  final List<RedisCommand<Object?>> _commands = [];
  int _encodedBytes;
  bool _executed = false;

  /// Adds one command and returns a reference for retrieving its typed result.
  BatchRef<T> add<T>(RedisCommand<T> command) {
    if (_executed) throw StateError('This batch has already executed.');
    validateOrdinaryCommand(command as RedisCommand<Object?>);
    final encodedBytes = encodeCommand(command).length;
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

  /// Executes all entries exactly once and preserves every individual outcome.
  Future<BatchResults> exec({Duration? timeout}) async {
    if (_executed) throw StateError('This batch has already executed.');
    _executed = true;
    if (_commands.isEmpty) throw StateError('A batch must contain at least one command.');
    final deadline = timeout ?? _defaultTimeout;
    if (deadline <= Duration.zero) {
      throw ArgumentError.value(deadline, 'timeout', 'must be positive');
    }
    final outcomes = await _executor(List.unmodifiable(_commands), deadline);
    return BatchResults._(_owner, List.unmodifiable(outcomes));
  }
}

/// Settles every command Future without losing individual failures.
Future<List<BatchOutcome<Object?>>> settleBatch(List<Future<Object?>> futures) async {
  return Future.wait(
    futures.map((future) async {
      try {
        return BatchSuccess<Object?>(await future);
      } on Object catch (error, stackTrace) {
        return BatchFailure<Object?>(error, stackTrace);
      }
    }),
  );
}
