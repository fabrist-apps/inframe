import 'package:artificer_core/src/generation/generation.dart';
import 'package:context/context.dart';
import 'package:dart_mappable/dart_mappable.dart';

part 'observations.mapper.dart';

/// Optional application identity; it contains no provider credentials.
@MappableClass(generateMethods: GenerateMethods.encode | GenerateMethods.decode)
final class InvocationContext with InvocationContextMappable {
  /// Creates identities to bind at an application execution boundary.
  const InvocationContext({this.operationId, this.attemptId});

  /// Application operation spanning one or more provider calls.
  final String? operationId;

  /// Caller-selected attempt identity; omitted identities are allocated per run.
  final String? attemptId;

  /// Decodes persisted invocation identity.
  static const fromMap = InvocationContextMapper.fromMap;

  /// Decodes persisted invocation identity from JSON.
  static const fromJson = InvocationContextMapper.fromJson;
}

/// Bind [InvocationContext] in the application's Conflux execution Context.
final invocationContextKey = ContextKey<InvocationContext>('artificer invocation');

/// Lifecycle records emitted in order for one actual provider attempt.
@MappableEnum()
enum ProviderObservationKind {
  /// Execution is about to enter the transport.
  started,

  /// HTTP status and provider request identity are available.
  response,

  /// Cumulative token usage is available.
  usage,

  /// The selected generation's semantic finish reason is available.
  verdict,

  /// Exactly one terminal outcome, after operation cleanup.
  finished,
}

/// Complete attempt outcome without potentially sensitive error details.
@MappableEnum()
enum ProviderOutcome {
  /// Decoding and requested normalization completed.
  succeeded,

  /// An expected provider, transport or protocol failure occurred.
  failed,

  /// The caller stopped consumption or interrupted execution.
  interrupted,

  /// An implementation, observer or cleanup defect occurred.
  defect,
}

/// Content-free in-process observation. Raw headers and error payloads are absent.
@MappableClass(generateMethods: GenerateMethods.encode | GenerateMethods.decode)
final class ProviderObservation with ProviderObservationMappable {
  /// Creates one ordered lifecycle record.
  const ProviderObservation({
    required this.kind,
    required this.attemptId,
    this.operationId,
    this.providerId,
    this.api,
    this.modelId,
    this.requestId,
    this.statusCode,
    this.usage,
    this.verdict,
    this.outcome,
  });

  /// Lifecycle stage.
  final ProviderObservationKind kind;

  /// Correlation identity for this execution.
  final String attemptId;

  /// Optional enclosing application operation.
  final String? operationId;

  /// Configured provider identity.
  final String? providerId;

  /// Configured API dialect.
  final String? api;

  /// Requested provider-local model identity.
  final String? modelId;

  /// Native request identity when headers supplied it.
  final String? requestId;

  /// HTTP status, without raw headers.
  final int? statusCode;

  /// Cumulative usage, never request or response content.
  final Usage? usage;

  /// Common semantic completion reason.
  final FinishReason? verdict;

  /// Present only on the terminal record.
  final ProviderOutcome? outcome;

  /// Decodes persisted observation data.
  static const fromMap = ProviderObservationMapper.fromMap;

  /// Decodes persisted observation JSON.
  static const fromJson = ProviderObservationMapper.fromJson;
}

/// Called synchronously in execution order; thrown errors remain Conflux defects.
typedef ProviderObserver = void Function(ProviderObservation observation);
