// All value fields are final; no annotation-only runtime dependency is needed.
// ignore_for_file: avoid_equals_and_hash_code_on_mutable_classes

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

  /// Calendar year, supported from 1 through 9999.
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

/// The inclusive epoch range shared by UTC and local calendar representations.
const minimumMomentMicros = -62135596800000000;

/// The last microsecond in year 9999.
// The required microsecond range targets the Dart VM.
// ignore: avoid_js_rounded_ints
const maximumMomentMicros = 253402300799999999;

/// Checks an epoch or a local-field encoding before native conversion.
bool inMomentRange(int micros) => micros >= minimumMomentMicros && micros <= maximumMomentMicros;

/// Validates without allowing the native constructor to normalize input.
MomentError? validateParts(MomentParts parts) {
  if (parts.year < 1 || parts.year > 9999) {
    return const MomentError(MomentErrorKind.outOfRange, 'Years must be 1–9999.', field: 'year');
  }
  final fields = [
    ('month', parts.month, 1, 12),
    (
      'day',
      parts.day,
      1,
      parts.month >= 1 && parts.month <= 12 ? calendarDaysInMonth(parts.year, parts.month) : 31,
    ),
    ('hour', parts.hour, 0, 23),
    ('minute', parts.minute, 0, 59),
    ('second', parts.second, 0, 59),
    ('millisecond', parts.millisecond, 0, 999),
    ('microsecond', parts.microsecond, 0, 999),
  ];
  for (final (field, value, min, max) in fields) {
    if (value < min || value > max) {
      return MomentError(MomentErrorKind.invalidField, '$field must be $min–$max.', field: field);
    }
  }
  return null;
}

/// Gregorian month length, independent of elapsed time or a timezone.
int calendarDaysInMonth(int year, int month) => switch (month) {
  2 => year % 4 == 0 && (year % 100 != 0 || year % 400 == 0) ? 29 : 28,
  4 || 6 || 9 || 11 => 30,
  _ => 31,
};

/// Encodes calendar fields for arithmetic; this does not resolve a local instant.
DateTime encodeParts(MomentParts p) => DateTime.utc(
  p.year,
  p.month,
  p.day,
  p.hour,
  p.minute,
  p.second,
  p.millisecond,
  p.microsecond,
);

/// Extracts fields at an explicit native implementation boundary.
MomentParts decodeParts(DateTime d) => MomentParts(
  year: d.year,
  month: d.month,
  day: d.day,
  hour: d.hour,
  minute: d.minute,
  second: d.second,
  millisecond: d.millisecond,
  microsecond: d.microsecond,
);
