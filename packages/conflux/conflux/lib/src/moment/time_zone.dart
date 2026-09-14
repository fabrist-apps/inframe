// All value fields are final; no annotation-only runtime dependency is needed.
// ignore_for_file: avoid_equals_and_hash_code_on_mutable_classes

import 'package:conflux/result.dart';
import 'package:conflux/src/moment/moment_error.dart';
import 'package:timezone/timezone.dart' as tz;

/// An explicit named region or constant offset; never an implicit device zone.
sealed class TimeZone {
  const TimeZone._();

  /// Looks up an exact identifier in the caller-initialized IANA database.
  static Result<NamedTimeZone, MomentError> named(String id) {
    if (!tz.timeZoneDatabase.isInitialized) {
      return const Failure(
        MomentError(
          MomentErrorKind.timezoneNotInitialized,
          'Initialize the timezone database before looking up a named zone.',
        ),
      );
    }
    final location = tz.timeZoneDatabase.locations[id];
    if (location == null) {
      return Failure(MomentError(MomentErrorKind.unknownTimeZone, 'Unknown timezone: $id.'));
    }
    return Success(NamedTimeZone._(location, id));
  }

  /// Borrows a resolved location without reading or changing global configuration.
  static NamedTimeZone fromLocation(tz.Location location) =>
      NamedTimeZone._(location, location.name);

  /// Validates a whole-second offset with an absolute value below 24 hours.
  static Result<FixedTimeZone, MomentError> fixed(Duration offset) {
    final micros = offset.inMicroseconds;
    if (micros % Duration.microsecondsPerSecond != 0 ||
        micros <= -Duration.microsecondsPerDay ||
        micros >= Duration.microsecondsPerDay) {
      return const Failure(
        MomentError(
          MomentErrorKind.invalidOffset,
          'Offsets must be whole seconds with magnitude below 24 hours.',
          field: 'offset',
        ),
      );
    }
    return Success(FixedTimeZone._(offset));
  }
}

/// A retained IANA location identified by its exact name, without alias folding.
final class NamedTimeZone extends TimeZone {
  const NamedTimeZone._(this.location, this.id) : super._();

  /// The borrowed location; later database replacement does not re-resolve it.
  final tz.Location location;

  /// The exact identifier used at construction.
  final String id;

  @override
  bool operator ==(Object other) => other is NamedTimeZone && id == other.id;
  @override
  int get hashCode => Object.hash(NamedTimeZone, id);
}

/// A constant offset, including fixed zero as distinct from UTC representation.
final class FixedTimeZone extends TimeZone {
  const FixedTimeZone._(this.offset) : super._();

  /// The fixed offset east of UTC.
  final Duration offset;

  @override
  bool operator ==(Object other) => other is FixedTimeZone && offset == other.offset;
  @override
  int get hashCode => Object.hash(FixedTimeZone, offset);
}

/// Reads the offset at an instant without losing negative sub-millisecond precision.
Duration zoneOffset(TimeZone zone, int micros) => switch (zone) {
  FixedTimeZone(:final offset) => offset,
  NamedTimeZone(:final location) => location.timeZone((micros - micros % 1000) ~/ 1000).offset,
};

/// The required choice when supplied local fields are repeated or absent.
enum Disambiguation {
  /// Earlier overlap instant; shift backward by a gap.
  earlier,

  /// Later overlap instant; shift forward by a gap.
  later,

  /// Earlier overlap instant; shift forward by a gap.
  compatible,

  /// Fail for either an overlap or a gap.
  reject,
}
