import 'package:conflux/effect.dart';
import 'package:conflux/option.dart';

/// Lazily opens the internal cursor for one Flow source or operator.
typedef OpenFlowCursor<A, E> = Effect<FlowSourceCursor<A, E>, E> Function();

/// The internal pull boundary shared by Flow sources and operators.
///
/// A cursor returns [Some] for a value, including `null`, and [None] for normal
/// completion. The managed public cursor enforces single-pull and scope rules.
// ignore: one_member_abstracts
abstract interface class FlowSourceCursor<A, E> {
  /// Pulls one value or terminal completion.
  Effect<Option<A>, E> next();
}

/// Opens and sequentially consumes one internal Flow cursor.
Effect<void, E> pumpFlow<A, E>(
  OpenFlowCursor<A, E> open,
  Effect<void, E> Function(A value) emit,
) => Effect.build((resolve) async {
  final cursor = await resolve(Effect.defer(open));
  while (true) {
    switch (await resolve(cursor.next())) {
      case Some<A>(:final value):
        await resolve(Effect.defer(() => emit(value)));
      case None():
        return;
    }
  }
});
