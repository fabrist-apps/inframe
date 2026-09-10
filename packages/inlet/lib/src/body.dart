part of 'inlet.dart';

const int _defaultBodyLimit = 1024 * 1024;

final class _BodyLimitFailure implements Exception {
  const _BodyLimitFailure(this.maxBytes);

  final int maxBytes;
}

final class _Body {
  _Body(Stream<List<int>> source) : _source = source;

  factory _Body.bytes(List<int> bytes) {
    final copied = _copyAndValidateBytes(bytes);
    return _Body(Stream.value(copied)).._knownLength = copied.length;
  }

  final Stream<List<int>> _source;
  Future<Uint8List>? _buffering;
  Uint8List? _cache;
  int? _knownLength;
  bool _closed = false;
  Future<void>? _closeFuture;

  int? get knownLength => _knownLength;

  Future<List<int>> bytes({int maxBytes = _defaultBodyLimit}) async {
    _validateMaxBytes(maxBytes);
    if (_closed) {
      throw StateError('The body is closed.');
    }

    final cached = _cache;
    if (cached != null) {
      _checkLimit(cached.length, maxBytes);
      return Uint8List.fromList(cached);
    }

    final buffering = _buffering ??= _read(maxBytes);
    final bytes = await buffering;
    _checkLimit(bytes.length, maxBytes);
    return Uint8List.fromList(bytes);
  }

  Future<Uint8List> _read(int maxBytes) async {
    final builder = BytesBuilder();
    await for (final chunk in _source) {
      final copied = _copyAndValidateBytes(chunk);
      _checkLimit(builder.length + copied.length, maxBytes);
      builder.add(copied);
    }
    if (_closed) {
      throw StateError('The body was closed while it was being read.');
    }
    final bytes = builder.takeBytes();
    _cache = bytes;
    _knownLength = bytes.length;
    return bytes;
  }

  Future<void> close() {
    final existing = _closeFuture;
    if (existing != null) {
      return existing;
    }
    _closed = true;
    _cache = null;
    return _closeFuture = Future<void>.value();
  }
}

Uint8List _copyAndValidateBytes(List<int> bytes) {
  for (final byte in bytes) {
    if (byte < 0 || byte > 255) {
      throw ArgumentError.value(bytes, 'bytes', 'must contain values from 0 through 255');
    }
  }
  return Uint8List.fromList(bytes);
}

void _validateMaxBytes(int maxBytes) {
  if (maxBytes < 0) {
    throw ArgumentError.value(maxBytes, 'maxBytes', 'must not be negative');
  }
}

void _checkLimit(int byteCount, int maxBytes) {
  if (byteCount > maxBytes) {
    throw _BodyLimitFailure(maxBytes);
  }
}
