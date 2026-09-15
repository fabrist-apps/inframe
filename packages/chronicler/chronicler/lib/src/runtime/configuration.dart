import 'package:chronicler/src/configuration.dart';

/// Validates a required application label.
void validateConfiguredLabel(String value, String setting) {
  if (value.isEmpty) {
    throw ChroniclerConfigurationException(setting, 'is invalid');
  }
}

/// Validates runtime limits and snapshots mutable configuration collections.
ChroniclerOptions validateAndSnapshotOptions(ChroniclerOptions options) {
  final delivery = options.delivery;
  final positiveIntegers = <String, int>{
    'maxPendingRecords': delivery.maxPendingRecords,
    'maxPendingBytes': delivery.maxPendingBytes,
    'maxRecordBytes': delivery.maxRecordBytes,
    'maxBatchRecords': delivery.maxBatchRecords,
    'maxBatchBytes': delivery.maxBatchBytes,
    'maxConcurrentExports': delivery.maxConcurrentExports,
    'maxAttempts': delivery.maxAttempts,
  };
  for (final MapEntry(:key, :value) in positiveIntegers.entries) {
    if (value <= 0) throw ChroniclerConfigurationException(key, 'must be positive');
  }
  final positiveDurations = <String, Duration>{
    'batchInterval': delivery.batchInterval,
    'attemptTimeout': delivery.attemptTimeout,
    'initialRetryDelay': delivery.initialRetryDelay,
    'maxRetryDelay': delivery.maxRetryDelay,
    'flushTimeout': delivery.flushTimeout,
    'closeTimeout': delivery.closeTimeout,
  };
  for (final MapEntry(:key, :value) in positiveDurations.entries) {
    if (value <= Duration.zero) {
      throw ChroniclerConfigurationException(key, 'must be positive');
    }
  }
  if (delivery.maxRetryDelay < delivery.initialRetryDelay) {
    throw const ChroniclerConfigurationException(
      'maxRetryDelay',
      'must be at least initialRetryDelay',
    );
  }
  if (delivery.cleanupReserve < Duration.zero || delivery.cleanupReserve >= delivery.closeTimeout) {
    throw const ChroniclerConfigurationException(
      'cleanupReserve',
      'must be nonnegative and less than closeTimeout',
    );
  }
  if (delivery.maxPendingBytes < delivery.maxRecordBytes) {
    throw const ChroniclerConfigurationException(
      'maxPendingBytes',
      'must fit maxRecordBytes',
    );
  }
  if (delivery.maxBatchBytes < delivery.maxRecordBytes + 32) {
    throw const ChroniclerConfigurationException(
      'maxBatchBytes',
      'must fit maxRecordBytes and batch framing',
    );
  }
  for (final MapEntry(:key, :value) in {
    'logs': options.sampling.logs,
    'events': options.sampling.events,
    'traces': options.sampling.traces,
  }.entries) {
    if (!value.isFinite || value < 0 || value > 1) {
      throw ChroniclerConfigurationException(key, 'sampling rate must be between zero and one');
    }
  }
  if (options.diagnostics.notificationInterval <= Duration.zero) {
    throw const ChroniclerConfigurationException(
      'notificationInterval',
      'must be positive',
    );
  }
  final metrics = options.metrics;
  for (final MapEntry(:key, :value) in {
    'maxInstruments': metrics.maxInstruments,
    'maxSeries': metrics.maxSeries,
    'maxSeriesPerInstrument': metrics.maxSeriesPerInstrument,
    'maxAttributes': metrics.maxAttributes,
    'maxHistogramBoundaries': metrics.maxHistogramBoundaries,
  }.entries) {
    if (value <= 0) throw ChroniclerConfigurationException(key, 'must be positive');
  }
  for (final MapEntry(:key, :value) in {
    'metricInterval': metrics.interval,
    'metricIdleTimeout': metrics.idleTimeout,
  }.entries) {
    if (value <= Duration.zero) {
      throw ChroniclerConfigurationException(key, 'must be positive');
    }
  }
  final terms = <String>{};
  for (final term in options.redaction.fieldTerms) {
    if (term.isEmpty) {
      throw const ChroniclerConfigurationException('fieldTerms', 'must contain nonempty terms');
    }
    terms.add(term.toLowerCase());
  }
  return ChroniclerOptions(
    delivery: delivery,
    sampling: options.sampling,
    redaction: RedactionOptions(
      fieldTerms: Set.unmodifiable(terms),
      beforeRecord: options.redaction.beforeRecord,
    ),
    diagnostics: options.diagnostics,
    metrics: options.metrics,
    tracing: options.tracing,
    enabledSignals: Set.unmodifiable(options.enabledSignals),
  );
}
