part of '../../effect.dart';

typedef _EffectRun<A, E> = Future<Exit<A, E>> Function(_Execution execution);

/// A lazy, reusable description of work producing [A] or expected error [E].
final class Effect<A, E> {
  const Effect._(this._run);

  final _EffectRun<A, E> _run;

  Future<Exit<A, E>> _evaluate(_Execution execution) async {
    if (execution.cancellation.isCancelled) {
      return Failed(Interrupted(execution.cancellation.reason));
    }
    try {
      await execution.yieldIfNeeded();
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
  static Effect<A, Never> sync<A>(A Function() callback) => Effect._((_) async {
    try {
      return Succeeded(callback());
    } on Object catch (error, stackTrace) {
      return Failed(Defect(error, stackTrace));
    }
  });

  /// Lazily chooses another effect for each execution.
  static Effect<A, E> defer<A, E>(Effect<A, E> Function() factory) => Effect._((execution) async {
    try {
      return await factory()._evaluate(execution);
    } on Object catch (error, stackTrace) {
      return Failed(Defect(error, stackTrace));
    }
  });

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
      Cause<E> cause = Interrupted(reason);
      if (onCancel != null) {
        try {
          await onCancel();
        } on Object catch (error, stackTrace) {
          cause = Sequential([cause, Defect(error, stackTrace)]);
        }
      }
      complete(Failed(cause));
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
      Effect._((execution) async {
        try {
          return Succeeded(select(execution.context));
        } on Object catch (error, stackTrace) {
          return Failed(Defect(error, stackTrace));
        }
      });

  /// Builds an effect with a callback-local callable binder.
  ///
  /// Every asynchronous bind must be awaited. The builder is valid only while
  /// [body] is active, and every run receives fresh builder state.
  static Effect<A, E> build<A, E>(
    FutureOr<A> Function(EffectBuilder<E> $) body,
  ) => Effect._((execution) async {
    final builder = EffectBuilder<E>._(execution);
    try {
      final value = await body(builder);
      final failure = builder._terminalCause;
      return failure == null ? Succeeded(value) : Failed(failure);
    } on Object catch (error, stackTrace) {
      final failure = builder._terminalCause;
      if (failure != null) return Failed(failure);
      return Failed(Defect(error, stackTrace));
    } finally {
      builder._deactivate();
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
    final child = _Execution(
      context: execution.context,
      scope: Scope._(),
      clock: execution.clock,
      cancellation: execution.cancellation,
    );
    return _runScoped(effect, child);
  });
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
      return _appendCleanup(exit, Defect(error, stackTrace));
    }
    final cleanupExit = await _runProtected(
      cleanup,
      execution.context,
      execution.clock,
    );
    final cleanupCause = switch (cleanupExit) {
      Succeeded<void, Never>() => null,
      Failed<void, Never>(:final cause) => cause,
    };
    return _appendCleanup(exit, cleanupCause);
  });

  /// Runs [finalizer] only when the operation is interrupted.
  Effect<A, E> onCancel(Effect<void, Never> finalizer) => onExit((exit) {
    if (exit case Failed<A, E>(:final cause) when _containsInterruption<E>(cause)) {
      return finalizer;
    }
    return Effect.succeed<void, Never>(null);
  });
}

bool _containsInterruption<E>(Cause<E> cause) => switch (cause) {
  Interrupted<E>() => true,
  Sequential<E>(:final causes) ||
  Parallel<E>(:final causes) => causes.any((cause) => _containsInterruption<E>(cause)),
  Expected<E>() || Defect<E>() => false,
};
