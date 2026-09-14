/// An expected failure to construct or change a Moment.
final class MomentError {
  /// Creates a diagnostic, optionally identifying the invalid field.
  const MomentError(this.kind, this.message, {this.field});

  /// The category callers can match without parsing [message].
  final MomentErrorKind kind;

  /// A human-readable explanation.
  final String message;

  /// The offending input field, when known.
  final String? field;

  @override
  String toString() => 'MomentError(${kind.name}: $message)';
}

/// Expected date-time validation and resolution failures.
enum MomentErrorKind {
  /// The timestamp does not follow the supported ISO grammar.
  invalidFormat,

  /// A calendar field is invalid, rather than normalized.
  invalidField,

  /// A date-time or elapsed difference exceeds its native representable range.
  outOfRange,

  /// An offset has fractional seconds or magnitude at least 24 hours.
  invalidOffset,

  /// The caller has not loaded an IANA database.
  timezoneNotInitialized,

  /// The loaded database does not contain the requested identifier.
  unknownTimeZone,

  /// Local fields lie in a transition gap.
  nonexistentLocalTime,

  /// Local fields identify multiple instants.
  ambiguousLocalTime,
}
