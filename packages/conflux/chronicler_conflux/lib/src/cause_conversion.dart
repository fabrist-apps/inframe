import 'dart:convert';

import 'package:conflux/effect.dart';

const int _maxNodes = 64;
const int _maxMetadataBytes = 32 * 1024;
const int _maxTextBytes = 4 * 1024;

/// Explicit Chronicler error-capture input derived from a Conflux Cause.
final class ChroniclerErrorInput {
  /// Creates immutable input for explicit Chronicler error capture.
  const ChroniclerErrorInput({
    required this.error,
    required this.stackTrace,
    required this.attributes,
  });

  /// Non-null summary suitable for the captured error value.
  final ConfluxFailure error;

  /// First genuine defect stack, when the Cause contains a defect.
  final StackTrace? stackTrace;

  /// Bounded structural metadata retaining the Cause tree.
  final Map<String, Object?> attributes;
}

/// Non-null summary used as the root of an explicit Chronicler error capture.
final class ConfluxFailure implements Exception {
  const ConfluxFailure._(this.kind);

  /// Kind of the root Conflux Cause node.
  final String kind;

  @override
  String toString() => 'Conflux Effect failed with a $kind cause.';
}

/// Converts complete Conflux failure trees without recording an occurrence.
extension ConfluxCauseConversion<E> on Cause<E> {
  /// Returns bounded input for an explicit `context.errors.capture` call.
  ChroniclerErrorInput toChroniclerError() => _CauseConverter<E>().convert(this);
}

final class _CauseConverter<E> {
  final _nodes = <Map<String, Object?>>[];
  var _nodesOmitted = false;
  var _textTruncated = false;
  var _textUnavailable = false;
  StackTrace? _firstDefectStack;

  ChroniclerErrorInput convert(Cause<E> cause) {
    final pending = <_PendingNode<E>>[_PendingNode(cause, null)];
    while (pending.isNotEmpty) {
      if (_nodes.length == _maxNodes) {
        _nodesOmitted = true;
        break;
      }
      final current = pending.removeLast();
      final index = _nodes.length;
      final node = _node(current.cause, current.parent);
      if (!_fits(node)) {
        _nodesOmitted = true;
        break;
      }
      _nodes.add(Map.unmodifiable(node));
      switch (current.cause) {
        case Sequential<E>(:final causes) || Parallel<E>(:final causes):
          for (final child in causes.reversed) {
            pending.add(_PendingNode(child, index));
          }
        case Expected<E>() || Defect<E>() || Interrupted<E>():
          break;
      }
    }

    final metadata = Map<String, Object?>.unmodifiable(_metadata(_nodes));
    return ChroniclerErrorInput(
      error: ConfluxFailure._(_kind(cause)),
      stackTrace: _firstDefectStack,
      attributes: Map.unmodifiable({'conflux.cause': metadata}),
    );
  }

  Map<String, Object?> _node(Cause<E> cause, int? parent) {
    final node = <String, Object?>{'parent': parent, 'kind': _kind(cause)};
    switch (cause) {
      case Expected<E>(:final error):
        _addValue(node, error, label: 'error');
      case Defect<E>(:final error, :final stackTrace):
        _firstDefectStack ??= stackTrace;
        _addValue(node, error, label: 'error');
        _addText(node, 'stackTrace', _safeStack(stackTrace));
      case Interrupted<E>(:final reason):
        _addValue(node, reason, label: 'reason');
      case Sequential<E>() || Parallel<E>():
        break;
    }
    return node;
  }

  void _addValue(
    Map<String, Object?> node,
    Object? value, {
    required String label,
  }) {
    node['isNull'] = value == null;
    if (value == null) {
      node['type'] = 'Null';
      node['message'] = 'null';
      return;
    }
    final displayLabel = label == 'error' ? 'Error' : 'Reason';
    _addText(
      node,
      'type',
      _safeText(() => value.runtimeType.toString(), '[Unknown ${label.toLowerCase()} type]'),
    );
    _addText(node, 'message', _safeText(value.toString, '[$displayLabel message unavailable]'));
  }

  void _addText(Map<String, Object?> node, String key, _TextSnapshot text) {
    node[key] = text.value;
    if (text.truncated) {
      node['textTruncated'] = true;
      _textTruncated = true;
    }
    if (text.unavailable) {
      node['textUnavailable'] = true;
      _textUnavailable = true;
    }
  }

  _TextSnapshot _safeStack(StackTrace stackTrace) =>
      _safeText(stackTrace.toString, '[Stack trace unavailable]');

  _TextSnapshot _safeText(String Function() convert, String fallback) {
    try {
      return _truncate(convert());
    } on Object {
      return _TextSnapshot(fallback, unavailable: true);
    }
  }

  _TextSnapshot _truncate(String value) {
    if (utf8.encode(value).length <= _maxTextBytes) return _TextSnapshot(value);
    const suffix = '…';
    final buffer = StringBuffer();
    var bytes = 0;
    for (final rune in value.runes) {
      final text = String.fromCharCode(rune);
      final runeBytes = utf8.encode(text).length;
      if (bytes + runeBytes + utf8.encode(suffix).length > _maxTextBytes) break;
      buffer.write(text);
      bytes += runeBytes;
    }
    return _TextSnapshot('$buffer$suffix', truncated: true);
  }

  bool _fits(Map<String, Object?> node) {
    final proposed = [..._nodes, node];
    return utf8.encode(jsonEncode(_metadata(proposed))).length <= _maxMetadataBytes;
  }

  Map<String, Object?> _metadata(List<Map<String, Object?>> nodes) => {
    'version': 1,
    'nodes': nodes,
    'nodesOmitted': _nodesOmitted,
    'textTruncated': _textTruncated,
    'textUnavailable': _textUnavailable,
  };
}

String _kind<E>(Cause<E> cause) => switch (cause) {
  Expected<E>() => 'expected',
  Defect<E>() => 'defect',
  Interrupted<E>() => 'interrupted',
  Sequential<E>() => 'sequential',
  Parallel<E>() => 'parallel',
};

final class _PendingNode<E> {
  const _PendingNode(this.cause, this.parent);

  final Cause<E> cause;
  final int? parent;
}

final class _TextSnapshot {
  const _TextSnapshot(
    this.value, {
    this.truncated = false,
    this.unavailable = false,
  });

  final String value;
  final bool truncated;
  final bool unavailable;
}
