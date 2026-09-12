import 'dart:convert';
import 'dart:typed_data';

import 'package:chronicler/src/configuration.dart';
import 'package:chronicler/src/models.dart';

final class ChroniclerEncodingException implements Exception {
  const ChroniclerEncodingException(this.reason);
  final String reason;
}

/// Canonical compact UTF-8 JSON encoder used for delivery accounting.
final class ChroniclerCodec {
  const ChroniclerCodec({this.limits = const ChroniclerLimits()});

  final ChroniclerLimits limits;

  Uint8List encodeRecord(ChroniclerRecord record) =>
      Uint8List.fromList(utf8.encode(jsonEncode(_sortObject(_recordMap(record)))));

  Uint8List encodeBatch(ChroniclerBatch batch) => Uint8List.fromList(
    utf8.encode(
      jsonEncode(
        _sortObject({
          'schemaVersion': 1,
          'records': batch.records.map(_recordMap).toList(growable: false),
        }),
      ),
    ),
  );

  Map<String, Object?> _recordMap(ChroniclerRecord record) {
    return switch (record) {
      LogRecord() => <String, Object?>{
        'schemaVersion': 1,
        'eventId': record.envelope.eventId,
        'appId': record.envelope.appId,
        'release': record.envelope.release,
        'source': record.envelope.source.name,
        'timestamp': _formatTimestamp(record.envelope.timestamp),
        'buildId': ?record.envelope.buildId,
        'userId': ?record.envelope.userId,
        'anonymousId': ?record.envelope.anonymousId,
        'sessionId': ?record.envelope.sessionId,
        'traceId': ?record.envelope.traceId,
        'spanId': ?record.envelope.spanId,
        'parentSpanId': ?record.envelope.parentSpanId,
        'kind': record.kind,
        'payload': {
          'severity': record.payload.severity.name,
          'message': record.payload.message,
          'attributes': record.payload.attributes,
          if (record.payload.error case final error?)
            'error': {
              'type': error.type,
              'message': error.message,
              'stackTrace': ?error.stackTrace,
            },
          'stackTrace': ?record.payload.stackTrace,
        },
      },
    };
  }

  Object? _sortObject(Object? value) => switch (value) {
    Map<Object?, Object?>() => <String, Object?>{
      for (final key in value.keys.cast<String>().toList()..sort()) key: _sortObject(value[key]),
    },
    List<Object?>() => value.map(_sortObject).toList(growable: false),
    _ => value,
  };

  String _formatTimestamp(DateTime value) {
    final utc = value.toUtc();
    final base = utc.toIso8601String();
    final separator = base.indexOf('.');
    final seconds = separator == -1
        ? base.substring(0, base.length - 1)
        : base.substring(0, separator);
    final micros = utc.millisecond * 1000 + utc.microsecond;
    return '$seconds.${micros.toString().padLeft(6, '0')}Z';
  }
}
