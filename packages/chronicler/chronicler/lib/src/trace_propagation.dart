import 'dart:convert';

/// Validated W3C parent metadata accepted at an explicit trace boundary.
final class RemoteTraceParent {
  const RemoteTraceParent._({
    required this.traceId,
    required this.parentSpanId,
    required this.sampled,
    required this.tracestate,
  });

  /// Incoming 16-byte trace identifier as lowercase hexadecimal text.
  final String traceId;

  /// Incoming 8-byte parent identifier as lowercase hexadecimal text.
  final String parentSpanId;

  /// Whether the upstream trace was sampled.
  final bool sampled;

  /// Valid ordered vendor entries retained for propagation.
  final List<String> tracestate;
}

/// Decodes bounded W3C Trace Context metadata from carrier headers.
abstract final class TracePropagation {
  static final _traceId = RegExp(r'^[0-9a-f]{32}$');
  static final _spanId = RegExp(r'^[0-9a-f]{16}$');
  static final _byte = RegExp(r'^[0-9a-f]{2}$');
  static final _simpleKey = RegExp(r'^[a-z][a-z0-9_\-*/]{0,255}$');
  static final _tenantKey = RegExp(
    r'^[a-z0-9][a-z0-9_\-*/]{0,240}@[a-z][a-z0-9_\-*/]{0,13}$',
  );

  /// Returns a validated remote parent, or null when traceparent is invalid.
  static RemoteTraceParent? extract(Map<String, String> headers) {
    final traceparent = _combinedHeader(headers, 'traceparent');
    if (traceparent == null || utf8.encode(traceparent).length > 1024) return null;
    if (traceparent.contains(',')) return null;
    final fields = traceparent.split('-');
    if (fields.length < 4) return null;
    final version = fields[0];
    if (!_byte.hasMatch(version) || version == 'ff') return null;
    if (version == '00' && (fields.length != 4 || traceparent.length != 55)) return null;
    if (version != '00' && traceparent.length < 55) {
      return null;
    }
    final traceId = fields[1];
    final parentSpanId = fields[2];
    final flags = fields[3];
    if (!_traceId.hasMatch(traceId) || _allZero(traceId)) return null;
    if (!_spanId.hasMatch(parentSpanId) || _allZero(parentSpanId)) return null;
    if (!_byte.hasMatch(flags)) return null;
    final state = _decodeTracestate(_combinedHeader(headers, 'tracestate'));
    return RemoteTraceParent._(
      traceId: traceId,
      parentSpanId: parentSpanId,
      sampled: int.parse(flags, radix: 16).isOdd,
      tracestate: List.unmodifiable(state),
    );
  }

  static String? _combinedHeader(Map<String, String> headers, String name) {
    final values = <String>[];
    for (final MapEntry(:key, :value) in headers.entries) {
      if (key.toLowerCase() == name) values.add(value);
    }
    return values.isEmpty ? null : values.join(',');
  }

  static List<String> _decodeTracestate(String? value) {
    if (value == null || value.isEmpty) return const [];
    if (utf8.encode(value).length > 8192) return const [];
    final entries = value
        .split(',')
        .map((entry) => entry.trim())
        .where((entry) => entry.isNotEmpty)
        .toList();
    if (entries.length > 32) return const [];
    final keys = <String>{};
    for (final entry in entries) {
      final separator = entry.indexOf('=');
      if (separator <= 0) return const [];
      final key = entry.substring(0, separator);
      final stateValue = entry.substring(separator + 1);
      if ((!_simpleKey.hasMatch(key) && !_tenantKey.hasMatch(key)) ||
          !keys.add(key) ||
          !_validStateValue(stateValue)) {
        return const [];
      }
    }
    final retained = [...entries];
    while (_encodedStateBytes(retained) > 512) {
      final oversized = retained.lastIndexWhere((entry) => utf8.encode(entry).length > 128);
      retained.removeAt(oversized < 0 ? retained.length - 1 : oversized);
    }
    return retained;
  }

  static int _encodedStateBytes(List<String> entries) =>
      entries.fold(0, (bytes, entry) => bytes + utf8.encode(entry).length) +
      (entries.isEmpty ? 0 : entries.length - 1);

  static bool _validStateValue(String value) {
    if (value.isEmpty || value.length > 256 || value.endsWith(' ')) return false;
    for (final unit in value.codeUnits) {
      if (unit < 0x20 || unit > 0x7e || unit == 0x2c || unit == 0x3d) return false;
    }
    return true;
  }

  static bool _allZero(String value) => value.codeUnits.every((unit) => unit == 0x30);
}
