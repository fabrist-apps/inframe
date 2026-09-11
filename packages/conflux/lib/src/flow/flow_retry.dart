import 'package:conflux/effect.dart';
import 'package:conflux/option.dart';
import 'package:conflux/schedule.dart';
import 'package:conflux/src/effect/effect.dart' show EffectAccess;
import 'package:conflux/src/effect/execution.dart' show EffectExecution;
import 'package:conflux/src/flow/protocol.dart';

/// Opens Flow cursors that resubscribe through a fresh Schedule driver.
abstract final class RetryFlowSource {
  /// Creates a cursor without opening its first source attempt.
  static Effect<FlowSourceCursor<A, E>, E> open<A, E, O>(
    OpenFlowCursor<A, E> upstream,
    Schedule<E, O, E> schedule,
  ) => Effect.succeed(_RetryCursor(upstream, schedule.driver()));
}

final class _RetryCursor<A, E, O> implements FlowSourceCursor<A, E> {
  _RetryCursor(this._upstream, this._driver);

  final OpenFlowCursor<A, E> _upstream;
  final ScheduleDriver<E, O, E> _driver;
  FlowSourceCursor<A, E>? _attempt;
  var _completed = false;

  @override
  Effect<Option<A>, E> next() => EffectAccess.create((execution) async {
    if (_completed) return const Succeeded(None());
    while (true) {
      var attempt = _attempt;
      if (attempt == null) {
        final opened = await EffectAccess.evaluate(Effect.defer(_upstream), execution);
        switch (opened) {
          case Succeeded<FlowSourceCursor<A, E>, E>(:final value):
            attempt = value;
            _attempt = value;
          case Failed<FlowSourceCursor<A, E>, E>(:final cause):
            final retry = await _retry(cause, execution);
            if (retry case Some<Exit<Option<A>, E>>(:final value)) return value;
            continue;
        }
      }

      final pulled = await EffectAccess.evaluate(attempt.next(), execution);
      switch (pulled) {
        case Succeeded<Option<A>, E>(value: None()):
          _completed = true;
          _attempt = null;
          return pulled;
        case Succeeded<Option<A>, E>(value: Some<A>()):
          return pulled;
        case Failed<Option<A>, E>(:final cause):
          _attempt = null;
          final retry = await _retry(cause, execution);
          if (retry case Some<Exit<Option<A>, E>>(:final value)) return value;
      }
    }
  });

  Future<Option<Exit<Option<A>, E>>> _retry(
    Cause<E> attemptCause,
    EffectExecution execution,
  ) async {
    final primary = attemptCause.primaryError;
    if (primary is! Some<E>) return Some(Failed(attemptCause));
    final stepped = await EffectAccess.evaluate(_driver.step(primary.value), execution);
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
