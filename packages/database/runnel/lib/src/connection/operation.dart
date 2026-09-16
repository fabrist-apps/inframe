import 'dart:async';
import 'dart:io';

import 'package:conflux/effect.dart';
import 'package:conflux/option.dart';
import 'package:runnel/src/command.dart';
import 'package:runnel/src/errors.dart';

/// Owns cancellation hooks for one execution, never for a reusable Effect.
final class RunnelOperation {
  final List<FutureOr<void> Function()> _hooks = [];
  bool _cancelled = false;

  /// Whether this execution has received interruption.
  bool get isCancelled => _cancelled;

  /// Registers a hook and returns its removal function.
  void Function() onCancel(FutureOr<void> Function() hook) {
    if (_cancelled) throw StateError('Operation already cancelled.');
    _hooks.add(hook);
    return () => _hooks.remove(hook);
  }

  /// Stops all currently owned foreign waits.
  Future<void> cancel() async {
    _cancelled = true;
    final hooks = List<FutureOr<void> Function()>.of(_hooks);
    _hooks.clear();
    await Future.wait(hooks.map((hook) async => hook()));
  }

  /// Builds fresh adapter state for each Effect execution.
  static Effect<T, RunnelError> run<T>(Future<T> Function(RunnelOperation operation) work) =>
      Effect.defer((_) {
        final operation = RunnelOperation();
        return Effect.tryFuture(
          (_) => work(operation),
          onError: (error, stack, _) => expected(error, stack),
          onCancel: (_) => operation.cancel(),
        );
      });

  /// Maps only failures belonging to the socket adapter's known error family.
  static RunnelError expected(Object error, StackTrace stack) => switch (error) {
    CommandDecoderDefect() => Error.throwWithStackTrace(error.error, error.stackTrace),
    RunnelError() => error,
    SocketException() || HandshakeException() => RunnelTransportError(
      'Could not establish the Redis connection.',
      deliveryStatus: const Some(RedisDeliveryStatus.notSent),
      cause: error,
      stackTrace: stack,
    ),
    TimeoutException() => RunnelTimeoutError(
      'The Redis connection deadline expired.',
      deliveryStatus: const Some(RedisDeliveryStatus.notSent),
      cause: error,
      stackTrace: stack,
    ),
    _ => Error.throwWithStackTrace(error, stack),
  };

  /// Input validation runs before transmission, separate from callback execution.
  static T validate<T>(T Function() create) {
    try {
      return create();
    } on ArgumentError catch (error, stack) {
      throw RunnelInputError(
        'Invalid Runnel input: ${error.name ?? 'configuration'}.',
        stackTrace: stack,
      );
    } on FormatException catch (_, stack) {
      throw RunnelInputError('Invalid Runnel configuration.', stackTrace: stack);
    }
  }

  /// Adapts local release while preserving cleanup defects.
  static Effect<void, Never> release(Future<void> Function() close) => Effect.tryFuture(
    (_) => close(),
    onError: (error, stack, _) => Error.throwWithStackTrace(error, stack),
  );
}
