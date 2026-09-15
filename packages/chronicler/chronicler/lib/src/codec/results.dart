/// Thrown when a model cannot be encoded under the codec contract.
final class ChroniclerEncodingException implements Exception {
  /// Creates an encoding failure with a payload-free [reason].
  const ChroniclerEncodingException(this.reason) : _kind = _EncodingFailureKind.invalid;

  /// Reports that the complete encoded record exceeds its byte limit.
  const ChroniclerEncodingException.recordTooLarge()
    : reason = 'record byte limit exceeded',
      _kind = _EncodingFailureKind.recordTooLarge;

  /// Reports a structural or resource limit, retaining a payload-free [reason].
  const ChroniclerEncodingException.limitExceeded(this.reason)
    : _kind = _EncodingFailureKind.limitExceeded;

  /// The payload-free encoding failure reason.
  final String reason;

  final _EncodingFailureKind _kind;
}

enum _EncodingFailureKind { invalid, limitExceeded, recordTooLarge }

/// Internal classification independent of diagnostic wording.
extension EncodingFailureDetails on ChroniclerEncodingException {
  /// Whether the complete encoded record exceeded its byte limit.
  bool get isRecordTooLarge => _kind == _EncodingFailureKind.recordTooLarge;

  /// The corresponding failure category for untrusted input.
  DecodeFailureReason get decodeReason => switch (_kind) {
    _EncodingFailureKind.invalid => DecodeFailureReason.invalidField,
    _EncodingFailureKind.limitExceeded ||
    _EncodingFailureKind.recordTooLarge => DecodeFailureReason.limitExceeded,
  };
}

/// Result of decoding untrusted Chronicler bytes.
sealed class DecodeResult<T> {
  /// Creates the base type for a decode result.
  const DecodeResult();
}

/// A successfully decoded [value].
final class Decoded<T> extends DecodeResult<T> {
  /// Creates a successful decode result containing [value].
  const Decoded(this.value);

  /// The decoded value.
  final T value;
}

/// A payload-free typed decoding failure.
final class DecodeFailure<T> extends DecodeResult<T> {
  /// Creates a failed decode result with [reason].
  const DecodeFailure(this.reason);

  /// The failure category.
  final DecodeFailureReason reason;
}

/// Stable categories returned when decoding fails.
enum DecodeFailureReason {
  /// Input bytes are not valid UTF-8.
  invalidUtf8,

  /// UTF-8 input is not valid JSON.
  invalidJson,

  /// The declared schema version is unsupported.
  unsupportedVersion,

  /// A required field is missing or invalid.
  invalidField,

  /// Input exceeds a configured count or byte limit.
  limitExceeded,
}
