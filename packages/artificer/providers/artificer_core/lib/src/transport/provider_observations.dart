// Internal transport support; public contracts live in observations.dart.
// ignore_for_file: public_member_api_docs

import 'package:artificer_core/src/errors.dart';
import 'package:artificer_core/src/generation/generation.dart';
import 'package:artificer_core/src/native.dart';
import 'package:artificer_core/src/observations.dart';
import 'package:conflux/effect.dart';
import 'package:conflux/flow.dart';
import 'package:context/context.dart';

/// Execution-local correlation shared by a model and its transport call.
class ProviderObservations {
  ProviderObservations(this.observer);
  final ProviderObserver? observer;
  final key = ContextKey<ProviderAttempt>('provider attempt');

  Effect<T, AiError> effect<T>(
    Effect<T, AiError> operation, {
    String? providerId,
    String? api,
    String? modelId,
    Usage? Function(T)? usage,
    FinishReason? Function(T)? verdict,
  }) => Effect.defer((context) {
    if (context.read(key) != null) return operation;
    final attempt = ProviderAttempt(
      observer,
      context.read(invocationContextKey),
      providerId,
      api,
      modelId,
    );
    return operation
        .withContext(context.withBinding(key.bind(attempt)))
        .tap(
          (value, _) => Effect.sync((_) {
            final tokens = usage?.call(value);
            if (tokens != null) attempt.usage(tokens);
            final reason = verdict?.call(value);
            if (reason != null) attempt.verdict(reason);
          }),
        )
        .onExit((exit, _) => Effect.sync((_) => attempt.finish(exit)));
  });

  Flow<T, AiError> flow<T>(
    Flow<T, AiError> operation, {
    String? providerId,
    String? api,
    String? modelId,
  }) => Flow.defer((context) {
    if (context.read(key) != null) return operation;
    final attempt = ProviderAttempt(
      observer,
      context.read(invocationContextKey),
      providerId,
      api,
      modelId,
    );
    var complete = false;
    return operation
        .withContext(context.withBinding(key.bind(attempt)))
        .tap(
          (value, _) => Effect.sync((_) {
            if (value case UsageUpdated(:final usage)) attempt.usage(usage);
            if (value case GenerationFinished(:final result)) {
              complete = true;
              if (result.usage case final usage?) attempt.usage(usage);
              attempt.verdict(result.finishReason);
            }
          }),
        )
        .concat(
          Flow.defer((_) {
            complete = true;
            return Flow.empty();
          }),
        )
        .onExit((exit, _) => Effect.sync((_) => attempt.finish(exit, stopped: !complete)));
  });
}

/// Mutable only within one execution; never retained on a model or serialized.
class ProviderAttempt {
  ProviderAttempt(
    this.observer,
    InvocationContext? context,
    this.providerId,
    this.api,
    this.modelId,
  ) : operationId = context?.operationId,
      attemptId = context?.attemptId ?? 'attempt-${++_sequence}';
  static int _sequence = 0;
  final ProviderObserver? observer;
  final String? operationId;
  final String attemptId;
  final String? providerId;
  final String? api;
  final String? modelId;
  bool _started = false;
  bool _finished = false;
  String? _requestId;
  int? _statusCode;
  Usage? _usage;

  void _emit(
    ProviderObservationKind kind, {
    Usage? usage,
    FinishReason? verdict,
    ProviderOutcome? outcome,
  }) {
    observer?.call(
      ProviderObservation(
        kind: kind,
        attemptId: attemptId,
        operationId: operationId,
        providerId: providerId,
        api: api,
        modelId: modelId,
        requestId: _requestId,
        statusCode: _statusCode,
        usage: usage,
        verdict: verdict,
        outcome: outcome,
      ),
    );
  }

  void start() {
    if (_started) throw StateError('One observed invocation may send only one request.');
    _started = true;
    _emit(ProviderObservationKind.started);
  }

  void response(ResponseMetadata metadata) {
    _requestId = metadata.requestId;
    _statusCode = metadata.statusCode;
    _emit(ProviderObservationKind.response);
  }

  void usage(Usage value) {
    if (_usage?.inputTokens == value.inputTokens &&
        _usage?.outputTokens == value.outputTokens &&
        _usage?.totalTokens == value.totalTokens) {
      return;
    }
    _usage = value;
    _emit(ProviderObservationKind.usage, usage: value);
  }

  void verdict(FinishReason value) => _emit(ProviderObservationKind.verdict, verdict: value);

  void finish<T>(Exit<T, AiError> exit, {bool stopped = false}) {
    if (!_started || _finished) return;
    _finished = true;
    final outcome = switch (exit) {
      Succeeded() => stopped ? ProviderOutcome.interrupted : ProviderOutcome.succeeded,
      Failed(:final cause) when _hasDefect(cause) => ProviderOutcome.defect,
      Failed(:final cause) when cause.containsInterruption => ProviderOutcome.interrupted,
      Failed() => ProviderOutcome.failed,
    };
    _emit(ProviderObservationKind.finished, outcome: outcome);
  }

  bool _hasDefect(Cause<AiError> cause) => switch (cause) {
    Defect() => true,
    Sequential(:final causes) || Parallel(:final causes) => causes.any(_hasDefect),
    _ => false,
  };
}
