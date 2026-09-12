import 'dart:async';
import 'dart:collection';

import 'package:chronicler/src/codec.dart';
import 'package:chronicler/src/configuration.dart';
import 'package:chronicler/src/diagnostics.dart';
import 'package:chronicler/src/models.dart';
import 'package:chronicler/src/record_validation.dart';
import 'package:chronicler/src/transport.dart';
import 'package:chrono_id/chrono_id.dart';

/// Configured owner of capture and export resources.
final class Chronicler {
  Chronicler({
    required String appId,
    required String release,
    required ChroniclerSource source,
    required ChroniclerExporter exporter,
    String? buildId,
    ChroniclerOptions options = const ChroniclerOptions(),
  }) : _runtime = ChroniclerRuntime.create(
         appId: appId,
         release: release,
         source: source,
         exporter: exporter,
         buildId: buildId,
         options: options,
       );

  static const Set<String> defaultSensitiveFieldTerms =
      ChroniclerOptions.defaultSensitiveFieldTerms;

  final ChroniclerRuntime _runtime;

  ChroniclerRecorder get recorder => ChroniclerRecorder._(_runtime);

  Map<DiagnosticReason, BigInt> get diagnosticCounts => _runtime.diagnosticCounts;
}

/// Borrowed immutable attribution view over one Chronicler runtime.
final class ChroniclerRecorder {
  const ChroniclerRecorder._(this._runtime);

  final ChroniclerRuntime _runtime;

  void recordLog(
    LogSeverity severity,
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?> attributes = const {},
  }) => _runtime.recordLog(
    severity,
    message,
    error: error,
    stackTrace: stackTrace,
    attributes: attributes,
  );
}

final class ChroniclerRuntime {
  ChroniclerRuntime._({
    required this.appId,
    required this.release,
    required this.source,
    required this.exporter,
    required this.buildId,
    required this.options,
  }) : validator = RecordValidator(options.limits),
       codec = ChroniclerCodec(
         limits: options.limits,
         maxRecordBytes: options.delivery.maxRecordBytes,
         maxBatchBytes: options.delivery.maxBatchBytes,
         maxBatchRecords: options.delivery.maxBatchRecords,
       ),
       diagnostics = DiagnosticChannel(options.diagnostics);

  factory ChroniclerRuntime.create({
    required String appId,
    required String release,
    required ChroniclerSource source,
    required ChroniclerExporter exporter,
    required String? buildId,
    required ChroniclerOptions options,
  }) {
    final snapshot = _validateAndSnapshotOptions(options);
    final validator = RecordValidator(snapshot.limits);
    _validateConfiguredLabel(validator, appId, 'appId', snapshot.limits.maxIdBytes);
    _validateConfiguredLabel(validator, release, 'release', snapshot.limits.maxLabelBytes);
    if (buildId != null) {
      _validateConfiguredLabel(validator, buildId, 'buildId', snapshot.limits.maxLabelBytes);
    }
    return ChroniclerRuntime._(
      appId: appId,
      release: release,
      source: source,
      exporter: exporter,
      buildId: buildId,
      options: snapshot,
    );
  }

  final String appId;
  final String release;
  final ChroniclerSource source;
  final ChroniclerExporter exporter;
  final String? buildId;
  final ChroniclerOptions options;
  final RecordValidator validator;
  final ChroniclerCodec codec;
  final DiagnosticChannel diagnostics;
  final _pending = Queue<_PendingRecord>();
  final _active = <_ActiveExport>{};
  var _pendingBytes = 0;
  var _pumpScheduled = false;
  Timer? _batchTimer;

  Map<DiagnosticReason, BigInt> get diagnosticCounts => diagnostics.counts;

  void recordLog(
    LogSeverity severity,
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?> attributes = const {},
  }) {
    if (diagnostics.insideCallback) {
      diagnostics.record(DiagnosticReason.reentrantRecording);
      return;
    }
    try {
      validator.validateString(message, options.limits.maxStringBytes, 'message');
      final snapshot = validator.snapshotAttributes(attributes);
      final details = error == null ? null : _convertError(error, stackTrace);
      final standaloneStack = error == null && stackTrace != null
          ? _safeText(stackTrace.toString, '[Stack trace unavailable]')
          : null;
      if (standaloneStack != null) {
        validator.validateString(
          standaloneStack,
          options.limits.maxStackTraceBytes,
          'stackTrace',
        );
      }
      final record = LogRecord(
        envelope: RecordEnvelope(
          eventId: ChronoID.generate(prefix: 'evt'),
          appId: appId,
          release: release,
          source: source,
          timestamp: DateTime.now().toUtc(),
          buildId: buildId,
        ),
        payload: LogPayload(
          severity: severity,
          message: message,
          attributes: snapshot,
          error: details,
          stackTrace: standaloneStack,
        ),
      );
      final bytes = codec.encodeRecord(record);
      if (bytes.length > options.delivery.maxRecordBytes) {
        diagnostics.record(DiagnosticReason.recordTooLarge);
        return;
      }
      if (_pending.length + _activeRecordCount >= options.delivery.maxPendingRecords ||
          _pendingBytes + bytes.length > options.delivery.maxPendingBytes) {
        diagnostics.record(DiagnosticReason.queueFull);
        return;
      }
      _pending.add(_PendingRecord(record, bytes.length));
      _pendingBytes += bytes.length;
      if (_pending.length >= options.delivery.maxBatchRecords) {
        _schedulePump();
      } else {
        _batchTimer ??= Timer(options.delivery.batchInterval, _pump);
      }
    } on RecordValidationException {
      diagnostics.record(DiagnosticReason.invalidRecord);
    } on Object {
      diagnostics.record(DiagnosticReason.invalidRecord);
    }
  }

  int get _activeRecordCount => _active.fold(0, (count, export) => count + export.records.length);

  ErrorDetails _convertError(Object error, StackTrace? stackTrace) {
    final type = _safeText(() => error.runtimeType.toString(), '[Unknown error type]');
    final message = _safeText(error.toString, '[Error message unavailable]');
    final stack = stackTrace == null
        ? null
        : _safeText(stackTrace.toString, '[Stack trace unavailable]');
    validator
      ..validateString(type, options.limits.maxLabelBytes, 'error type')
      ..validateString(message, options.limits.maxErrorMessageBytes, 'error message');
    if (stack != null) {
      validator.validateString(stack, options.limits.maxStackTraceBytes, 'error stackTrace');
    }
    return ErrorDetails(type: type, message: message, stackTrace: stack);
  }

  String _safeText(String Function() convert, String fallback) {
    try {
      return convert();
    } on Object {
      diagnostics.record(DiagnosticReason.textConversionFailed);
      return fallback;
    }
  }

  void _schedulePump() {
    if (_pumpScheduled) return;
    _pumpScheduled = true;
    Timer.run(() {
      _pumpScheduled = false;
      _pump();
    });
  }

  void _pump() {
    _batchTimer?.cancel();
    _batchTimer = null;
    while (_active.length < options.delivery.maxConcurrentExports && _pending.isNotEmpty) {
      final records = <_PendingRecord>[];
      var batchBytes = 32;
      while (_pending.isNotEmpty && records.length < options.delivery.maxBatchRecords) {
        final next = _pending.first;
        final candidateBytes = batchBytes + next.encodedBytes + (records.isEmpty ? 0 : 1);
        if (candidateBytes > options.delivery.maxBatchBytes) break;
        records.add(_pending.removeFirst());
        batchBytes = candidateBytes;
      }
      if (records.isEmpty) return;
      final active = _ActiveExport(records);
      _active.add(active);
      try {
        final attempt = exporter.export(
          ChroniclerBatch(records.map((pending) => pending.record)),
        );
        active.attempt = attempt;
        unawaited(
          attempt.result.then(
            (_) => _complete(active),
            onError: (Object _, StackTrace _) {
              diagnostics.record(DiagnosticReason.exportFailed);
              _complete(active);
            },
          ),
        );
      } on Object {
        diagnostics.record(DiagnosticReason.exportFailed);
        _complete(active);
      }
    }
    if (_pending.isNotEmpty) {
      _batchTimer ??= Timer(options.delivery.batchInterval, _pump);
    }
  }

  void _complete(_ActiveExport active) {
    if (!_active.remove(active)) return;
    for (final record in active.records) {
      _pendingBytes -= record.encodedBytes;
    }
    _schedulePump();
  }
}

final class _PendingRecord {
  const _PendingRecord(this.record, this.encodedBytes);
  final ChroniclerRecord record;
  final int encodedBytes;
}

final class _ActiveExport {
  _ActiveExport(this.records);
  final List<_PendingRecord> records;
  ExportAttempt? attempt;
}

void _validateConfiguredLabel(
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

ChroniclerOptions _validateAndSnapshotOptions(ChroniclerOptions options) {
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
