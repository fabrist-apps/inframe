import 'package:chronicler/chronicler.dart';
import 'package:conflux/effect.dart';

/// Runs Effects inside SDK-owned Chronicler span lifetimes.
extension ChroniclerEffectTracing<A, E> on Effect<A, E> {
  /// Runs this Effect in a child span, or a root when no parent is active.
  Effect<A, E> withSpan(
    String name, {
    SpanKind kind = SpanKind.internal,
    Map<String, Object?> attributes = const {},
  }) => _withChroniclerSpan(
    name,
    kind: kind,
    attributes: attributes,
    forceRoot: false,
    parent: null,
  );

  /// Runs this Effect in an explicit root boundary, optionally continuing [parent].
  Effect<A, E> withRootSpan(
    String name, {
    RemoteTraceParent? parent,
    SpanKind kind = SpanKind.internal,
    Map<String, Object?> attributes = const {},
  }) => _withChroniclerSpan(
    name,
    kind: kind,
    attributes: attributes,
    forceRoot: true,
    parent: parent,
  );

  Effect<A, E> _withChroniclerSpan(
    String name, {
    required SpanKind kind,
    required Map<String, Object?> attributes,
    required bool forceRoot,
    required RemoteTraceParent? parent,
  }) => Effect.defer((_) {
    ChroniclerSpan? span;
    final operation = Effect.build<A, E>(($) {
      final context = $.context;
      final acquired = forceRoot
          ? context.tracing.startRootSpan(
              name,
              parent: parent,
              kind: kind,
              attributes: attributes,
            )
          : context.tracing.startSpan(
              name,
              kind: kind,
              attributes: attributes,
            );
      span = acquired;
      final traced = context.withChronicler(acquired.recorder);
      return $(Effect.using(withContext(traced)));
    });
    return operation.onExit((exit, _) {
      return Effect.sync((_) => span?.end(_statusFor(exit)));
    });
  });
}

SpanStatus _statusFor<A, E>(Exit<A, E> exit) => switch (exit) {
  Succeeded<A, E>() => SpanStatus.success,
  Failed<A, E>(:final cause) =>
    _isInterruptionOnly(cause) ? SpanStatus.cancelled : SpanStatus.error,
};

bool _isInterruptionOnly<E>(Cause<E> cause) {
  final pending = <Cause<E>>[cause];
  while (pending.isNotEmpty) {
    final current = pending.removeLast();
    switch (current) {
      case Interrupted<E>():
        break;
      case Sequential<E>(:final causes) || Parallel<E>(:final causes):
        pending.addAll(causes);
      case Expected<E>() || Defect<E>():
        return false;
    }
  }
  return true;
}
