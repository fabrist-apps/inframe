import 'package:chronicler/src/codec/results.dart';
import 'package:chronicler/src/configuration.dart';
import 'package:chronicler/src/models.dart';
import 'package:chronicler/src/record_validation.dart';
import 'package:conflux/result.dart';

/// Adapts model-owned Val schemas to payload-free codec failures.
final class RecordSchema {
  /// Creates validation with the codec's configured limits.
  const RecordSchema({
    required this.metricOptions,
    required this.maxRecordBytes,
  });

  /// Metric dimension and histogram limits.
  final MetricOptions metricOptions;

  /// Attribute snapshot byte budget.
  final int maxRecordBytes;

  /// Validates through the model schema and translates failures for the codec.
  void validate(ChroniclerRecord record) {
    try {
      // Bound attributes before dart_mappable walks their containers.
      final validator = RecordValidator(maxSnapshotBytes: maxRecordBytes);
      switch (record) {
        case LogRecord():
          validator.snapshotAttributes(record.payload.attributes);
        case ProductEventRecord():
          validator.snapshotAttributes(record.payload.properties);
        case UserPropertiesSetRecord():
          validator.snapshotAttributes(record.payload.properties);
        case SpanRecord():
          validator.snapshotAttributes(record.payload.attributes);
        case ErrorRecord():
          validator.snapshotAttributes(record.payload.attributes);
        case MetricRecord():
          validator.snapshotMetricAttributes(
            record.payload.attributes,
            maxAttributes: metricOptions.maxAttributes,
          );
        case IdentityLinkRecord() || UserPropertiesUnsetRecord():
          break;
      }
      final result = ChroniclerRecord.schema(
        metricOptions: metricOptions,
        maxRecordBytes: maxRecordBytes,
      ).safeParse(record.toMap());
      if (result.isFailure) {
        // Keep validation details out of codec diagnostics.
        throw const ChroniclerEncodingException('record is invalid');
      }
    } on RecordValidationException catch (failure) {
      if (failure.isLimitExceeded) {
        throw ChroniclerEncodingException.limitExceeded(failure.reason);
      }
      throw ChroniclerEncodingException(failure.reason);
    }
  }
}
