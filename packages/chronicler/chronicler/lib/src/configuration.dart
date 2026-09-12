import 'package:chronicler/src/models.dart';

/// Identifies the setting that made Chronicler configuration invalid.
final class ChroniclerConfigurationException implements Exception {
  const ChroniclerConfigurationException(this.setting, this.reason);

  final String setting;
  final String reason;

  @override
  String toString() => 'ChroniclerConfigurationException: $setting $reason';
}

/// Bounds queued records, batches, retries, and lifecycle operations.
final class DeliveryOptions {
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

  final int maxPendingRecords;
  final int maxPendingBytes;
  final int maxRecordBytes;
  final int maxBatchRecords;
  final int maxBatchBytes;
  final Duration batchInterval;
  final int maxConcurrentExports;
  final Duration attemptTimeout;
  final int maxAttempts;
  final Duration initialRetryDelay;
  final Duration maxRetryDelay;
  final Duration flushTimeout;
  final Duration closeTimeout;
  final Duration cleanupReserve;
}

/// Bounds record labels, IDs, attributes, and error text.
final class ChroniclerLimits {
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

  final int maxIdBytes;
  final int maxLabelBytes;
  final int maxMapEntries;
  final int maxListItems;
  final int maxDepth;
  final int maxKeyBytes;
  final int maxStringBytes;
  final int maxErrorMessageBytes;
  final int maxStackTraceBytes;
  final int maxCauses;
}

/// Probability used for independently sampled record kinds.
final class SamplingOptions {
  const SamplingOptions({this.logs = 1, this.events = 1, this.traces = 1});

  final double logs;
  final double events;
  final double traces;
}

/// Synchronous privacy rules applied before records enter the queue.
final class RedactionOptions {
  const RedactionOptions({
    this.fieldTerms = ChroniclerOptions.defaultSensitiveFieldTerms,
    this.beforeRecord,
  });

  final Iterable<String> fieldTerms;
  final ChroniclerRecord? Function(ChroniclerRecord)? beforeRecord;
}

/// Controls diagnostic callback delivery.
final class DiagnosticOptions {
  const DiagnosticOptions({
    this.onDiagnostic,
    this.notificationInterval = const Duration(seconds: 1),
  });

  final void Function(ChroniclerDiagnostic)? onDiagnostic;
  final Duration notificationInterval;
}

/// Reserved base configuration for metric aggregation added by INF-11.
final class MetricOptions {
  const MetricOptions({
    this.interval = const Duration(seconds: 10),
    this.maxInstruments = 100,
    this.maxSeries = 1000,
    this.maxSeriesPerInstrument = 100,
    this.maxAttributes = 20,
    this.idleTimeout = const Duration(minutes: 5),
    this.maxHistogramBoundaries = 64,
  });

  final Duration interval;
  final int maxInstruments;
  final int maxSeries;
  final int maxSeriesPerInstrument;
  final int maxAttributes;
  final Duration idleTimeout;
  final int maxHistogramBoundaries;
}

/// Reserved base configuration for tracing added by INF-9.
final class TracingOptions {
  const TracingOptions({
    this.honorRemoteSampling = true,
    this.propagationEnabled = true,
    this.isCancellation,
  });

  final bool honorRemoteSampling;
  final bool propagationEnabled;
  final bool Function(Object error)? isCancellation;
}

/// Immutable setup for a Chronicler runtime.
final class ChroniclerOptions {
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

  final DeliveryOptions delivery;
  final ChroniclerLimits limits;
  final SamplingOptions sampling;
  final RedactionOptions redaction;
  final DiagnosticOptions diagnostics;
  final MetricOptions metrics;
  final TracingOptions tracing;
  final Set<ChroniclerSignal> enabledSignals;
}

/// A telemetry data type with an independent collection switch.
enum ChroniclerSignal { logs, events, traces, errors, metrics }

/// A payload-free diagnostic emitted by Chronicler itself.
final class ChroniclerDiagnostic {
  const ChroniclerDiagnostic({required this.reason, required this.count});

  final DiagnosticReason reason;
  final BigInt count;
}

/// Reasons counted by the runtime diagnostic channel.
enum DiagnosticReason {
  invalidRecord,
  recordTooLarge,
  queueFull,
  collectionDisabled,
  sampledOut,
  hookDropped,
  hookFailed,
  exportRejected,
  attemptsExhausted,
  shutdown,
  runtimeClosed,
  exportFailed,
  invalidExportResult,
  exportTimedOut,
  exportCancellationFailed,
  exportCleanupFailed,
  noActiveSpan,
  invalidSpanUpdate,
  invalidMeasurement,
  seriesLimitReached,
  textConversionFailed,
  cancellationClassifierFailed,
  syncCallbackReturnedFuture,
  reentrantRecording,
}
