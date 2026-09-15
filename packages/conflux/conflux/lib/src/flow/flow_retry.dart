import 'package:conflux/effect.dart';
import 'package:conflux/option.dart';
import 'package:conflux/schedule.dart';
import 'package:conflux/src/effect/effect.dart' show EffectAccess;
import 'package:conflux/src/effect/execution.dart'
    show EffectCancellation, EffectExecution, ScopeAccess;
import 'package:conflux/src/effect/exit.dart' show ExitRuntimeOperations;
import 'package:conflux/src/flow/protocol.dart';

/// Opens Flow cursors that resubscribe through a fresh Schedule driver.
abstract final class RetryFlowSource {
  /// Creates a cursor without opening its first source attempt.
  static Effect<FlowSourceCursor<A, E>, E> open<A, E, O>(
    OpenFlowCursor<A, E> upstream,
    Schedule<E, O, E> schedule,
  ) => EffectAccess.create((execution) async {
    final cursor = _RetryCursor(upstream, schedule.createStep());
    final registered = ScopeAccess.addFinalizer(
      execution.scope,
      cursor.close(),
      execution.context,
      execution.clock,
    );
    if (registered) return Succeeded(cursor);
    return const Failed(Interrupted(ScopeClosed()));
  });
}

final class _RetryCursor<A, E, O> implements FlowSourceCursor<A, E> {
  _RetryCursor(this._upstream, this._driver);

  final OpenFlowCursor<A, E> _upstream;
  final ScheduleStep<E, O, E> _driver;
  _RetryAttempt<A, E>? _attempt;
  var _completed = false;

  @override
  Effect<Option<A>, E> next() => EffectAccess.create((execution) async {
    if (_completed) return const Succeeded(None());
    while (true) {
      var attempt = _attempt;
      if (attempt == null) {
        final opened = await _RetryAttempt.open(_upstream, execution);
        switch (opened) {
          case Succeeded<_RetryAttempt<A, E>, E>(:final value):
            attempt = value;
            _attempt = value;
          case Failed<_RetryAttempt<A, E>, E>(:final cause):
            final retry = await _retry(cause, execution);
            if (retry case Some<Exit<Option<A>, E>>(:final value)) return value;
            continue;
        }
      }

      final pulled = await attempt.pull();
      if (pulled case Succeeded<Option<A>, E>(value: Some<A>())) return pulled;

      _attempt = null;
      final terminal = pulled.appendCleanup(await attempt.close(interrupt: false));
      switch (terminal) {
        case Succeeded<Option<A>, E>(value: None()):
          _completed = true;
          return terminal;
        case Failed<Option<A>, E>(:final cause):
          final retry = await _retry(cause, execution);
          if (retry case Some<Exit<Option<A>, E>>(:final value)) return value;
        case Succeeded<Option<A>, E>(value: Some<A>()):
          throw StateError('A retry attempt closed after emitting a value.');
      }
    }
  });

  Effect<void, Never> close() => EffectAccess.create((_) async {
    final attempt = _attempt;
    _attempt = null;
    if (attempt == null) return const Succeeded(null);
    final cleanup = await attempt.close(interrupt: true);
    return cleanup == null ? const Succeeded(null) : Failed(cleanup);
  });

  Future<Option<Exit<Option<A>, E>>> _retry(
    Cause<E> attemptCause,
    EffectExecution execution,
  ) async {
    final primary = attemptCause.primaryError;
    if (primary is! Some<E>) return Some(Failed(attemptCause));
    final stepped = await EffectAccess.evaluate(_driver(primary.value), execution);
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

final class _RetryAttempt<A, E> {
  _RetryAttempt(
    this._cursor,
    this._execution,
    this._cancellation,
    this._stopParentCancellation,
  );

  final FlowSourceCursor<A, E> _cursor;
  final EffectExecution _execution;
  final EffectCancellation _cancellation;
  final void Function() _stopParentCancellation;
  Future<Cause<Never>?>? _closing;

  static Future<Exit<_RetryAttempt<A, E>, E>> open<A, E>(
    OpenFlowCursor<A, E> upstream,
    EffectExecution parent,
  ) async {
    final cancellation = EffectCancellation();
    final stopParentCancellation = parent.cancellation.listen(
      cancellation.cancel,
    );
    final execution = EffectExecution(
      context: parent.context,
      scope: ScopeAccess.create(),
      clock: parent.clock,
      cancellation: cancellation,
    );
    final opened = await EffectAccess.evaluate(Effect.defer((_) => upstream()), execution);
    return switch (opened) {
      Succeeded<FlowSourceCursor<A, E>, E>(:final value) => Succeeded(
        _RetryAttempt(value, execution, cancellation, stopParentCancellation),
      ),
      Failed<FlowSourceCursor<A, E>, E>(:final cause) => () async {
        stopParentCancellation();
        return Failed<_RetryAttempt<A, E>, E>(
          cause,
        ).appendCleanup(await execution.scope.close());
      }(),
    };
  }

  Future<Exit<Option<A>, E>> pull() => EffectAccess.evaluate(
    _cursor.next(),
    _execution,
  );

  Future<Cause<Never>?> close({required bool interrupt}) {
    final active = _closing;
    if (active != null) return active;
    final closing = _close(interrupt);
    _closing = closing;
    return closing;
  }

  Future<Cause<Never>?> _close(bool interrupt) async {
    _stopParentCancellation();
    if (interrupt) _cancellation.cancel(const _RetryAttemptClosed());
    return _execution.scope.close();
  }
}

final class _RetryAttemptClosed {
  const _RetryAttemptClosed();

  @override
  String toString() => 'Flow retry attempt closed';
}

E _widenNever<E>(Never error) => error;
