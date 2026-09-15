import 'package:conflux/effect.dart';
import 'package:conflux/option.dart';
import 'package:conflux/schedule.dart';
import 'package:conflux/src/effect/effect.dart' show EffectAccess;
import 'package:conflux/src/effect/execution.dart' show EffectExecution;
import 'package:conflux/src/flow/flow.dart' show FlowCursor;
import 'package:conflux/src/flow/protocol.dart';

/// Opens Flow cursors that resubscribe through a fresh Schedule step.
abstract final class RetryFlowSource {
  /// Creates a cursor without opening its first source attempt.
  static Effect<FlowSourceCursor<A, E>, E> open<A, E, O>(
    Effect<FlowCursor<A, E>, E> Function() upstream,
    Schedule<E, O, E> schedule,
  ) => Effect.defer((_) => Effect.succeed(_RetryCursor(upstream, schedule.createStep())));
}

final class _RetryCursor<A, E, O> implements FlowSourceCursor<A, E> {
  _RetryCursor(this._upstream, this._step);

  final Effect<FlowCursor<A, E>, E> Function() _upstream;
  final ScheduleStep<E, O, E> _step;
  FlowCursor<A, E>? _attempt;
  var _completed = false;

  @override
  Effect<Option<A>, E> next() => EffectAccess.create((execution) async {
    if (_completed) return const Succeeded(None());
    while (true) {
      var attempt = _attempt;
      if (attempt == null) {
        final opened = await EffectAccess.evaluate(Effect.defer((_) => _upstream()), execution);
        switch (opened) {
          case Succeeded<FlowCursor<A, E>, E>(:final value):
            attempt = value;
            _attempt = value;
          case Failed<FlowCursor<A, E>, E>(:final cause):
            final retry = await _retry(cause, execution);
            if (retry case Some<Exit<Option<A>, E>>(:final value)) return value;
            continue;
        }
      }

      final pulled = await EffectAccess.evaluate(attempt.next(), execution);
      if (pulled case Succeeded<Option<A>, E>(value: Some<A>())) return pulled;

      _attempt = null;
      // A managed cursor finishes its cleanup before returning a terminal pull.
      switch (pulled) {
        case Succeeded<Option<A>, E>(value: None()):
          _completed = true;
          return pulled;
        case Failed<Option<A>, E>(:final cause):
          final retry = await _retry(cause, execution);
          if (retry case Some<Exit<Option<A>, E>>(:final value)) return value;
        case Succeeded<Option<A>, E>(value: Some<A>()):
          throw StateError('A retry attempt closed after emitting a value.');
      }
    }
  });

  Future<Option<Exit<Option<A>, E>>> _retry(
    Cause<E> attemptCause,
    EffectExecution execution,
  ) async {
    final primary = attemptCause.primaryError;
    if (primary is! Some<E>) return Some(Failed(attemptCause));
    final stepped = await EffectAccess.evaluate(_step(primary.value), execution);
    switch (stepped) {
      case Failed<ScheduleDecision<O>, E>(:final cause):
        return Some(Failed(cause));
      case Succeeded<ScheduleDecision<O>, E>(value: ScheduleStop<O>()):
        return Some(Failed(attemptCause));
      case Succeeded<ScheduleDecision<O>, E>(
        value: ScheduleContinue<O>(:final delay),
      ):
        final waited = await EffectAccess.evaluate(Effect.sleep(delay), execution);
        return switch (waited) {
          Succeeded<void, Never>() => const None(),
          Failed<void, Never>(:final cause) => Some(
            Failed(cause.mapExpected<E>(_widenNever)),
          ),
        };
    }
  }
}

E _widenNever<E>(Never error) => error;
