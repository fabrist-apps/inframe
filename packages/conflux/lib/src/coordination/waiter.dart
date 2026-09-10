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

  /// Waits for the owner's result and removes this registration on cancellation.
  Effect<A, Never> awaitValue({required void Function() onCancel}) {
    return Effect.tryFuture<Effect<A, Never>, Never>(
      () => _completion.future,
      onError: Error.throwWithStackTrace,
      onCancel: () {
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
