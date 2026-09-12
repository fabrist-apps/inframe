import 'dart:math';

import 'package:chronicler/src/configuration.dart';
import 'package:chronicler/src/record_validation.dart';

/// Validates a required application label against its configured byte bound.
void validateConfiguredLabel(
  RecordValidator validator,
  String value,
  String setting,
  int maxBytes,
) {
  try {
    if (value.isEmpty) throw const RecordValidationException('must be nonempty');
    validator.validateString(value, maxBytes, setting);
  } on RecordValidationException {
    throw ChroniclerConfigurationException(setting, 'is invalid');
  }
}

/// Creates and probes secure randomness before accepting runtime ownership.
Random createSecureRandom(Random Function()? factory) {
  try {
    final random = (factory?.call() ?? Random.secure())..nextInt(256);
    return random;
  } on Object {
    throw const ChroniclerConfigurationException('secureRandom', 'is unavailable');
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
  final limits = options.limits;
  final limitValues = <String, int>{
    'maxIdBytes': limits.maxIdBytes,
    'maxLabelBytes': limits.maxLabelBytes,
    'maxMapEntries': limits.maxMapEntries,
    'maxListItems': limits.maxListItems,
    'maxDepth': limits.maxDepth,
    'maxKeyBytes': limits.maxKeyBytes,
    'maxStringBytes': limits.maxStringBytes,
    'maxErrorMessageBytes': limits.maxErrorMessageBytes,
    'maxStackTraceBytes': limits.maxStackTraceBytes,
  };
  for (final MapEntry(:key, :value) in limitValues.entries) {
    if (value <= 0) throw ChroniclerConfigurationException(key, 'must be positive');
  }
  if (limits.maxCauses < 0) {
    throw const ChroniclerConfigurationException('maxCauses', 'must be nonnegative');
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
    limits: limits,
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
