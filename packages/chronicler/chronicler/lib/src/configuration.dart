import 'package:chronicler/src/models.dart';

/// Identifies the setting that made Chronicler configuration invalid.
final class ChroniclerConfigurationException implements Exception {
  /// Creates a failure for [setting] with a payload-free [reason].
  const ChroniclerConfigurationException(this.setting, this.reason);

  /// The configuration field or operation that failed validation.
  final String setting;

  /// The payload-free reason the setting is invalid.
  final String reason;

  @override
  String toString() => 'ChroniclerConfigurationException: $setting $reason';
}

/// Bounds queued records, batches, retries, and lifecycle operations.
final class DeliveryOptions {
  /// Creates delivery limits and lifecycle deadlines.
  const DeliveryOptions({
    this.maxPendingRecords = 5000,
    this.maxPendingBytes = 8 * 1024 * 1024,
    this.maxRecordBytes = 64 * 1024,
    this.maxBatchRecords = 100,
    this.maxBatchBytes = 512 * 1024,
    this.batchInterval = const Duration(seconds: 5),
    this.maxConcurrentExports = 1,
    this.attemptTimeout = const Duration(seconds: 10),
    this.maxAttempts = 5,
    this.initialRetryDelay = const Duration(seconds: 1),
    this.maxRetryDelay = const Duration(seconds: 30),
    this.flushTimeout = const Duration(seconds: 10),
    this.closeTimeout = const Duration(seconds: 10),
    this.cleanupReserve = const Duration(seconds: 2),
  });

  /// Maximum queued and in-flight record count.
  final int maxPendingRecords;

  /// Maximum encoded bytes held by queued and in-flight records.
  final int maxPendingBytes;

  /// Maximum bytes in one encoded record.
  final int maxRecordBytes;

  /// Maximum records in one exported batch.
  final int maxBatchRecords;

  /// Maximum bytes in one complete encoded batch.
  final int maxBatchBytes;

  /// Maximum time a new record waits before becoming exportable.
  final Duration batchInterval;

  /// Maximum simultaneous exporter attempts.
  final int maxConcurrentExports;

  /// Deadline for one exporter attempt, including synchronous setup work.
  final Duration attemptTimeout;

  /// Maximum total attempts for one record.
  final int maxAttempts;

  /// Full-jitter ceiling for the first retry.
  final Duration initialRetryDelay;

  /// Maximum full-jitter ceiling for later retries.
  final Duration maxRetryDelay;

  /// Default deadline for a Chronicler flush operation.
  final Duration flushTimeout;

  /// Total deadline for final delivery and exporter cleanup.
  final Duration closeTimeout;

  /// Portion of [closeTimeout] reserved for cleanup.
  final Duration cleanupReserve;
}

/// Bounds record labels, IDs, attributes, and error text.
final class ChroniclerLimits {
  /// Creates schema and caller-data limits.
  const ChroniclerLimits({
    this.maxIdBytes = 256,
    this.maxLabelBytes = 256,
    this.maxMapEntries = 128,
    this.maxListItems = 128,
    this.maxDepth = 5,
    this.maxKeyBytes = 128,
    this.maxStringBytes = 8 * 1024,
    this.maxErrorMessageBytes = 8 * 1024,
    this.maxStackTraceBytes = 16 * 1024,
    this.maxCauses = 4,
  });

  /// Maximum UTF-8 bytes in identifiers.
  final int maxIdBytes;

  /// Maximum UTF-8 bytes in names and labels.
  final int maxLabelBytes;

  /// Maximum entries in each attribute map.
  final int maxMapEntries;

  /// Maximum items in each attribute list.
  final int maxListItems;

  /// Maximum attribute container depth, counting the root map as one.
  final int maxDepth;

  /// Maximum UTF-8 bytes in an attribute key.
  final int maxKeyBytes;

  /// Maximum UTF-8 bytes in a general string value.
  final int maxStringBytes;

  /// Maximum UTF-8 bytes in converted error text.
  final int maxErrorMessageBytes;

  /// Maximum UTF-8 bytes in a stack trace.
  final int maxStackTraceBytes;

  /// Maximum nested causes in one error record.
  final int maxCauses;
}

/// Probability used for independently sampled record kinds.
final class SamplingOptions {
  /// Creates independent sampling probabilities for sampled signals.
  const SamplingOptions({this.logs = 1, this.events = 1, this.traces = 1});

  /// Probability that an eligible log is retained.
  final double logs;

  /// Probability that an eligible product event is retained.
  final double events;

  /// Probability that an eligible span is retained.
  final double traces;
}

/// Synchronous privacy rules applied before records enter the queue.
final class RedactionOptions {
  /// Creates field-name rules and an optional final synchronous hook.
  const RedactionOptions({
    this.fieldTerms = ChroniclerOptions.defaultSensitiveFieldTerms,
    this.beforeRecord,
  });

  /// Case-insensitive substrings that identify sensitive field names.
  final Iterable<String> fieldTerms;

  /// Optional synchronous hook invoked once before a record is buffered.
  final ChroniclerRecord? Function(ChroniclerRecord)? beforeRecord;
}

/// Controls diagnostic callback delivery.
final class DiagnosticOptions {
  /// Creates payload-free diagnostic notification behavior.
  const DiagnosticOptions({
    this.onDiagnostic,
    this.notificationInterval = const Duration(seconds: 1),
  });

  /// Receives rate-limited diagnostic counts outside the recording path.
  final void Function(ChroniclerDiagnostic)? onDiagnostic;

  /// Minimum interval between notifications for the same reason.
  final Duration notificationInterval;
}

/// Reserved base configuration for metric aggregation added by INF-11.
final class MetricOptions {
  /// Creates reserved metric aggregation limits for the metrics package.
  const MetricOptions({
    this.interval = const Duration(seconds: 10),
    this.maxInstruments = 100,
    this.maxSeries = 1000,
    this.maxSeriesPerInstrument = 100,
    this.maxAttributes = 20,
    this.idleTimeout = const Duration(minutes: 5),
    this.maxHistogramBoundaries = 64,
  });

  /// Default metric aggregation interval.
  final Duration interval;

  /// Maximum registered metric instruments.
  final int maxInstruments;

  /// Maximum aggregate series across instruments.
  final int maxSeries;

  /// Maximum aggregate series for one instrument.
  final int maxSeriesPerInstrument;

  /// Maximum attributes retained on one metric measurement.
  final int maxAttributes;

  /// Time after which an inactive metric series may be released.
  final Duration idleTimeout;

  /// Maximum histogram boundaries for one instrument.
  final int maxHistogramBoundaries;
}

/// Reserved base configuration for tracing added by INF-9.
final class TracingOptions {
  /// Creates reserved tracing behavior for the tracing package.
  const TracingOptions({
    this.honorRemoteSampling = true,
    this.propagationEnabled = true,
    this.isCancellation,
  });

  /// Whether a valid remote sampling decision is preserved.
  final bool honorRemoteSampling;

  /// Whether trace context propagation is enabled.
  final bool propagationEnabled;

  /// Optional application classifier for cancellation errors.
  final bool Function(Object error)? isCancellation;
}

/// Immutable setup for a Chronicler runtime.
final class ChroniclerOptions {
  /// Creates an immutable runtime configuration.
  const ChroniclerOptions({
    this.delivery = const DeliveryOptions(),
    this.limits = const ChroniclerLimits(),
    this.sampling = const SamplingOptions(),
    this.redaction = const RedactionOptions(),
    this.diagnostics = const DiagnosticOptions(),
    this.metrics = const MetricOptions(),
    this.tracing = const TracingOptions(),
    this.enabledSignals = const {
      ChroniclerSignal.logs,
      ChroniclerSignal.events,
      ChroniclerSignal.traces,
      ChroniclerSignal.errors,
      ChroniclerSignal.metrics,
    },
  });

  /// Default case-insensitive field-name terms treated as sensitive.
  static const defaultSensitiveFieldTerms = <String>{
    'password',
    'secret',
    'passwd',
    'api_key',
    'apikey',
    'auth',
    'credentials',
    'mysql_pwd',
    'privatekey',
    'private_key',
    'token',
    'bearer',
  };

  /// Queueing, batching, retry, and lifecycle options.
  final DeliveryOptions delivery;

  /// Record schema and caller-data limits.
  final ChroniclerLimits limits;

  /// Sampling probabilities for sampled signal types.
  final SamplingOptions sampling;

  /// Built-in and application-defined redaction behavior.
  final RedactionOptions redaction;

  /// Runtime diagnostic notification behavior.
  final DiagnosticOptions diagnostics;

  /// Reserved metric aggregation options.
  final MetricOptions metrics;

  /// Reserved tracing options.
  final TracingOptions tracing;

  /// Signal types whose capture starts enabled.
  final Set<ChroniclerSignal> enabledSignals;
}

/// A telemetry data type with an independent collection switch.
enum ChroniclerSignal {
  /// Structured log records.
  logs,

  /// Product event records.
  events,

  /// Distributed tracing span records.
  traces,

  /// Error occurrence records.
  errors,

  /// Aggregated metric records.
  metrics,
}

/// A payload-free diagnostic emitted by Chronicler itself.
final class ChroniclerDiagnostic {
  /// Creates a notification for [reason] containing [count] occurrences.
  const ChroniclerDiagnostic({required this.reason, required this.count});

  /// The condition counted by this notification.
  final DiagnosticReason reason;

  /// Occurrences accumulated since the previous notification for [reason].
  final BigInt count;
}

/// Reasons counted by the runtime diagnostic channel.
enum DiagnosticReason {
  /// A record failed schema or caller-data validation.
  invalidRecord,

  /// A final encoded record exceeded its byte limit.
  recordTooLarge,

  /// The pending queue lacked count or byte capacity.
  queueFull,

  /// Collection was disabled for the record's signal.
  collectionDisabled,

  /// Sampling excluded the record.
  sampledOut,

  /// The capture hook returned no record.
  hookDropped,

  /// The capture hook threw.
  hookFailed,

  /// The exporter permanently rejected a record.
  exportRejected,

  /// A record consumed all delivery attempts.
  attemptsExhausted,

  /// Shutdown discarded unresolved work.
  shutdown,

  /// Recording occurred after shutdown started.
  runtimeClosed,

  /// The exporter threw or completed with an error.
  exportFailed,

  /// A per-record exporter result was malformed.
  invalidExportResult,

  /// An exporter attempt exceeded its deadline.
  exportTimedOut,

  /// An exporter cancellation request threw.
  exportCancellationFailed,

  /// Exporter cleanup threw or remained unfinished.
  exportCleanupFailed,

  /// A tracing operation required an active span.
  noActiveSpan,

  /// A span update violated its lifecycle contract.
  invalidSpanUpdate,

  /// A metric measurement was invalid.
  invalidMeasurement,

  /// A metric series capacity was exhausted.
  seriesLimitReached,

  /// Converting application error text failed.
  textConversionFailed,

  /// The application cancellation classifier threw.
  cancellationClassifierFailed,

  /// A callback required to be synchronous returned a future.
  syncCallbackReturnedFuture,

  /// Recording recursively entered the same runtime callback.
  reentrantRecording,
}
