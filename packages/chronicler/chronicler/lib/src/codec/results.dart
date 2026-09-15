/// Thrown when a model cannot be encoded under the codec contract.
final class ChroniclerEncodingException implements Exception {
  /// Creates an encoding failure with a payload-free [reason].
  const ChroniclerEncodingException(this.reason);

  /// The payload-free encoding failure reason.
  final String reason;
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
