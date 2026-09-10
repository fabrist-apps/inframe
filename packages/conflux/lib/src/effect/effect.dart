part of '../../effect.dart';

typedef _EffectRun<A, E> = Future<Exit<A, E>> Function(_Execution execution);

/// A lazy, reusable description of work producing [A] or expected error [E].
final class Effect<A, E> {
  const Effect._(this._run);

  final _EffectRun<A, E> _run;

  Future<Exit<A, E>> _evaluate(_Execution execution) async {
    await execution.yieldIfNeeded();
    return _run(execution);
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
}
