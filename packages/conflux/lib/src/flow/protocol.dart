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
