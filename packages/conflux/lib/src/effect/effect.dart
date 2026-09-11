import 'dart:async';
import 'dart:collection';

import 'package:conflux/non_empty_list.dart';
import 'package:conflux/option.dart';
import 'package:conflux/result.dart';
import 'package:conflux/src/effect/builder.dart';
import 'package:conflux/src/effect/cause.dart';
import 'package:conflux/src/effect/clock.dart';
import 'package:conflux/src/effect/execution.dart';
import 'package:conflux/src/effect/exit.dart';
import 'package:context/context.dart';

typedef _EffectRun<A, E> = Future<Exit<A, E>> Function(EffectExecution execution);

/// A lazy, reusable description of work producing [A] or expected error [E].
final class Effect<A, E> {
  const Effect._(this._run);

  final _EffectRun<A, E> _run;

  Future<Exit<A, E>> _evaluate(EffectExecution execution) async {
    if (execution.cancellation.isCancelled) {
      return Failed(Interrupted(execution.cancellation.reason));
    }
    try {
      final boundary = execution.schedulingBoundary();
      if (boundary != null) await boundary;
      if (execution.cancellation.isCancelled) {
        return Failed(Interrupted(execution.cancellation.reason));
      }
      return await _run(execution);
    } on Object catch (error, stackTrace) {
      return Failed(Defect(error, stackTrace));
    }
  }

  /// Describes a successful value without starting work.
  static Effect<A, E> succeed<A, E>(A value) => Effect._((_) async => Succeeded(value));

  /// Describes an expected failure without starting work.
  static Effect<A, E> fail<A, E>(E error) => Effect._((_) async => Failed(Expected(error)));

  /// Describes an already structured failure without starting work.
  static Effect<A, E> failCause<A, E>(Cause<E> cause) => Effect._((_) async => Failed(cause));

  /// Lazily invokes a synchronous callback when the effect runs.
  ///
  /// A thrown object becomes a [Defect] with its original stack trace.
  static Effect<A, Never> sync<A>(A Function() callback) =>
      Effect._((_) async => Succeeded(callback()));

  /// Lazily chooses another effect for each execution.
  static Effect<A, E> defer<A, E>(Effect<A, E> Function() factory) =>
      Effect._((execution) => factory()._evaluate(execution));

  /// Waits for [duration] using the execution's cancellable [Clock].
  ///
  /// The duration must not be negative. It is passed to [Clock.sleep] without
  /// rounding; the selected Clock defines its effective timer precision.
  static Effect<void, Never> sleep(Duration duration) {
    _requireNonNegativeDuration(duration);
    return Effect._((execution) async {
      final wait = execution.clock.sleep(duration);
      final completed = Completer<Exit<void, Never>>();
      var settled = false;
      void Function()? stopListening;

      Future<void> finish(Exit<void, Never> exit) async {
        if (settled) return;
        settled = true;
        stopListening?.call();
        try {
          await wait.cancel();
          completed.complete(exit);
        } on Object catch (error, stackTrace) {
          completed.complete(exit.appendCleanup(Defect(error, stackTrace)));
        }
      }

      stopListening = execution.cancellation.listen(
        (reason) => unawaited(finish(Failed(Interrupted(reason)))),
      );
      // Even cancellation during Clock.sleep must observe a late wait failure.
      try {
        unawaited(
          wait.completed.then<void>(
            (_) => finish(const Succeeded(null)),
            onError: (Object error, StackTrace stackTrace) =>
                finish(Failed(Defect(error, stackTrace))),
          ),
        );
      } on Object catch (error, stackTrace) {
        unawaited(finish(Failed(Defect(error, stackTrace))));
      }
      return completed.future;
    });
  }

  /// Converts a synchronous [Result] into an effect.
  static Effect<A, E> fromResult<A, E>(Result<A, E> result) => switch (result) {
    Success<A, E>(:final value) => succeed(value),
    Failure<A, E>(:final error) => fail(error),
  };

  /// Converts an [Option], evaluating [onNone] only when it is absent.
  static Effect<A, E> fromOption<A, E>(
    Option<A> option,
    E Function() onNone,
  ) => switch (option) {
    Some<A>(:final value) => succeed(value),
    None() => defer(() => fail(onNone())),
  };

  /// Adapts a foreign [Future] factory to typed Effect execution.
  ///
  /// [onError] is the only conversion from a foreign failure to [E]. When
  /// cancellation is requested, [onCancel] may stop adapter-owned work. With
  /// no hook, Conflux observes late completion but cannot stop the Future.
  static Effect<A, E> tryFuture<A, E>(
    Future<A> Function() factory, {
    required E Function(Object error, StackTrace stackTrace) onError,
    FutureOr<void> Function()? onCancel,
  }) => Effect._((execution) async {
    late final Future<A> future;
    try {
      future = factory();
    } on Object catch (error, stackTrace) {
      try {
        return Failed(Expected(onError(error, stackTrace)));
      } on Object catch (mapperError, mapperStackTrace) {
        return Failed(Defect(mapperError, mapperStackTrace));
      }
    }

    Future<Cause<E>> cancellationCause(Object? reason) async {
      Cause<E> cause = Interrupted(reason);
      if (onCancel != null) {
        try {
          await onCancel();
        } on Object catch (error, stackTrace) {
          cause = Sequential([cause, Defect(error, stackTrace)]);
        }
      }
      return cause;
    }

    if (execution.cancellation.isCancelled) {
      unawaited(
        future.then<void>(
          (_) {},
          onError: (Object _, StackTrace _) {},
        ),
      );
      return Failed(
        await cancellationCause(execution.cancellation.reason),
      );
    }

    final completion = Completer<Exit<A, E>>();
    var settled = false;
    late final void Function() stopListening;

    void complete(Exit<A, E> exit) {
      if (settled) return;
      settled = true;
      stopListening();
      completion.complete(exit);
    }

    stopListening = execution.cancellation.listen((reason) async {
      if (settled) return;
      settled = true;
      stopListening();
      completion.complete(Failed(await cancellationCause(reason)));
    });

    unawaited(
      future.then(
        (value) => complete(Succeeded(value)),
        onError: (Object error, StackTrace stackTrace) {
          if (settled) return;
          try {
            complete(Failed(Expected(onError(error, stackTrace))));
          } on Object catch (mapperError, mapperStackTrace) {
            complete(Failed(Defect(mapperError, mapperStackTrace)));
          }
        },
      ),
    );
    return completion.future;
  });

  /// Reads a value from the execution [Context] when run.
  static Effect<A, Never> context<A>(A Function(Context context) select) =>
      Effect._((execution) async => Succeeded(select(execution.context)));

  /// Builds an effect with a callback-local callable binder.
  ///
  /// Every asynchronous bind must be awaited. The builder is valid only while
  /// [body] is active, and every run receives fresh builder state. A plain Dart
  /// await has no cancellation hook; use [tryFuture] for adaptable foreign work.
  static Effect<A, E> build<A, E>(
    FutureOr<A> Function(EffectBuilder<E> $) body,
  ) => Effect._((execution) async {
    final builder = EffectBuilderAccess.create<E>(execution);
    try {
      final value = await body(builder);
      final failure = EffectBuilderAccess.terminalCause(builder);
      return failure == null ? Succeeded(value) : Failed(failure);
    } on Object catch (error, stackTrace) {
      final failure = EffectBuilderAccess.terminalCause(builder);
      if (failure != null) return Failed(failure);
      return Failed(Defect(error, stackTrace));
    } finally {
      EffectBuilderAccess.deactivate(builder);
    }
  });

  /// Runs this effect with [context] for it and its descendants.
  Effect<A, E> withContext(Context context) => Effect._((execution) async {
    final previous = execution.context;
    execution.context = context;
    try {
      return await _evaluate(execution);
    } finally {
      execution.context = previous;
    }
  });

  /// Runs [effect] in a child scope and closes it before returning.
  static Effect<A, E> using<A, E>(Effect<A, E> effect) => Effect._((execution) async {
    final child = EffectExecution(
      context: execution.context,
      scope: ScopeAccess.create(),
      clock: execution.clock,
      cancellation: execution.cancellation,
    );
    return child.runScoped(effect);
  });

  /// Collects Effects in input order, sequentially unless [concurrency] is set.
  static Effect<List<A>, E> all<A, E>(
    Iterable<Effect<A, E>> effects, {
    int concurrency = 1,
  }) {
    if (concurrency <= 0) {
      throw ArgumentError.value(concurrency, 'concurrency', 'Must be positive.');
    }
    return Effect._((execution) {
      return _EffectCollection.run(List.of(effects), execution, concurrency);
    });
  }

  /// Maps [inputs] to Effects and collects their values in input order.
  static Effect<List<A>, E> forEach<I, A, E>(
    Iterable<I> inputs,
    Effect<A, E> Function(I input) effect, {
    int concurrency = 1,
  }) {
    if (concurrency <= 0) {
      throw ArgumentError.value(concurrency, 'concurrency', 'Must be positive.');
    }
    return Effect.defer(() {
      final effects = inputs.map(
        (input) => Effect.defer<A, E>(() => effect(input)),
      );
      return all(effects, concurrency: concurrency);
    });
  }

  /// Returns the first successful branch after interrupting and cleaning up losers.
  static Effect<A, E> race<A, E>(Iterable<Effect<A, E>> effects) => Effect._((execution) {
    final branches = List<Effect<A, E>>.of(effects);
    if (branches.isEmpty) {
      throw ArgumentError.value(effects, 'effects', 'Must not be empty.');
    }
    return _EffectRace.run(branches, execution);
  });

  /// Evaluates every input and accumulates all expected errors in input order.
  static Effect<List<A>, NonEmptyList<E>> validate<I, A, E>(
    Iterable<I> inputs,
    Effect<A, E> Function(I input) validate,
  ) => Effect._((execution) async {
    final values = <A>[];
    final errors = <E>[];
    for (final input in inputs) {
      final exit = await Effect.defer(() => validate(input))._evaluate(execution);
      switch (exit) {
        case Succeeded<A, E>(:final value):
          values.add(value);
        case Failed<A, E>(:final cause) when cause.containsFatal:
          return Failed(
            cause.mapExpected<NonEmptyList<E>>(NonEmptyList.new),
          );
        case Failed<A, E>(:final cause):
          errors.addAll(cause.expectedErrors);
      }
    }
    if (errors.isNotEmpty) {
      return Failed(Expected(NonEmptyList(errors.first, errors.skip(1))));
    }
    return Succeeded(List.unmodifiable(values));
  });
}

/// Clock-based timing for an Effect.
extension EffectTiming<A, E> on Effect<A, E> {
  /// Waits for [duration] before starting this Effect.
  Effect<A, E> delay(Duration duration) {
    _requireNonNegativeDuration(duration);
    return Effect._((execution) async {
      final waited = await Effect.sleep(duration)._evaluate(execution);
      return switch (waited) {
        Succeeded<void, Never>() => _evaluate(execution),
        Failed<void, Never>(:final cause) => Failed(cause),
      };
    });
  }

  /// Measures this Effect with the execution's monotonic clock.
  Effect<({A value, Duration elapsed}), E> timed() => Effect._((execution) async {
    final startedAt = execution.clock.monotonic();
    return switch (await _evaluate(execution)) {
      Succeeded<A, E>(:final value) => Succeeded((
        value: value,
        elapsed: execution.clock.monotonic() - startedAt,
      )),
      Failed<A, E>(:final cause) => Failed(cause),
    };
  });

  /// Interrupts this Effect after [duration] and returns [onTimeout].
  ///
  /// Child cleanup finishes before the timeout result becomes available, so
  /// cleanup can make the total elapsed time exceed [duration].
  Effect<A, E> timeout(
    Duration duration, {
    required E Function() onTimeout,
  }) {
    _requireNonNegativeDuration(duration);
    return Effect._((execution) async {
      final operation = ScopeAccess.fork(execution.scope, this, execution);
      final timer = ScopeAccess.fork(
        execution.scope,
        Effect.sleep(duration),
        execution,
      );
      final winner = await Future.any<_TimeoutWinner<A, E>>([
        operation.join().then(_OperationFinished.new),
        timer.join().then(_TimerFinished.new),
      ]);

      return switch (winner) {
        _OperationFinished<A, E>(:final exit) => () async {
          final timerExit = await timer.interrupt(const _TimeoutCancelled());
          final cleanup = switch (timerExit) {
            Succeeded<void, Never>() => null,
            Failed<void, Never>(:final cause) => cause.defectsOnly,
          };
          return exit.appendCleanup(cleanup);
        }(),
        _TimerFinished<A, E>(exit: Failed<void, Never>(:final cause)) => () async {
          final operationExit = await operation.interrupt(
            execution.cancellation.reason,
          );
          return Failed<A, E>(
            cause.mapExpected<E>(_absurd),
          ).appendCleanup(_defectsFrom(operationExit));
        }(),
        _TimerFinished<A, E>(exit: Succeeded<void, Never>()) => () async {
          final operationExit = await operation.interrupt(
            const _TimeoutElapsed(),
          );
          late final E error;
          try {
            error = onTimeout();
          } on Object catch (failure, stackTrace) {
            return Failed<A, E>(
              Defect(failure, stackTrace),
            ).appendCleanup(_defectsFrom(operationExit));
          }
          return Failed<A, E>(
            Expected(error),
          ).appendCleanup(_defectsFrom(operationExit));
        }(),
      };
    });
  }
}

Cause<Never>? _defectsFrom<A, E>(Exit<A, E> exit) => switch (exit) {
  Succeeded<A, E>() => null,
  Failed<A, E>(:final cause) => cause.defectsOnly,
};

void _requireNonNegativeDuration(Duration duration) {
  if (duration.isNegative) {
    throw ArgumentError.value(duration, 'duration', 'Must not be negative.');
  }
}

E _absurd<E>(Never value) => value;

sealed class _TimeoutWinner<A, E> {
  const _TimeoutWinner();
}

final class _OperationFinished<A, E> extends _TimeoutWinner<A, E> {
  const _OperationFinished(this.exit);

  final Exit<A, E> exit;
}

final class _TimerFinished<A, E> extends _TimeoutWinner<A, E> {
  const _TimerFinished(this.exit);

  final Exit<void, Never> exit;
}

final class _TimeoutElapsed {
  const _TimeoutElapsed();

  @override
  String toString() => 'Effect timeout elapsed';
}

final class _TimeoutCancelled {
  const _TimeoutCancelled();

  @override
  String toString() => 'Effect timeout cancelled';
}

final class _IndexedExit<A, E> {
  const _IndexedExit(this.index, this.exit);

  final int index;
  final Exit<A, E> exit;
}

/// Owns active branches and observes each completion once.
///
/// Completions are delivered in arrival order. Results and cleanup failures
/// retain source order separately, so an earlier failure cannot reorder winners.
final class _EffectBranches<A, E> {
  _EffectBranches(this.execution);

  final EffectExecution execution;
  final _active = <int, Fiber<A, E>>{};
  final _ready = Queue<_IndexedExit<A, E>>();
  Completer<_IndexedExit<A, E>>? _waiting;

  int get length => _active.length;
  bool get isNotEmpty => _active.isNotEmpty;

  void start(int index, Effect<A, E> effect) {
    final fiber = ScopeAccess.fork(execution.scope, effect, execution);
    _active[index] = fiber;
    unawaited(
      fiber.join().then((exit) {
        final waiting = _waiting;
        if (waiting == null) {
          _ready.add(_IndexedExit(index, exit));
        } else {
          _waiting = null;
          waiting.complete(_IndexedExit(index, exit));
        }
      }),
    );
  }

  Future<_IndexedExit<A, E>> next() async {
    // Branch executions have separate counters; the coordinator must also
    // yield while processing a long sequence of immediately completed work.
    final boundary = execution.schedulingBoundary();
    if (boundary != null) await boundary;
    final _IndexedExit<A, E> completed;
    if (_ready.isNotEmpty) {
      completed = _ready.removeFirst();
    } else {
      final waiting = Completer<_IndexedExit<A, E>>();
      _waiting = waiting;
      completed = await waiting.future;
    }
    _active.remove(completed.index);
    return completed;
  }

  Future<Cause<Never>?> interrupt(Object reason) async {
    // Future.wait preserves the source order of the insertion-ordered map.
    final exits = await Future.wait(
      _active.values.map((fiber) => fiber.interrupt(reason)),
    );
    _active.clear();
    _ready.clear();
    return CauseGroup.parallel(exits.map(_defectsFrom).whereType<Cause<Never>>());
  }
}

abstract final class _EffectCollection {
  static Future<Exit<List<A>, E>> run<A, E>(
    List<Effect<A, E>> effects,
    EffectExecution execution,
    int concurrency,
  ) async {
    if (effects.isEmpty) return Succeeded(List.unmodifiable(const []));

    final slots = List<Option<A>>.filled(effects.length, const None());
    final branches = _EffectBranches<A, E>(execution);
    var nextIndex = 0;

    void startNext() {
      final index = nextIndex++;
      branches.start(index, effects[index]);
    }

    while (nextIndex < effects.length && branches.length < concurrency) {
      startNext();
    }

    while (branches.isNotEmpty) {
      final completed = await branches.next();
      switch (completed.exit) {
        case Succeeded<A, E>(:final value):
          slots[completed.index] = Some(value);
          if (nextIndex < effects.length) startNext();
        case Failed<A, E>(:final cause):
          final cleanup = await branches.interrupt(const _CollectionStopped());
          return Failed<List<A>, E>(cause).appendCleanup(cleanup);
      }
    }

    final values = slots.map((slot) {
      return switch (slot) {
        Some<A>(:final value) => value,
        None() => throw StateError('Collection completed without a value.'),
      };
    });
    return Succeeded(List.unmodifiable(values));
  }
}

final class _CollectionStopped {
  const _CollectionStopped();

  @override
  String toString() => 'Collection stopped after a branch failed';
}

abstract final class _EffectRace {
  static Future<Exit<A, E>> run<A, E>(
    List<Effect<A, E>> effects,
    EffectExecution execution,
  ) async {
    final branches = _EffectBranches<A, E>(execution);
    for (var index = 0; index < effects.length; index += 1) {
      branches.start(index, effects[index]);
    }
    final failures = List<Cause<E>?>.filled(effects.length, null);

    while (branches.isNotEmpty) {
      final completed = await branches.next();
      switch (completed.exit) {
        case Failed<A, E>(:final cause):
          failures[completed.index] = cause;
        case Succeeded<A, E>(:final value):
          final cleanup = await branches.interrupt(const _RaceLost());
          return Succeeded<A, E>(value).appendCleanup(cleanup);
      }
    }

    return Failed(Parallel(failures.whereType<Cause<E>>()));
  }
}

final class _RaceLost {
  const _RaceLost();

  @override
  String toString() => 'Race branch lost';
}

/// Type-preserving transformations for an Effect.
extension EffectTransformation<A, E> on Effect<A, E> {
  /// Transforms a successful value.
  Effect<B, E> map<B>(B Function(A value) transform) => Effect._((execution) async {
    return switch (await _evaluate(execution)) {
      Succeeded<A, E>(:final value) => Succeeded(transform(value)),
      Failed<A, E>(:final cause) => Failed(cause),
    };
  });

  /// Sequences another Effect after success.
  Effect<B, E> flatMap<B>(Effect<B, E> Function(A value) transform) => Effect._((execution) async {
    return switch (await _evaluate(execution)) {
      Succeeded<A, E>(:final value) => await transform(value)._evaluate(execution),
      Failed<A, E>(:final cause) => Failed(cause),
    };
  });

  /// Transforms every expected error leaf while preserving cause structure.
  Effect<A, F> mapError<F>(F Function(E error) transform) => Effect._((execution) async {
    return switch (await _evaluate(execution)) {
      Succeeded<A, E>(:final value) => Succeeded(value),
      Failed<A, E>(:final cause) => Failed(cause.mapExpected(transform)),
    };
  });

  /// Transforms success and every expected error leaf.
  Effect<B, F> mapBoth<B, F>({
    required B Function(A value) onSuccess,
    required F Function(E error) onFailure,
  }) => map(onSuccess).mapError(onFailure);

  /// Discards a successful value.
  Effect<void, E> asVoid() => map((_) {});

  /// Combines two successful values in sequence.
  Effect<C, E> zipWith<B, C>(
    Effect<B, E> other,
    C Function(A left, B right) combine,
  ) => flatMap((left) => other.map((right) => combine(left, right)));

  /// Keeps a successful value or creates an expected failure.
  Effect<A, E> filterOrFail(
    bool Function(A value) predicate,
    E Function(A value) onFailure,
  ) => flatMap((value) {
    return predicate(value) ? Effect.succeed(value) : Effect.fail(onFailure(value));
  });
}

/// Removes one Effect layer while preserving its expected error type.
extension FlattenEffect<A, E> on Effect<Effect<A, E>, E> {
  /// Sequences the nested Effect.
  Effect<A, E> flatten() => flatMap((effect) => effect);
}

/// Expected-error recovery under the deterministic primary-error contract.
extension EffectRecovery<A, E> on Effect<A, E> {
  /// Recovers an all-expected cause once using its primary error.
  Effect<A, E> catchError(Effect<A, E> Function(E error) recover) => Effect._((execution) async {
    final exit = await _evaluate(execution);
    if (exit case Failed<A, E>(:final cause)) {
      final primary = cause.primaryError;
      if (primary case Some<E>(:final value)) {
        return recover(value)._evaluate(execution);
      }
    }
    return exit;
  });

  /// Maps success or an all-expected failure to a value.
  Effect<B, E> match<B>({
    required B Function(A value) onSuccess,
    required B Function(E error) onFailure,
  }) => matchEffect(
    onSuccess: (value) => Effect.succeed(onSuccess(value)),
    onFailure: (error) => Effect.succeed(onFailure(error)),
  );

  /// Selects another Effect for success or an all-expected failure.
  Effect<B, E> matchEffect<B>({
    required Effect<B, E> Function(A value) onSuccess,
    required Effect<B, E> Function(E error) onFailure,
  }) => Effect._((execution) async {
    final exit = await _evaluate(execution);
    return switch (exit) {
      Succeeded<A, E>(:final value) => onSuccess(value)._evaluate(execution),
      Failed<A, E>(:final cause) => switch (cause.primaryError) {
        Some<E>(value: final error) => onFailure(error)._evaluate(execution),
        None() => Future.value(Failed(cause)),
      },
    };
  });

  /// Converts success or an all-expected failure to a synchronous [Result].
  ///
  /// The expected error type remains in the Effect so mixed causes can retain
  /// their typed Expected leaves alongside defects or interruption.
  Effect<Result<A, E>, E> result() => Effect._((execution) async {
    final exit = await _evaluate(execution);
    return switch (exit) {
      Succeeded<A, E>(:final value) => Succeeded(Success(value)),
      Failed<A, E>(:final cause) => switch (cause.primaryError) {
        Some<E>(value: final error) => Succeeded(Failure(error)),
        None() => Failed(cause),
      },
    };
  });
}

/// Effectful observation that leaves the observed branch unchanged.
extension EffectObservation<A, E> on Effect<A, E> {
  /// Runs [observe] after success and retains the original value.
  Effect<A, E> tap(Effect<void, E> Function(A value) observe) =>
      flatMap((value) => observe(value).map((_) => value));

  /// Observes the primary expected error without recovering it.
  Effect<A, E> tapError(
    Effect<void, Never> Function(E error) observe,
  ) => Effect._((execution) async {
    final exit = await _evaluate(execution);
    if (exit case Failed<A, E>(:final cause)) {
      final primary = cause.primaryError;
      if (primary case Some<E>(:final value)) {
        return _FailureObservation.run(
          exit,
          Effect.defer(() => observe(value)),
          execution,
        );
      }
    }
    return exit;
  });

  /// Observes the complete cause without recovering it.
  Effect<A, E> tapCause(
    Effect<void, Never> Function(Cause<E> cause) observe,
  ) => Effect._((execution) async {
    final exit = await _evaluate(execution);
    return switch (exit) {
      Succeeded<A, E>() => exit,
      Failed<A, E>(:final cause) => _FailureObservation.run(
        exit,
        Effect.defer(() => observe(cause)),
        execution,
      ),
    };
  });
}

abstract final class _FailureObservation {
  static Future<Exit<A, E>> run<A, E>(
    Exit<A, E> original,
    Effect<void, Never> observer,
    EffectExecution execution,
  ) async {
    final observerExit = await EffectExecution.runProtected(
      observer,
      execution.context,
      execution.clock,
    );
    return switch (observerExit) {
      Succeeded<void, Never>() => original,
      Failed<void, Never>(:final cause) => original.appendCleanup(cause),
    };
  }
}

/// Cleanup operations that run before an Effect returns to its caller.
extension EffectCleanup<A, E> on Effect<A, E> {
  /// Runs [finalizer] after every outcome and preserves both failures.
  Effect<A, E> ensuring(Effect<void, Never> finalizer) => onExit((_) => finalizer);

  /// Runs the Effect returned by [finalizer] after every [Exit].
  Effect<A, E> onExit(
    Effect<void, Never> Function(Exit<A, E> exit) finalizer,
  ) => Effect._((execution) async {
    final exit = await _evaluate(execution);
    late final Effect<void, Never> cleanup;
    try {
      cleanup = finalizer(exit);
    } on Object catch (error, stackTrace) {
      return exit.appendCleanup(Defect(error, stackTrace));
    }
    final cleanupExit = await EffectExecution.runProtected(
      cleanup,
      execution.context,
      execution.clock,
    );
    final cleanupCause = switch (cleanupExit) {
      Succeeded<void, Never>() => null,
      Failed<void, Never>(:final cause) => cause,
    };
    return exit.appendCleanup(cleanupCause);
  });

  /// Runs [finalizer] only when the operation is interrupted.
  Effect<A, E> onCancel(Effect<void, Never> finalizer) => onExit((exit) {
    if (exit case Failed<A, E>(:final cause) when cause.containsInterruption) {
      return finalizer;
    }
    return Effect.succeed<void, Never>(null);
  });
}

/// Uses Effect internals across the runtime's normal libraries.
abstract final class EffectAccess {
  /// Creates an Effect for another Conflux subsystem using runtime execution.
  static Effect<A, E> create<A, E>(
    Future<Exit<A, E>> Function(EffectExecution execution) run,
  ) => Effect._(run);

  /// Evaluates [effect] inside [execution].
  static Future<Exit<A, E>> evaluate<A, E>(
    Effect<A, E> effect,
    EffectExecution execution,
  ) => effect._evaluate(execution);
}
