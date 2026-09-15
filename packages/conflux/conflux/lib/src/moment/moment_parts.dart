// All value fields are final; no annotation-only runtime dependency is needed.
// ignore_for_file: avoid_equals_and_hash_code_on_mutable_classes

import 'package:conflux/result.dart';
import 'package:conflux/src/moment/moment_error.dart';

/// Immutable local or UTC calendar fields, validated when constructing a Moment.
final class MomentParts {
  /// Supplies a date and optional clock fields. Invalid inputs are retained.
  const MomentParts({
    required this.year,
    required this.month,
    required this.day,
    this.hour = 0,
    this.minute = 0,
    this.second = 0,
    this.millisecond = 0,
    this.microsecond = 0,
  });

  /// Proleptic Gregorian year, including year zero and negative years.
  final int year;

  /// Month from 1 through 12.
  final int month;

  /// Day of the month, starting at 1.
  final int day;

  /// Hour from 0 through 23.
  final int hour;

  /// Minute from 0 through 59.
  final int minute;

  /// Second from 0 through 59; leap seconds are unsupported.
  final int second;

  /// Millisecond within the second, from 0 through 999.
  final int millisecond;

  /// Microsecond within the millisecond, from 0 through 999.
  final int microsecond;

  /// Replaces supplied fields and retains omitted fields without validation.
  MomentParts copyWith({
    int? year,
    int? month,
    int? day,
    int? hour,
    int? minute,
    int? second,
    int? millisecond,
    int? microsecond,
  }) => MomentParts(
    year: year ?? this.year,
    month: month ?? this.month,
    day: day ?? this.day,
    hour: hour ?? this.hour,
    minute: minute ?? this.minute,
    second: second ?? this.second,
    millisecond: millisecond ?? this.millisecond,
    microsecond: microsecond ?? this.microsecond,
  );

  @override
  bool operator ==(Object other) =>
      other is MomentParts &&
      year == other.year &&
      month == other.month &&
      day == other.day &&
      hour == other.hour &&
      minute == other.minute &&
      second == other.second &&
      millisecond == other.millisecond &&
      microsecond == other.microsecond;

  @override
  int get hashCode => Object.hash(year, month, day, hour, minute, second, millisecond, microsecond);
}

/// Dart DateTime's inclusive lower bound: 100 million days before the epoch.
const minimumMomentMicros = -8640000000000000000;

/// Dart DateTime's inclusive upper bound: 100 million days after the epoch.
const maximumMomentMicros = 8640000000000000000;

/// Checks an epoch or a local-field encoding before native conversion.
bool inMomentRange(int micros) => micros >= minimumMomentMicros && micros <= maximumMomentMicros;

/// Gregorian month length, independent of elapsed time or a timezone.
int calendarDaysInMonth(int year, int month) => switch (month) {
  2 => year % 4 == 0 && (year % 100 != 0 || year % 400 == 0) ? 29 : 28,
  4 || 6 || 9 || 11 => 30,
  _ => 31,
};

/// Internal validation and native calendar encoding, excluded from the public entrypoint.
extension MomentPartsEncoding on MomentParts {
  /// Validates and encodes fields without normalizing calendar overflow.
  Result<int, MomentError> encodeValidated() {
    if (year < -271821 || year > 275760) {
      return const Failure(
        MomentError(
          MomentErrorKind.outOfRange,
          'Year is outside Dart DateTime’s range.',
          field: 'year',
        ),
      );
    }
    for (final (field, value, min, max) in [
      ('month', month, 1, 12),
      ('day', day, 1, calendarDaysInMonth(year, month)),
      ('hour', hour, 0, 23),
      ('minute', minute, 0, 59),
      ('second', second, 0, 59),
      ('millisecond', millisecond, 0, 999),
      ('microsecond', microsecond, 0, 999),
    ]) {
      if (value < min || value > max) {
        return Failure(
          MomentError(MomentErrorKind.invalidField, '$field must be $min–$max.', field: field),
        );
      }
    }
    final micros = encodeCalendar();
    if (micros < BigInt.from(minimumMomentMicros) || micros > BigInt.from(maximumMomentMicros)) {
      return const Failure(
        MomentError(
          MomentErrorKind.outOfRange,
          'Calendar fields are outside Dart DateTime’s range.',
        ),
      );
    }
    return Success(micros.toInt());
  }

  /// Encodes Gregorian fields exactly, including intermediate out-of-range dates.
  ///
  /// Gregorian dates repeat every 400 years (146097 days). A safe surrogate year
  /// lets native calendar logic handle the fields while BigInt retains the cycle
  /// displacement, without constructing a DateTime beyond its representable range.
  BigInt encodeCalendar({BigInt? year, int? month, int? day}) {
    final calendarYear = year ?? BigInt.from(this.year);
    final surrogateYear = (calendarYear % BigInt.from(400)).toInt() + 2000;
    final cycles = (calendarYear - BigInt.from(surrogateYear)) ~/ BigInt.from(400);
    final surrogate = DateTime.utc(
      surrogateYear,
      month ?? this.month,
      day ?? this.day,
      hour,
      minute,
      second,
      millisecond,
      microsecond,
    );

    return BigInt.from(surrogate.microsecondsSinceEpoch) +
        cycles * BigInt.from(146097) * BigInt.from(Duration.microsecondsPerDay);
  }

  /// Encodes already validated calendar fields, without resolving a local instant.
  DateTime encode() =>
      DateTime.utc(year, month, day, hour, minute, second, millisecond, microsecond);
}

/// Extracts native calendar fields without changing their timezone.
extension DateTimeMomentParts on DateTime {
  /// Extracts fields at an explicit native implementation boundary.
  MomentParts toMomentParts() => MomentParts(
    year: year,
    month: month,
    day: day,
    hour: hour,
    minute: minute,
    second: second,
    millisecond: millisecond,
    microsecond: microsecond,
  );
}
