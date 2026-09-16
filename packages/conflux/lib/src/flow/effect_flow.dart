import 'package:conflux/effect.dart';
import 'package:conflux/src/flow/flow.dart';

/// Conversion from a lazy Effect to a single-value Flow.
extension EffectFlow<A, E> on Effect<A, E> {
  /// Emits the Effect value once, or terminates with its complete failure.
  Flow<A, E> asFlow() => FlowAccess.fromEffect(this);
}
