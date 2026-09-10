import 'dart:async';

import 'package:conflux/non_empty_list.dart';
import 'package:conflux/option.dart';
import 'package:conflux/result.dart';
import 'package:conflux/src/effect/builder.dart';
import 'package:conflux/src/effect/cause.dart';
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

sealed class _ValueSlot<A> {
  const _ValueSlot();
}

final class _EmptySlot<A> extends _ValueSlot<A> {
  const _EmptySlot();
}

final class _FilledSlot<A> extends _ValueSlot<A> {
  const _FilledSlot(this.value);

  final A value;
}

final class _IndexedExit<A, E> {
  const _IndexedExit(this.index, this.exit);

  final int index;
  final Exit<A, E> exit;
}

abstract final class _EffectCollection {
  static Future<Exit<List<A>, E>> run<A, E>(
    List<Effect<A, E>> effects,
    EffectExecution execution,
    int concurrency,
  ) async {
    if (effects.isEmpty) return Succeeded(List.unmodifiable(const []));

    final slots = List<_ValueSlot<A>>.filled(
      effects.length,
      const _EmptySlot(),
    );
    final active = <int, Fiber<A, E>>{};
    var nextIndex = 0;

    void startNext() {
      final index = nextIndex++;
      active[index] = ScopeAccess.fork(execution.scope, effects[index], execution);
    }

    while (nextIndex < effects.length && active.length < concurrency) {
      startNext();
    }

    while (active.isNotEmpty) {
      final completed = await Future.any(
        active.entries.map((entry) async {
          return _IndexedExit(entry.key, await entry.value.join());
        }),
      );
      active.remove(completed.index);

      switch (completed.exit) {
        case Succeeded<A, E>(:final value):
          slots[completed.index] = _FilledSlot(value);
          if (nextIndex < effects.length) startNext();
        case Failed<A, E>(:final cause):
          final cleanupFailures = <MapEntry<int, Cause<Never>>>[];
          await Future.wait(
            active.entries.map((entry) async {
              final loser = await entry.value.interrupt(const _CollectionStopped());
              if (loser case Failed<A, E>(:final cause)) {
                final cleanup = cause.defectsOnly;
                if (cleanup != null) {
                  cleanupFailures.add(MapEntry(entry.key, cleanup));
                }
              }
            }),
          );
          cleanupFailures.sort((left, right) => left.key.compareTo(right.key));
          if (cleanupFailures.isEmpty) return Failed(cause);
          final concurrentCleanup = CauseGroup.parallel(
            cleanupFailures.map((entry) => entry.value),
          )!;
          return Failed(Sequential([cause, concurrentCleanup]));
      }
    }

    final values = slots.map((slot) {
      return switch (slot) {
        _FilledSlot<A>(:final value) => value,
        _EmptySlot<A>() => throw StateError('Collection completed without a value.'),
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
    final active = <int, Fiber<A, E>>{
      for (var index = 0; index < effects.length; index += 1)
        index: ScopeAccess.fork(execution.scope, effects[index], execution),
    };
    final failures = List<Cause<E>?>.filled(effects.length, null);

    while (active.isNotEmpty) {
      final completed = await Future.any(
        active.entries.map((entry) async {
          return _IndexedExit(entry.key, await entry.value.join());
        }),
      );
      active.remove(completed.index);

      switch (completed.exit) {
        case Failed<A, E>(:final cause):
          failures[completed.index] = cause;
        case Succeeded<A, E>(:final value):
          final cleanupFailures = <MapEntry<int, Cause<Never>>>[];
          await Future.wait(
            active.entries.map((entry) async {
              final loser = await entry.value.interrupt(const _RaceLost());
              if (loser case Failed<A, E>(:final cause)) {
                final cleanup = cause.defectsOnly;
                if (cleanup != null) {
                  cleanupFailures.add(MapEntry(entry.key, cleanup));
                }
              }
            }),
          );
          if (cleanupFailures.isEmpty) return Succeeded(value);
          cleanupFailures.sort((left, right) => left.key.compareTo(right.key));
          return Failed(
            CauseGroup.parallel(
              cleanupFailures.map((entry) => entry.value),
            )!,
          );
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
  /// Evaluates [effect] inside [execution].
  static Future<Exit<A, E>> evaluate<A, E>(
    Effect<A, E> effect,
    EffectExecution execution,
  ) => effect._evaluate(execution);
}
