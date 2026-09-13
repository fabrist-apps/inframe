import 'dart:async';

import 'package:conflux/effect.dart';

/// One cancellable wait owned by a coordination state machine.
///
/// The owner removes a cancelled waiter synchronously. Committing a value marks
/// the waiter settled before completing its Future, so later cancellation
/// cannot undo the state transition that produced the value.
final class CoordinationWaiter<A> {
  final Completer<Effect<A, Never>> _completion = Completer();
  var _settled = false;

  /// Starts the owner's registration, then waits for its result cancellably.
  ///
  /// [onStart] runs inside the foreign-Future adapter, before its cancellation
  /// check. This ensures cancellation either prevents registration or invokes
  /// [onCancel] to remove it.
  Effect<A, Never> awaitValue({
    required void Function() onStart,
    required void Function() onCancel,
  }) {
    return Effect.tryFuture<Effect<A, Never>, Never>(
      (_) {
        onStart();
        return _completion.future;
      },
      onError: (error, stackTrace, _) => Error.throwWithStackTrace(error, stackTrace),
      onCancel: (_) {
        if (_settled) return;
        _settled = true;
        onCancel();
      },
    ).flatten();
  }

  /// Commits [value] if this waiter has not been cancelled or settled.
  void succeed(A value) => _complete(Effect.succeed(value));

  /// Interrupts the wait with [reason] if it has not already settled.
  void interrupt(Object reason) => _complete(
    Effect.failCause(Interrupted(reason)),
  );

  void _complete(Effect<A, Never> result) {
    if (_settled) return;
    _settled = true;
    _completion.complete(result);
  }
}
