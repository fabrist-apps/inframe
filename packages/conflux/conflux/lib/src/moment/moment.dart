// All value fields are final; no annotation-only runtime dependency is needed.
// ignore_for_file: avoid_equals_and_hash_code_on_mutable_classes

import 'package:ack/ack.dart';
import 'package:conflux/result.dart';
import 'package:conflux/src/moment/local_resolution.dart';
import 'package:conflux/src/moment/moment_error.dart';
import 'package:conflux/src/moment/moment_parts.dart';
import 'package:conflux/src/moment/parsing.dart';
import 'package:conflux/src/moment/time_zone.dart';

/// An immutable instant with exact microseconds and explicit zone identity.
///
/// Equality includes representation and zone; [compareTo] compares instants only.
/// UTC and derived local fields use Dart DateTime’s native representable range.
sealed class Moment implements Comparable<Moment> {
  const Moment._(this.microsecondsSinceEpoch);

  /// Validates signed epoch microseconds against Dart DateTime's inclusive bounds.
  static AckSchema<int, int> epochMicrosecondsSchema() =>
      Ack.integer().min(minimumMomentMicros).max(maximumMomentMicros);

  /// Constructs UTC from signed microseconds since the Unix epoch.
  static Result<UtcMoment, MomentError> fromEpochMicroseconds(int value) {
    if (epochMicrosecondsSchema().safeParse(value).isFail) {
      return const Failure(MomentError.range);
    }

    return Success(UtcMoment._(value));
  }

  /// Preserves the native instant without inferring a device timezone identity.
  static Result<UtcMoment, MomentError> fromDateTime(DateTime value) =>
      fromEpochMicroseconds(value.microsecondsSinceEpoch);

  /// Validates UTC fields without normalizing calendar overflow.
  static Result<UtcMoment, MomentError> utc(MomentParts parts) {
    final error = parts.validate();
    if (error != null) return Failure(error);

    return fromEpochMicroseconds(parts.encode().microsecondsSinceEpoch);
  }

  /// Resolves supplied local fields with an explicit gap/overlap policy.
  static Result<ZonedMoment, MomentError> zoned(
    MomentParts parts,
    TimeZone zone, {
    required Disambiguation disambiguation,
  }) => zone
      .resolveLocal(parts, disambiguation)
      .flatMap((micros) => fromEpochMicroseconds(micros).flatMap((utc) => utc.setZone(zone)));

  /// Parses strict ISO timestamps with 1–6 fractional digits and a required offset.
  ///
  /// `Z` yields UTC; numeric offsets retain fixed identity, including negative zero.
  /// Years use Dart's ISO spelling: `0000`, `-0001`, or signed six digits
  /// outside -9999–9999, such as `+010000`. Noncanonical year spellings,
  /// whitespace, leap seconds, calendar overflow and offset-free input fail.
  static Result<Moment, MomentError> parse(String input) => parseTimestamp(input).flatMap((parsed) {
    final wallMicros = parsed.parts.encode().microsecondsSinceEpoch;
    final offset = parsed.offset;
    if (offset == null) return fromEpochMicroseconds(wallMicros);

    return TimeZone.fixed(offset).flatMap(
      (zone) =>
          fromEpochMicroseconds(wallMicros - offset.inMicroseconds)
              .flatMap((utc) => utc.setZone(zone)),
    );
  });

  /// Selects the earlier instant, retaining [a] on ties.
  static Moment min(Moment a, Moment b) => a.compareTo(b) <= 0 ? a : b;

  /// Selects the later instant, retaining [a] on ties.
  static Moment max(Moment a, Moment b) => a.compareTo(b) >= 0 ? a : b;

  /// Signed microseconds since the Unix epoch.
  final int microsecondsSinceEpoch;

  /// Whether calendar fields are exposed in UTC representation.
  bool get isUtc => this is UtcMoment;

  /// Whether this instant retains an explicit zone descriptor.
  bool get isZoned => this is ZonedMoment;

  /// The actual offset east of UTC at this instant.
  Duration get offset => switch (this) {
    UtcMoment() => Duration.zero,
    ZonedMoment(:final zone) => zone.offsetAt(microsecondsSinceEpoch),
  };

  /// Calendar fields in the retained zone, or UTC for [UtcMoment].
  MomentParts get parts => DateTime.fromMicrosecondsSinceEpoch(
    microsecondsSinceEpoch + offset.inMicroseconds,
    isUtc: true,
  ).toMomentParts();

  /// UTC calendar fields independent of the retained zone.
  MomentParts get partsUtc => toDateTimeUtc().toMomentParts();

  /// Replaces all local fields, preserving the representation and zone.
  ///
  /// Use `parts.copyWith(...)` for partial changes. Unlike [setZone], this
  /// resolves newly supplied clock fields and requires a gap/overlap policy.
  Result<Moment, MomentError> withParts(
    MomentParts parts, {
    required Disambiguation disambiguation,
  }) => switch (this) {
    UtcMoment() => utc(parts),
    ZonedMoment(:final zone) => zoned(parts, zone, disambiguation: disambiguation),
  };

  /// Returns the same instant in UTC representation.
  UtcMoment toUtc() => switch (this) {
    final UtcMoment value => value,
    ZonedMoment() => UtcMoment._(microsecondsSinceEpoch),
  };

  /// Preserves the instant and derives local fields in [zone], validating their range.
  ///
  /// This does not reinterpret clock fields and requires no DST policy.
  Result<ZonedMoment, MomentError> setZone(TimeZone zone) {
    final local = microsecondsSinceEpoch + zone.offsetAt(microsecondsSinceEpoch).inMicroseconds;
    if (!inMomentRange(local)) return const Failure(MomentError.range);

    return Success(ZonedMoment._(microsecondsSinceEpoch, zone));
  }

  /// Converts explicitly to a native UTC date-time, preserving microseconds.
  DateTime toDateTimeUtc() =>
      DateTime.fromMicrosecondsSinceEpoch(microsecondsSinceEpoch, isUtc: true);

  @override
  int compareTo(Moment other) => microsecondsSinceEpoch.compareTo(other.microsecondsSinceEpoch);

  /// Whether this instant precedes [other], independent of zone identity.
  bool isBefore(Moment other) => compareTo(other) < 0;

  /// Whether this instant follows [other], independent of zone identity.
  bool isAfter(Moment other) => compareTo(other) > 0;

  /// Whether both values represent the same instant, even if unequal.
  bool isAtSameMomentAs(Moment other) => compareTo(other) == 0;

  /// Signed elapsed time: this instant minus [other].
  ///
  /// Returns outOfRange when the difference exceeds Dart Duration's signed
  /// 64-bit microseconds, even though both date-times are representable.
  Result<Duration, MomentError> difference(Moment other) {
    final micros = BigInt.from(microsecondsSinceEpoch) - BigInt.from(other.microsecondsSinceEpoch);
    if (micros < -(BigInt.one << 63) || micros > (BigInt.one << 63) - BigInt.one) {
      return const Failure(
        MomentError(
          MomentErrorKind.outOfRange,
          'The elapsed difference is outside Dart Duration’s range.',
        ),
      );
    }

    return Success(Duration(microseconds: micros.toInt()));
  }

  /// Inclusive instant bounds; inverted bounds contain no values.
  bool isBetween(Moment start, Moment end) => !isBefore(start) && !isAfter(end);

  /// Adds signed elapsed microseconds, retaining the representation and zone.
  Result<Moment, MomentError> addDuration(Duration duration) =>
      _shift(duration.inMicroseconds, subtract: false);

  /// Subtracts signed elapsed microseconds, retaining the representation and zone.
  Result<Moment, MomentError> subtractDuration(Duration duration) =>
      _shift(duration.inMicroseconds, subtract: true);

  Result<Moment, MomentError> _shift(int amount, {required bool subtract}) {
    // BigInt intermediates prevent overflow across the full native date range.
    final delta = BigInt.from(amount);
    final shifted = BigInt.from(microsecondsSinceEpoch) + (subtract ? -delta : delta);
    if (shifted < BigInt.from(minimumMomentMicros) || shifted > BigInt.from(maximumMomentMicros)) {
      return const Failure(MomentError.range);
    }

    final micros = shifted.toInt();
    final utc = UtcMoment._(micros);

    return switch (this) {
      UtcMoment() => Success(utc),
      ZonedMoment(:final zone) => utc.setZone(zone),
    };
  }

  /// UTC timestamp with six fractional digits and `Z`.
  String formatIso() => '${partsUtc.formatTimestamp()}Z';

  /// Local calendar date with the same ISO year spelling as [formatIso].
  String formatIsoDate() => parts.formatTimestamp(dateOnly: true);

  /// Local timestamp and numeric offset, including historical nonzero seconds.
  ///
  /// UTC uses `Z`; fixed zero uses `+00:00`. Parsing this output loses named identity.
  String formatIsoOffset() => '${parts.formatTimestamp()}${isUtc ? 'Z' : offset.formatIsoOffset()}';

  @override
  bool operator ==(Object other) =>
      other is Moment &&
      microsecondsSinceEpoch == other.microsecondsSinceEpoch &&
      switch ((this, other)) {
        (UtcMoment(), UtcMoment()) => true,
        (ZonedMoment(zone: final a), ZonedMoment(zone: final b)) => a == b,
        _ => false,
      };

  @override
  int get hashCode => Object.hash(microsecondsSinceEpoch, switch (this) {
    UtcMoment() => UtcMoment,
    ZonedMoment(:final zone) => zone,
  });
}

/// An instant whose calendar fields are UTC.
final class UtcMoment extends Moment {
  const UtcMoment._(super.microsecondsSinceEpoch) : super._();
}

/// An instant retaining a named region or a fixed offset.
final class ZonedMoment extends Moment {
  const ZonedMoment._(super.microsecondsSinceEpoch, this.zone) : super._();

  /// The zone used to derive local fields.
  final TimeZone zone;
}
