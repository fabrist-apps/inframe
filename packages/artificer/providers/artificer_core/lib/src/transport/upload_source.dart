import 'dart:async';
import 'dart:typed_data';

/// A repeatable upload body opened only when an upload operation executes.
sealed class UploadSource {
  UploadSource({required String filename, required String mimeType, required this.length})
    : filename = _field(filename, 'filename'),
      mimeType = _field(mimeType, 'mimeType') {
    if (length < 0) throw ArgumentError.value(length, 'length', 'must not be negative');
    if (filename.contains('\n') || filename.contains('\r')) {
      throw ArgumentError.value(filename, 'filename', 'must not contain line breaks');
    }
    if (mimeType.contains('\n') || mimeType.contains('\r')) {
      throw ArgumentError.value(mimeType, 'mimeType', 'must not contain line breaks');
    }
  }

  factory UploadSource.bytes(
    Iterable<int> bytes, {
    required String filename,
    required String mimeType,
  }) = BytesUploadSource;

  factory UploadSource.stream(
    Stream<List<int>> Function() openRead, {
    required int length,
    required String filename,
    required String mimeType,
  }) = StreamUploadSource;

  /// The source filename sent to the provider.
  final String filename;

  /// The media MIME type.
  final String mimeType;

  /// The declared upload byte length.
  final int length;

  /// Opens a fresh byte stream for one upload execution.
  Stream<List<int>> openRead();
}

/// A copied in-memory upload body.
final class BytesUploadSource extends UploadSource {
  /// Creates a [BytesUploadSource].
  factory BytesUploadSource(
    Iterable<int> bytes, {
    required String filename,
    required String mimeType,
  }) {
    final values = bytes.toList(growable: false);
    if (values.any((byte) => byte < 0 || byte > 255)) {
      throw ArgumentError.value(bytes, 'bytes', 'must contain values from 0 through 255');
    }
    final copy = Uint8List.fromList(values).asUnmodifiableView();
    return BytesUploadSource._(copy, filename: filename, mimeType: mimeType);
  }

  BytesUploadSource._(
    this.bytes, {
    required super.filename,
    required super.mimeType,
  }) : super(length: bytes.length);

  /// An immutable copy of the source bytes.
  final List<int> bytes;

  @override
  Stream<List<int>> openRead() => Stream.value(bytes);
}

/// A repeatable stream factory with declared upload metadata.
final class StreamUploadSource extends UploadSource {
  /// Creates a [StreamUploadSource].
  StreamUploadSource(
    this._openRead, {
    required super.length,
    required super.filename,
    required super.mimeType,
  });

  final Stream<List<int>> Function() _openRead;

  @override
  Stream<List<int>> openRead() => _validateLength(_openRead(), length);
}

Stream<List<int>> _validateLength(Stream<List<int>> source, int expected) {
  var actual = 0;
  return source.transform(
    StreamTransformer.fromHandlers(
      handleData: (chunk, sink) {
        if (chunk is! Uint8List && chunk.any((byte) => byte < 0 || byte > 255)) {
          sink
            ..addError(const UploadInvalidByte())
            ..close();
          return;
        }
        actual += chunk.length;
        if (actual > expected) {
          sink
            ..addError(UploadLengthMismatch(expected: expected, actual: actual))
            ..close();
          return;
        }
        sink.add(List.unmodifiable(chunk));
      },
      handleDone: (sink) {
        if (actual != expected) {
          sink.addError(UploadLengthMismatch(expected: expected, actual: actual));
        }
        sink.close();
      },
    ),
  );
}

/// A local upload-source contract failure detected during execution.
sealed class UploadSourceError implements Exception {
  const UploadSourceError(this.message);

  /// The human-readable failure or result message.
  final String message;
}

/// A source emitted an integer outside the byte range.
final class UploadInvalidByte extends UploadSourceError {
  /// Creates an [UploadInvalidByte].
  const UploadInvalidByte() : super('Upload chunks must contain bytes from 0 through 255.');
}

/// The opened source emitted a different byte count than declared.
final class UploadLengthMismatch extends UploadSourceError {
  /// Creates an [UploadLengthMismatch].
  UploadLengthMismatch({required this.expected, required this.actual})
    : super('Expected $expected upload bytes, received $actual.');

  /// The expected.
  final int expected;

  /// The observed byte count.
  final int actual;
}

String _field(String value, String name) {
  if (value.isEmpty) throw ArgumentError.value(value, name, 'must not be empty');
  return value;
}
