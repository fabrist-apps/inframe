import 'dart:async';

import 'package:conflux/effect.dart';
import 'package:conflux/option.dart';
import 'package:conflux/pubsub.dart';
import 'package:conflux/queue.dart';
import 'package:conflux/schedule.dart';
import 'package:conflux/src/effect/cause.dart' show CauseGroup;
import 'package:conflux/src/effect/effect.dart' show EffectAccess;
import 'package:conflux/src/effect/execution.dart'
    show EffectCancellation, EffectExecution, ScopeAccess, ScopeClosed;
import 'package:conflux/src/effect/exit.dart' show ExitRuntimeOperations;
import 'package:conflux/src/flow/batching.dart';
import 'package:conflux/src/flow/combination.dart';
import 'package:conflux/src/flow/concurrent.dart';
import 'package:conflux/src/flow/coordination_adapter.dart';
import 'package:conflux/src/flow/flow_buffer.dart';
import 'package:conflux/src/flow/flow_retry.dart';
import 'package:conflux/src/flow/flow_scheduling.dart';
import 'package:conflux/src/flow/protocol.dart';
import 'package:conflux/src/flow/sharing.dart';
import 'package:conflux/src/flow/stream_adapter.dart';
import 'package:conflux/src/validation.dart';
import 'package:context/context.dart';

E _widenNever<E>(Never error) => error;

/// A lazy, reusable description of a typed sequence.
///
/// Constructing a Flow starts no work. Each [open], runner, or subscription
/// creates independent cursor state and a child resource scope.
final class Flow<A, E> {
  const Flow._(this._openCursor);

  final OpenFlowCursor<A, E> _openCursor;

  /// Creates a Flow that completes without emitting a value.
  static Flow<A, E> empty<A, E>() => Flow._(
    () => Effect.succeed(_CallbackCursor<A, E>(() => Effect.succeed(const None()))),
  );

  /// Creates a Flow that emits [value] once, including when it is `null`.
  static Flow<A, E> succeed<A, E>(A value) => Flow._(
    () => Effect.succeed(_ValueCursor<A, E>(value)),
  );

  /// Creates a Flow that terminates with expected [error].
  static Flow<A, E> fail<A, E>(E error) => Flow._(
    () => Effect.succeed(_CallbackCursor<A, E>(() => Effect.fail(error))),
  );

  /// Creates a cold Flow whose iterator is acquired for each consumption.
  static Flow<A, Never> fromIterable<A>(Iterable<A> values) => Flow._(
    () => Effect.defer(
      (_) => Effect.succeed(_IteratorCursor<A, Never>(values.iterator)),
    ),
  );

  /// Lazily chooses a Flow for each consumption.
  ///
  /// The factory runs inside the consumption boundary. A thrown object becomes
  /// a defect with its original stack trace.
  static Flow<A, E> defer<A, E>(Flow<A, E> Function(Context context) factory) => Flow._(
    () => Effect.defer((context) => factory(context).open()),
  );

  /// Consumes [queue] as a shared competing source.
  ///
  /// Each accepted item reaches one Queue consumer. Flow cleanup removes its
  /// pending take but never shuts down the externally owned Queue. Queue
  /// shutdown becomes normal Flow completion; other interruptions remain fatal.
  static Flow<A, Never> fromQueue<A>(Queue<A> queue) => Flow._(
    () => CoordinationFlowSource.openQueue(queue),
  );

  /// Consumes [pubsub] through one subscription per Flow consumption.
  ///
  /// The Flow scope owns and releases its subscription without shutting down the
  /// externally owned PubSub. PubSub or subscription shutdown becomes normal
  /// Flow completion; other interruptions remain fatal.
  static Flow<A, Never> fromPubSub<A>(PubSub<A> pubsub) => Flow._(
    () => CoordinationFlowSource.openPubSub(pubsub),
  );

  /// Adapts a Stream factory through a bounded Flow-owned buffer.
  ///
  /// Each consumption invokes [source] and subscribes once. Stream errors pass
  /// through [onError]. [capacity] must be positive, and [onOverflow] is
  /// required when [overflow] is [FlowOverflowPolicy.fail]. Backpressure pauses
  /// this subscription but cannot bound buffering internal to a broadcast source.
  static Flow<A, E> fromStream<A, E>(
    Stream<A> Function(Context context) source, {
    required E Function(Object error, StackTrace stackTrace, Context context) onError,
    int capacity = 16,
    FlowOverflowPolicy overflow = FlowOverflowPolicy.backpressure,
    E Function(FlowBufferOverflow overflow, Context context)? onOverflow,
  }) {
    FlowMailbox.validateBuffer(capacity, overflow, onOverflow);
    return Flow._(
      () => StreamFlowSource.open(
        source,
        onError: onError,
        capacity: capacity,
        overflow: overflow,
        onOverflow: onOverflow,
      ),
    );
  }

  /// Concurrently merges [sources] as their values become available.
  ///
  /// [capacity] bounds the shared output buffer. Backpressure waits for the
  /// consumer by default; the other [overflow] policies match [fromStream].
  static Flow<A, E> merge<A, E>(
    Iterable<Flow<A, E>> sources, {
    int capacity = 16,
    FlowOverflowPolicy overflow = FlowOverflowPolicy.backpressure,
    E Function(FlowBufferOverflow overflow, Context context)? onOverflow,
  }) {
    FlowMailbox.validateBuffer(capacity, overflow, onOverflow);
    return Flow._(
      () => ConcurrentFlowSource.openMerge(
        sources.map((source) => source.open),
        capacity: capacity,
        overflow: overflow,
        onOverflow: onOverflow,
      ),
    );
  }

  /// Pairs corresponding positions from [sources].
  ///
  /// Pulls one value from every source concurrently and completes when the
  /// shortest source completes. Emitted lists are immutable and input ordered.
  static Flow<List<A>, E> zip<A, E>(Iterable<Flow<A, E>> sources) => Flow._(
    () => CombinationFlowSource.openZip(
      sources.map((source) => source.open),
    ),
  );

  /// Emits an immutable input-ordered snapshot after every source has a value.
  ///
  /// A source that completes before its first value completes the combination.
  /// A completed source with a value retains that latest value until all finish.
  static Flow<List<A>, E> combineLatest<A, E>(
    Iterable<Flow<A, E>> sources, {
    int capacity = 16,
    FlowOverflowPolicy overflow = FlowOverflowPolicy.backpressure,
    E Function(FlowBufferOverflow overflow, Context context)? onOverflow,
  }) {
    FlowMailbox.validateBuffer(capacity, overflow, onOverflow);
    return Flow._(
      () => CombinationFlowSource.openCombineLatest(
        sources.map((source) => source.open),
        capacity: capacity,
        overflow: overflow,
        onOverflow: onOverflow,
      ),
    );
  }

  /// Opens one scoped pull cursor.
  ///
  /// Only one [FlowCursor.next] may be outstanding. Completion or failure closes
  /// the cursor scope. The acquiring Effect scope also closes it if the caller
  /// stops pulling early.
  Effect<FlowCursor<A, E>, E> open() => EffectAccess.create((parent) async {
    final cancellation = EffectCancellation();
    final stopParentCancellation = parent.cancellation.listen(cancellation.cancel);
    final child = EffectExecution(
      context: parent.context,
      scope: ScopeAccess.create(),
      clock: parent.clock,
      cancellation: cancellation,
    );

    final opened = await EffectAccess.evaluate(Effect.defer((_) => _openCursor()), child);
    switch (opened) {
      case Failed<FlowSourceCursor<A, E>, E>(:final cause):
        stopParentCancellation();
        return Failed<FlowCursor<A, E>, E>(
          cause,
        ).appendCleanup(await child.scope.close());
      case Succeeded<FlowSourceCursor<A, E>, E>(:final value):
        final cursor = _ManagedFlowCursor<A, E>(
          value,
          child,
          cancellation,
          stopParentCancellation,
        );
        final unregister = ScopeAccess.registerFinalizer(
          parent.scope,
          cursor._closeEffect,
          parent.context,
          parent.clock,
        );
        if (unregister != null) {
          cursor._unregister = unregister;
          return Succeeded(cursor);
        }

        final cleanup = await cursor._close(
          interrupt: true,
          terminal: const Failed(Interrupted(ScopeClosed())),
        );
        return Failed<FlowCursor<A, E>, E>(
          const Interrupted(ScopeClosed()),
        ).appendCleanup(cleanup);
    }
  });

  /// Transforms each emitted value while preserving the failure channel.
  Flow<B, E> map<B>(B Function(A value, Context context) transform) => Flow._(
    () => open().map(
      (cursor, _) => _CallbackCursor(
        () => cursor.next().map(
          (option, context) => switch (option) {
            Some<A>(:final value) => Some(transform(value, context)),
            None() => const None(),
          },
        ),
      ),
    ),
  );

  /// Emits only values accepted by [predicate].
  Flow<A, E> filter(bool Function(A value, Context context) predicate) =>
      filterMap((value, context) => predicate(value, context) ? Some(value) : const None());

  /// Transforms values and emits only present results.
  Flow<B, E> filterMap<B>(Option<B> Function(A value, Context context) transform) => Flow._(
    () => open().map((cursor, _) => _FilterMapCursor(cursor, transform)),
  );

  /// Discards the first [count] values.
  Flow<A, E> skip(int count) {
    checkNonNegative(count, 'count');
    if (count == 0) return this;
    return Flow._(
      () => open().map((cursor, _) => _SkipCursor(cursor, count)),
    );
  }

  /// Emits the longest prefix accepted by [predicate].
  Flow<A, E> takeWhile(bool Function(A value, Context context) predicate) => Flow._(
    () => open().map((cursor, _) => _TakeWhileCursor(cursor, predicate)),
  );

  /// Discards the longest prefix accepted by [predicate].
  Flow<A, E> skipWhile(bool Function(A value, Context context) predicate) => Flow._(
    () => open().map((cursor, _) => _SkipWhileCursor(cursor, predicate)),
  );

  /// Suppresses values equal to the immediately preceding value.
  ///
  /// [equals] defaults to `==`. Each consumption retains only its preceding
  /// value.
  Flow<A, E> distinctUntilChanged({
    bool Function(A previous, A current, Context context)? equals,
  }) => Flow._(
    () => open().map(
      (cursor, _) => _DistinctCursor(
        cursor,
        equals ?? (previous, current, _) => previous == current,
      ),
    ),
  );

  /// Consumes this Flow to completion before opening and consuming [other].
  Flow<A, E> concat(Flow<A, E> other) => Flow._(
    () => open().map(
      (cursor, _) => _ConcatCursor(cursor, other.open),
    ),
  );

  /// Emits each accumulated state after combining an upstream value.
  Flow<B, E> scan<B>(
    B initial,
    B Function(B state, A value, Context context) combine,
  ) => Flow._(
    () => open().map((cursor, _) => _ScanCursor(cursor, initial, combine)),
  );

  /// Emits [values] before opening this Flow.
  Flow<A, E> startWith(Iterable<A> values) =>
      Flow.fromIterable(values).widenError<E>().concat(this);

  /// Uses [fallback] only after normal completion without an emitted value.
  Flow<A, E> switchIfEmpty(Flow<A, E> Function(Context context) fallback) => Flow._(
    () => open().map(
      (cursor, _) => _SwitchIfEmptyCursor(cursor, fallback),
    ),
  );

  /// Sequences one effectful transformation at a time in source order.
  Flow<B, E> mapEffect<B>(
    Effect<B, E> Function(A value, Context context) transform,
  ) => Flow._(
    () => open().map(
      (cursor, _) => _CallbackCursor(
        () => Effect.build((resolve) async {
          return switch (await resolve(cursor.next())) {
            Some<A>(:final value) => Some(
              await resolve(Effect.defer((context) => transform(value, context))),
            ),
            None() => const None(),
          };
        }),
      ),
    ),
  );

  /// Consumes each transformed inner Flow fully before opening the next one.
  Flow<B, E> concatMap<B>(
    Flow<B, E> Function(A value, Context context) transform,
  ) => Flow._(
    () => open().map((cursor, _) => _ConcatMapCursor(cursor, transform)),
  );

  /// Concurrently consumes mapped inner Flows and emits available values.
  ///
  /// At most [concurrency] inners are active. [capacity] bounds their shared
  /// output buffer, whose overflow behavior matches [fromStream].
  Flow<B, E> mergeMap<B>(
    Flow<B, E> Function(A value, Context context) transform, {
    required int concurrency,
    int capacity = 16,
    FlowOverflowPolicy overflow = FlowOverflowPolicy.backpressure,
    E Function(FlowBufferOverflow overflow, Context context)? onOverflow,
  }) {
    checkPositive(concurrency, 'concurrency');
    FlowMailbox.validateBuffer(capacity, overflow, onOverflow);
    return Flow._(
      () => ConcurrentFlowSource.openMergeMap(
        open,
        (value, context) => transform(value, context).open,
        concurrency: concurrency,
        capacity: capacity,
        overflow: overflow,
        onOverflow: onOverflow,
      ),
    );
  }

  /// Replaces active inner work after its cleanup completes.
  ///
  /// Values from a replaced inner are suppressed immediately. If outer values
  /// arrive during cleanup, only the latest pending value is mapped afterward.
  Flow<B, E> switchMap<B>(
    Flow<B, E> Function(A value, Context context) transform, {
    int capacity = 16,
    FlowOverflowPolicy overflow = FlowOverflowPolicy.backpressure,
    E Function(FlowBufferOverflow overflow, Context context)? onOverflow,
  }) {
    FlowMailbox.validateBuffer(capacity, overflow, onOverflow);
    return Flow._(
      () => ConcurrentFlowSource.openSwitchMap(
        open,
        (value, context) => transform(value, context).open,
        capacity: capacity,
        overflow: overflow,
        onOverflow: onOverflow,
      ),
    );
  }

  /// Ignores outer values without mapping them while an inner Flow is active.
  Flow<B, E> exhaustMap<B>(
    Flow<B, E> Function(A value, Context context) transform, {
    int capacity = 16,
    FlowOverflowPolicy overflow = FlowOverflowPolicy.backpressure,
    E Function(FlowBufferOverflow overflow, Context context)? onOverflow,
  }) {
    FlowMailbox.validateBuffer(capacity, overflow, onOverflow);
    return Flow._(
      () => ConcurrentFlowSource.openExhaustMap(
        open,
        (value, context) => transform(value, context).open,
        capacity: capacity,
        overflow: overflow,
        onOverflow: onOverflow,
      ),
    );
  }

  /// Combines primary values with the latest available [secondary] value.
  ///
  /// Secondary updates never emit by themselves. Primary values before the
  /// first secondary value are ignored, and primary completion ends both.
  Flow<C, E> withLatestFrom<B, C>(
    Flow<B, E> secondary,
    C Function(A primary, B latest, Context context) combine, {
    int capacity = 16,
    FlowOverflowPolicy overflow = FlowOverflowPolicy.backpressure,
    E Function(FlowBufferOverflow overflow, Context context)? onOverflow,
  }) {
    FlowMailbox.validateBuffer(capacity, overflow, onOverflow);
    return Flow._(
      () => CombinationFlowSource.openWithLatestFrom(
        open,
        secondary.open,
        combine,
        capacity: capacity,
        overflow: overflow,
        onOverflow: onOverflow,
      ),
    );
  }

  /// Shares one upstream connection while at least one subscriber is attached.
  ///
  /// Each subscriber has a [capacity]-bounded live buffer. [replay] retains at
  /// most that many past values for subscribers joining the current connection.
  /// Completion or failure and replay remain available until the last attached
  /// subscriber scope closes. A later subscriber starts a fresh connection only
  /// after prior upstream cleanup completes.
  Flow<A, E> share({
    int capacity = 16,
    int replay = 0,
    FlowOverflowPolicy overflow = FlowOverflowPolicy.backpressure,
    E Function(FlowBufferOverflow overflow, Context context)? onOverflow,
  }) {
    FlowMailbox.validateBuffer(capacity, overflow, onOverflow);
    checkNonNegative(replay, 'replay');
    final shared = SharedFlowSource.create<A, E>(
      open,
      capacity: capacity,
      replay: replay,
      overflow: overflow,
      onOverflow: onOverflow,
    );
    return Flow._(shared);
  }

  /// Collects consecutive values into immutable batches of [count].
  ///
  /// [count] must be positive. Normal completion flushes a non-empty partial
  /// batch, while failure discards it and preserves the complete failure cause.
  Flow<List<A>, E> bufferCount(int count) {
    checkPositive(count, 'count');
    return Flow._(() => BatchingFlowSource.openCount(open, count));
  }

  /// Collects values until [duration] elapses or [maxSize] is reached.
  ///
  /// The timer starts with the first value in each batch and uses the runtime
  /// Clock. [maxSize] and [capacity] must be positive; [capacity] independently
  /// bounds source read-ahead while the downstream consumer is slow. Normal
  /// completion flushes a partial batch, while failure discards it.
  Flow<List<A>, E> bufferTime(
    Duration duration, {
    required int maxSize,
    int capacity = 16,
    FlowOverflowPolicy overflow = FlowOverflowPolicy.backpressure,
    E Function(FlowBufferOverflow overflow, Context context)? onOverflow,
  }) {
    checkDuration(duration, 'duration');
    checkPositive(maxSize, 'maxSize');
    FlowMailbox.validateBuffer(capacity, overflow, onOverflow);
    return Flow._(
      () => BatchingFlowSource.openTime(
        open,
        duration: duration,
        maxSize: maxSize,
        capacity: capacity,
        overflow: overflow,
        onOverflow: onOverflow,
      ),
    );
  }

  /// Emits the latest value after no newer value arrives within [duration].
  ///
  /// Timing uses the runtime's monotonic Clock. Normal completion emits a final
  /// pending value immediately, while failure discards it. [capacity] bounds
  /// both input staging and pending output when downstream is slow.
  Flow<A, E> debounce(
    Duration duration, {
    int capacity = 16,
    FlowOverflowPolicy overflow = FlowOverflowPolicy.backpressure,
    E Function(FlowBufferOverflow overflow, Context context)? onOverflow,
  }) {
    checkDuration(duration, 'duration');
    FlowMailbox.validateBuffer(capacity, overflow, onOverflow);
    return Flow._(
      () => FlowSchedulingSource.openDebounce(
        open,
        duration: duration,
        capacity: capacity,
        overflow: overflow,
        onOverflow: onOverflow,
      ),
    );
  }

  /// Emits the leading value and suppresses later values within [duration].
  ///
  /// There is no trailing emission. Intervals use upstream arrival timestamps
  /// from the runtime's monotonic Clock. [capacity] bounds input and output
  /// staging while downstream is slow.
  Flow<A, E> throttle(
    Duration duration, {
    int capacity = 16,
    FlowOverflowPolicy overflow = FlowOverflowPolicy.backpressure,
    E Function(FlowBufferOverflow overflow, Context context)? onOverflow,
  }) {
    checkDuration(duration, 'duration');
    FlowMailbox.validateBuffer(capacity, overflow, onOverflow);
    return Flow._(
      () => FlowSchedulingSource.openThrottle(
        open,
        duration: duration,
        capacity: capacity,
        overflow: overflow,
        onOverflow: onOverflow,
      ),
    );
  }

  /// Resubscribes after expected failures while [schedule] continues.
  ///
  /// Every consumption creates a fresh Schedule step, and every retry waits
  /// for the failed attempt's cleanup before the policy delay and next source
  /// factory call. Values delivered before failure may be delivered again.
  /// Repeatable factories and idempotent external operations remain the caller's
  /// responsibility. Causes containing a defect or interruption are preserved
  /// without retrying.
  Flow<A, E> retry<O>(Schedule<E, O, E> schedule) => Flow._(
    () => RetryFlowSource.open(open, schedule),
  );

  /// Runs source acquisition and every pull with [context].
  Flow<A, E> withContext(Context context) => Flow._(() => open().withContext(context));

  /// Transforms every expected error leaf while preserving cause structure.
  Flow<A, F> mapError<F>(F Function(E error, Context context) transform) => Flow._(
    () => open()
        .mapError(transform)
        .map((cursor, _) => _CallbackCursor(() => cursor.next().mapError(transform))),
  );

  /// Recovers once from an all-expected terminal cause.
  Flow<A, E> catchError(
    Flow<A, E> Function(E error, Context context) recover,
  ) => Flow._(
    () => Effect.succeed(_CatchErrorCursor(open, recover)),
  );

  /// Runs an effectful observer after each value and retains that value.
  Flow<A, E> tap(Effect<void, E> Function(A value, Context context) observe) =>
      mapEffect((value, context) => observe(value, context).map((_, _) => value));

  /// Observes the primary expected error without recovering it.
  Flow<A, E> tapError(
    Effect<void, Never> Function(E error, Context context) observe,
  ) => Flow._(
    () => open()
        .tapError(observe)
        .map((cursor, _) => _CallbackCursor(() => cursor.next().tapError(observe))),
  );

  /// Observes a complete terminal cause without recovering it.
  Flow<A, E> tapCause(
    Effect<void, Never> Function(Cause<E> cause, Context context) observe,
  ) => Flow._(
    () => open()
        .tapCause(observe)
        .map((cursor, _) => _CallbackCursor(() => cursor.next().tapCause(observe))),
  );

  /// Runs [finalizer] once after every terminal outcome.
  Flow<A, E> ensuring(Effect<void, Never> finalizer) => onExit((_, _) => finalizer);

  /// Runs the returned finalizer once with the complete consumption [Exit].
  Flow<A, E> onExit(
    Effect<void, Never> Function(Exit<void, E> exit, Context context) finalizer,
  ) => Flow._(
    () => _openWithExitHook(_openCursor, finalizer),
  );

  /// Emits at most the first [count] values and then closes upstream.
  Flow<A, E> take(int count) {
    checkNonNegative(count, 'count');
    if (count == 0) return Flow.empty();
    return Flow._(
      () => open().map((cursor, _) => _TakeCursor(cursor, count)),
    );
  }

  /// Collects every value into an immutable list.
  ///
  /// Calling this on an unbounded Flow does not provide a memory bound.
  Effect<List<A>, E> runCollect() => _consume((cursor, $) async {
    final values = <A>[];
    while (true) {
      switch (await $(cursor.next())) {
        case Some<A>(:final value):
          values.add(value);
        case None():
          return List<A>.unmodifiable(values);
      }
    }
  });

  /// Returns the first value, or [None] after normal empty completion.
  ///
  /// The consumer scope closes immediately after the first value.
  Effect<Option<A>, E> runFirst() => _consume((cursor, $) => $(cursor.next()));

  /// Runs one effectful [consume] callback at a time in source order.
  Effect<void, E> runForEach(
    Effect<void, E> Function(A value, Context context) consume,
  ) => _consume((cursor, $) async {
    while (true) {
      switch (await $(cursor.next())) {
        case Some<A>(:final value):
          await $(Effect.defer((context) => consume(value, context)));
        case None():
          return;
      }
    }
  });

  /// Reduces all values from [initial] and returns the final state.
  Effect<B, E> runFold<B>(
    B initial,
    B Function(B state, A value, Context context) combine,
  ) => _consume((cursor, $) async {
    var state = initial;
    while (true) {
      switch (await $(cursor.next())) {
        case Some<A>(:final value):
          state = combine(state, value, $.context);
        case None():
          return state;
      }
    }
  });

  /// Returns the final value after normal completion, or [None] when empty.
  Effect<Option<A>, E> runLast() => _consume((cursor, $) async {
    Option<A> last = const None();
    while (true) {
      switch (await $(cursor.next())) {
        case final Some<A> value:
          last = value;
        case None():
          return last;
      }
    }
  });

  /// Consumes and discards every value.
  Effect<void, E> runDrain() => runForEach((_, _) => Effect.succeed(null));

  Effect<R, E> _consume<R>(
    FutureOr<R> Function(FlowCursor<A, E> cursor, EffectBuilder<E> $) consume,
  ) => Effect.using(
    Effect.build<R, E>(($) async {
      final cursor = await $(open());
      return $(
        Effect.build<R, E>((consumeEffect) => consume(cursor, consumeEffect)).onExit(
          (exit, _) => _finishCursor(cursor, _voidExit(exit)),
        ),
      );
    }),
  );
}

Effect<FlowSourceCursor<A, E>, E> _openWithExitHook<A, E>(
  OpenFlowCursor<A, E> open,
  Effect<void, Never> Function(Exit<void, E> exit, Context context) finalizer,
) => EffectAccess.create((execution) async {
  final context = execution.context;
  final opened = await EffectAccess.evaluate(Effect.defer((_) => open()), execution);
  return switch (opened) {
    Succeeded<FlowSourceCursor<A, E>, E>(
      value: final _ExitHookCursor<A, E> existingCursor,
    ) =>
      Succeeded(
        _ExitHookCursor(
          existingCursor._upstream,
          (exit) => Effect.defer((_) => existingCursor.finalizer(exit)).ensuring(
            Effect.defer((_) => finalizer(exit, context)),
          ),
        ),
      ),
    Succeeded<FlowSourceCursor<A, E>, E>(:final value) => Succeeded(
      _ExitHookCursor(value, (exit) => finalizer(exit, context)),
    ),
    Failed<FlowSourceCursor<A, E>, E>(:final cause) =>
      Failed<FlowSourceCursor<A, E>, E>(cause).appendCleanup(
        await _runFlowFinalizer(
          (exit) => finalizer(exit, context),
          Failed(cause),
          execution,
        ),
      ),
  };
});

Effect<void, Never> _finishCursor<A, E>(
  FlowCursor<A, E> cursor,
  Exit<void, E> exit,
) => switch (cursor) {
  _ManagedFlowCursor<A, E>() => cursor._finish(exit),
  _ => cursor.close(),
};

Exit<void, E> _voidExit<A, E>(Exit<A, E> exit) => switch (exit) {
  Succeeded<A, E>() => const Succeeded(null),
  Failed<A, E>(:final cause) => Failed(cause),
};

Future<Cause<Never>?> _runFlowFinalizer<E>(
  Effect<void, Never> Function(Exit<void, E> exit) finalizer,
  Exit<void, E> exit,
  EffectExecution execution,
) async {
  late final Effect<void, Never> effect;
  try {
    effect = finalizer(exit);
  } on Object catch (error, stackTrace) {
    return Defect(error, stackTrace);
  }
  return switch (await EffectExecution.runProtected(
    effect,
    execution.context,
    execution.clock,
  )) {
    Succeeded<void, Never>() => null,
    Failed<void, Never>(:final cause) => cause,
  };
}

/// A scoped pull cursor for one Flow consumption.
abstract interface class FlowCursor<A, E> implements FlowSourceCursor<A, E> {
  /// Pulls the next value or [None] for normal completion.
  @override
  Effect<Option<A>, E> next();

  /// Stops consumption and awaits resource cleanup.
  Effect<void, Never> close();
}

abstract interface class _FlowSourceCursorFinalizer<E> {
  Effect<void, Never> Function(Exit<void, E> exit) get finalizer;
}

final class _ManagedFlowCursor<A, E> implements FlowCursor<A, E> {
  _ManagedFlowCursor(
    this._cursor,
    this._execution,
    this._cancellation,
    this._stopParentCancellation,
  );

  final FlowSourceCursor<A, E> _cursor;
  final EffectExecution _execution;
  final EffectCancellation _cancellation;
  final void Function() _stopParentCancellation;
  Future<Exit<Option<A>, E>>? _activePull;
  Future<Cause<Never>?>? _closing;
  void Function()? _unregister;
  var _cleanupReported = false;
  var _closed = false;

  @override
  Effect<Option<A>, E> next() => EffectAccess.create((caller) async {
    if (_closed) return const Succeeded(None());
    if (_activePull != null) {
      return Failed(
        Defect(StateError('Only one Flow cursor pull may be outstanding.'), StackTrace.current),
      );
    }

    final pull = EffectAccess.evaluate(_cursor.next(), _execution);
    _activePull = pull;
    final stopCallerCancellation = caller.cancellation.listen(_cancellation.cancel);
    late final Exit<Option<A>, E> exit;
    try {
      exit = await pull;
    } finally {
      stopCallerCancellation();
      _activePull = null;
    }

    if (exit case Failed<Option<A>, E>() || Succeeded<Option<A>, E>(value: None())) {
      return exit.appendCleanup(
        await _close(interrupt: false, terminal: _voidExit(exit)),
      );
    }
    return exit;
  });

  @override
  Effect<void, Never> close() => _closeEffect;

  Effect<void, Never> get _closeEffect => EffectAccess.create((_) async {
    final cleanup = await _close(
      interrupt: true,
      terminal: const Failed(Interrupted(FlowCursorClosed())),
    );
    return cleanup == null ? const Succeeded(null) : Failed(cleanup);
  });

  Effect<void, Never> _finish(Exit<void, E> exit) => EffectAccess.create((_) async {
    final cleanup = await _close(interrupt: false, terminal: exit);
    return cleanup == null ? const Succeeded(null) : Failed(cleanup);
  });

  Future<Cause<Never>?> _close({
    required bool interrupt,
    required Exit<void, E> terminal,
  }) async {
    var closing = _closing;
    closing ??= _startClosing(interrupt, terminal);
    final cleanup = await closing;
    if (_cleanupReported) return null;
    _cleanupReported = true;
    return cleanup;
  }

  Future<Cause<Never>?> _startClosing(
    bool interrupt,
    Exit<void, E> terminal,
  ) {
    final closing = _closeNow(interrupt: interrupt, terminal: terminal);
    _closing = closing;
    return closing;
  }

  Future<Cause<Never>?> _closeNow({
    required bool interrupt,
    required Exit<void, E> terminal,
  }) async {
    _closed = true;
    _stopParentCancellation();
    if (interrupt && !_cancellation.isCancelled) {
      _cancellation.cancel(const FlowCursorClosed());
    }
    if (interrupt) await _activePull;
    final hookFailure = switch (_cursor) {
      _FlowSourceCursorFinalizer<E>(:final finalizer) => await _runFlowFinalizer(
        finalizer,
        terminal,
        _execution,
      ),
      _ => null,
    };
    final scopeFailure = await _execution.scope.close();
    // Keep parent ownership until cleanup has finished, including concurrent
    // parent shutdown, then release the completed cursor from its parent scope.
    final unregister = _unregister;
    _unregister = null;
    unregister?.call();
    return CauseGroup.sequential([?hookFailure, ?scopeFailure]);
  }
}

final class _CallbackCursor<A, E> implements FlowSourceCursor<A, E> {
  const _CallbackCursor(this._next);

  final Effect<Option<A>, E> Function() _next;

  @override
  Effect<Option<A>, E> next() => _next();
}

final class _ValueCursor<A, E> implements FlowSourceCursor<A, E> {
  _ValueCursor(this._value);

  final A _value;
  var _emitted = false;

  @override
  Effect<Option<A>, E> next() => Effect.defer((_) {
    if (_emitted) return Effect.succeed(const None());
    _emitted = true;
    return Effect.succeed(Some(_value));
  });
}

final class _IteratorCursor<A, E> implements FlowSourceCursor<A, E> {
  _IteratorCursor(this._iterator);

  final Iterator<A> _iterator;

  @override
  Effect<Option<A>, E> next() => EffectAccess.create((_) async {
    return _iterator.moveNext() ? Succeeded(Some(_iterator.current)) : const Succeeded(None());
  });
}

final class _CatchErrorCursor<A, E> implements FlowSourceCursor<A, E> {
  _CatchErrorCursor(this._openUpstream, this._recover);

  final Effect<FlowCursor<A, E>, E> Function() _openUpstream;
  final Flow<A, E> Function(E error, Context context) _recover;
  FlowCursor<A, E>? _active;
  var _recovered = false;

  @override
  Effect<Option<A>, E> next() => Effect.defer((_) {
    final active = _active;
    if (active != null) {
      final pull = active.next();
      return _recovered ? pull : pull.catchError(_recoverAndPull);
    }
    return Effect.defer((_) => _openUpstream())
        .flatMap((cursor, _) {
          _active = cursor;
          return cursor.next();
        })
        .catchError(_recoverAndPull);
  });

  Effect<Option<A>, E> _recoverAndPull(E error, Context context) {
    _recovered = true;
    return Effect.defer((_) => _recover(error, context).open()).flatMap((cursor, _) {
      _active = cursor;
      return cursor.next();
    });
  }
}

final class _ExitHookCursor<A, E> implements FlowSourceCursor<A, E>, _FlowSourceCursorFinalizer<E> {
  _ExitHookCursor(this._upstream, this.finalizer);

  final FlowSourceCursor<A, E> _upstream;

  @override
  final Effect<void, Never> Function(Exit<void, E> exit) finalizer;

  @override
  Effect<Option<A>, E> next() => _upstream.next();
}

final class _ConcatMapCursor<A, B, E> implements FlowSourceCursor<B, E> {
  _ConcatMapCursor(this._upstream, this._transform);

  final FlowSourceCursor<A, E> _upstream;
  final Flow<B, E> Function(A value, Context context) _transform;
  FlowCursor<B, E>? _inner;

  @override
  Effect<Option<B>, E> next() => Effect.build(($) async {
    while (true) {
      final inner = _inner;
      if (inner != null) {
        final option = await $(inner.next());
        if (option case Some<B>()) return option;
        _inner = null;
      }

      switch (await $(_upstream.next())) {
        case Some<A>(:final value):
          _inner = await $(
            Effect.defer((context) => _transform(value, context).open()),
          );
        case None():
          return const None();
      }
    }
  });
}

final class _FilterMapCursor<A, B, E> implements FlowSourceCursor<B, E> {
  _FilterMapCursor(this._upstream, this._transform);

  final FlowSourceCursor<A, E> _upstream;
  final Option<B> Function(A value, Context context) _transform;

  @override
  Effect<Option<B>, E> next() => Effect.build(($) async {
    while (true) {
      switch (await $(_upstream.next())) {
        case Some<A>(:final value):
          final transformed = _transform(value, $.context);
          if (transformed case Some<B>()) return transformed;
        case None():
          return const None();
      }
    }
  });
}

final class _SkipCursor<A, E> implements FlowSourceCursor<A, E> {
  _SkipCursor(this._upstream, this._remaining);

  final FlowSourceCursor<A, E> _upstream;
  int _remaining;

  @override
  Effect<Option<A>, E> next() => Effect.build(($) async {
    while (_remaining > 0) {
      final option = await $(_upstream.next());
      if (option case None()) return const None();
      _remaining -= 1;
    }
    return $(_upstream.next());
  });
}

final class _TakeWhileCursor<A, E> implements FlowSourceCursor<A, E> {
  _TakeWhileCursor(this._upstream, this._predicate);

  final FlowSourceCursor<A, E> _upstream;
  final bool Function(A value, Context context) _predicate;
  var _done = false;

  @override
  Effect<Option<A>, E> next() {
    if (_done) return Effect.succeed(const None());
    return _upstream.next().map((option, context) {
      if (option case Some<A>(:final value) when !_predicate(value, context)) {
        _done = true;
        return const None();
      }
      return option;
    });
  }
}

final class _SkipWhileCursor<A, E> implements FlowSourceCursor<A, E> {
  _SkipWhileCursor(this._upstream, this._predicate);

  final FlowSourceCursor<A, E> _upstream;
  final bool Function(A value, Context context) _predicate;
  var _skipping = true;

  @override
  Effect<Option<A>, E> next() => Effect.build(($) async {
    if (!_skipping) return $(_upstream.next());
    while (true) {
      final option = await $(_upstream.next());
      switch (option) {
        case Some<A>(:final value) when _predicate(value, $.context):
          continue;
        case Some<A>():
          _skipping = false;
          return option;
        case None():
          return const None();
      }
    }
  });
}

final class _DistinctCursor<A, E> implements FlowSourceCursor<A, E> {
  _DistinctCursor(this._upstream, this._equals);

  final FlowSourceCursor<A, E> _upstream;
  final bool Function(A previous, A current, Context context) _equals;
  late A _previous;
  var _hasPrevious = false;

  @override
  Effect<Option<A>, E> next() => Effect.build(($) async {
    while (true) {
      final option = await $(_upstream.next());
      switch (option) {
        case Some<A>(:final value):
          if (_hasPrevious && _equals(_previous, value, $.context)) continue;
          _previous = value;
          _hasPrevious = true;
          return option;
        case None():
          return const None();
      }
    }
  });
}

final class _ConcatCursor<A, E> implements FlowSourceCursor<A, E> {
  _ConcatCursor(this._first, this._openSecond);

  FlowSourceCursor<A, E>? _first;
  final OpenFlowCursor<A, E> _openSecond;
  FlowSourceCursor<A, E>? _second;

  @override
  Effect<Option<A>, E> next() => Effect.build(($) async {
    final first = _first;
    if (first != null) {
      final option = await $(first.next());
      if (option case Some<A>()) return option;
      _first = null;
    }
    final existingSecond = _second;
    late final FlowSourceCursor<A, E> activeSecond;
    if (existingSecond != null) {
      activeSecond = existingSecond;
    } else {
      activeSecond = await $(
        Effect.defer<FlowSourceCursor<A, E>, E>((_) => _openSecond()),
      );
      _second = activeSecond;
    }
    return $(activeSecond.next());
  });
}

final class _ScanCursor<A, B, E> implements FlowSourceCursor<B, E> {
  _ScanCursor(this._upstream, this._state, this._combine);

  final FlowSourceCursor<A, E> _upstream;
  final B Function(B state, A value, Context context) _combine;
  B _state;

  @override
  Effect<Option<B>, E> next() => _upstream.next().map((option, context) {
    return switch (option) {
      Some<A>(:final value) => Some(_state = _combine(_state, value, context)),
      None() => const None(),
    };
  });
}

final class _SwitchIfEmptyCursor<A, E> implements FlowSourceCursor<A, E> {
  _SwitchIfEmptyCursor(this._upstream, this._fallback);

  final FlowSourceCursor<A, E> _upstream;
  final Flow<A, E> Function(Context context) _fallback;
  FlowSourceCursor<A, E>? _fallbackCursor;
  var _emitted = false;
  var _upstreamDone = false;

  @override
  Effect<Option<A>, E> next() => Effect.build(($) async {
    if (!_upstreamDone) {
      final option = await $(_upstream.next());
      if (option case Some<A>()) {
        _emitted = true;
        return option;
      }
      _upstreamDone = true;
      if (_emitted) return const None();
    }

    final existingFallback = _fallbackCursor;
    late final FlowSourceCursor<A, E> activeFallback;
    if (existingFallback != null) {
      activeFallback = existingFallback;
    } else {
      activeFallback = await $(
        Effect.defer<FlowSourceCursor<A, E>, E>(
          (context) => _fallback(context).open(),
        ),
      );
      _fallbackCursor = activeFallback;
    }
    return $(activeFallback.next());
  });
}

final class _TakeCursor<A, E> implements FlowSourceCursor<A, E> {
  _TakeCursor(this._upstream, this._remaining);

  final FlowSourceCursor<A, E> _upstream;
  int _remaining;

  @override
  Effect<Option<A>, E> next() {
    if (_remaining == 0) return Effect.succeed(const None());
    return _upstream.next().map((option, _) {
      if (option case Some<A>()) _remaining -= 1;
      return option;
    });
  }
}

/// Safe expected-error widening for Flows that cannot fail as expected.
extension FlowNeverError<A> on Flow<A, Never> {
  /// Widens the uninhabited expected-error channel to [E].
  Flow<A, E> widenError<E>() => mapError<E>((error, _) => _widenNever<E>(error! as Never));
}

/// Uses Flow internals from integration libraries without reversing dependencies.
abstract final class FlowAccess {
  /// Creates a single-value Flow from [effect].
  static Flow<A, E> fromEffect<A, E>(Effect<A, E> effect) => Flow._(
    () => Effect.succeed(_EffectCursor(effect)),
  );
}

final class _EffectCursor<A, E> implements FlowSourceCursor<A, E> {
  _EffectCursor(this._effect);

  final Effect<A, E> _effect;
  var _emitted = false;

  @override
  Effect<Option<A>, E> next() {
    if (_emitted) return Effect.succeed(const None());
    _emitted = true;
    return _effect.map<Option<A>>((value, _) => Some(value));
  }
}

/// Why a manually closed Flow cursor interrupted active work.
final class FlowCursorClosed {
  /// Creates the stable manual-close reason.
  const FlowCursorClosed();

  @override
  String toString() => 'Flow cursor closed';
}
