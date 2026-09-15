import 'package:conflux/result.dart';
import 'package:conflux/src/moment/moment.dart';
import 'package:conflux/src/moment/moment_error.dart';
import 'package:conflux/src/moment/moment_parts.dart';
import 'package:conflux/src/moment/time_zone.dart';

/// Local calendar periods; weeks run Monday through Sunday.
enum MomentUnit {
  /// Calendar year.
  year,

  /// Calendar month.
  month,

  /// Monday through Sunday.
  week,

  /// Local calendar day.
  day,

  /// Local clock hour.
  hour,

  /// Local clock minute.
  minute,

  /// Local clock second.
  second,
}

/// Calendar operations in a Moment's retained zone, separate from elapsed time.
extension MomentCalendar on Moment {
  /// Adds signed calendar units, resolving only the final local fields.
  ///
  /// Combine years/months, clamp the day once, then add weeks/days. January 31
  /// plus two months is March 31; two one-month calls may instead reach March 28.
  Result<Moment, MomentError> addCalendar({
    required Disambiguation disambiguation,
    int years = 0,
    int months = 0,
    int weeks = 0,
    int days = 0,
  }) => _calendarShift(years, months, weeks, days, subtract: false, policy: disambiguation);

  /// Subtracts calendar units in the same order, with each amount negated.
  ///
  /// Clamping is not generally reversible. Negative amounts are accepted.
  Result<Moment, MomentError> subtractCalendar({
    required Disambiguation disambiguation,
    int years = 0,
    int months = 0,
    int weeks = 0,
    int days = 0,
  }) => _calendarShift(years, months, weeks, days, subtract: true, policy: disambiguation);

  Result<Moment, MomentError> _calendarShift(
    int years,
    int months,
    int weeks,
    int days, {
    required bool subtract,
    required Disambiguation policy,
  }) {
    final p = parts;

    // Combine before narrowing: large signed amounts must not wrap or lose
    // cancellation between years/months or weeks/days.
    final sign = BigInt.from(subtract ? -1 : 1);
    final displacement = (BigInt.from(years) * BigInt.from(12) + BigInt.from(months)) * sign;
    final monthIndex =
        BigInt.from(p.year) * BigInt.from(12) + BigInt.from(p.month - 1) + displacement;
    final monthRemainder = monthIndex % BigInt.from(12);
    final year = (monthIndex - monthRemainder) ~/ BigInt.from(12);
    final month = monthRemainder.toInt() + 1;

    final lastDay = calendarDaysInMonth((year % BigInt.from(400)).toInt(), month);
    final clampedMicros = p.encodeCalendar(
      year: year,
      month: month,
      day: p.day > lastDay ? lastDay : p.day,
    );

    final calendarDays = (BigInt.from(weeks) * BigInt.from(7) + BigInt.from(days)) * sign;
    final wallMicros = clampedMicros + calendarDays * BigInt.from(Duration.microsecondsPerDay);
    if (wallMicros < BigInt.from(minimumMomentMicros) ||
        wallMicros > BigInt.from(maximumMomentMicros)) {
      return const Failure(MomentError.calenderRange);
    }

    final finalParts = DateTime.fromMicrosecondsSinceEpoch(
      wallMicros.toInt(),
      isUtc: true,
    ).toMomentParts();

    return withParts(finalParts, disambiguation: policy);
  }

  /// Resolves the minimum local fields for [unit] using the supplied policy.
  ///
  /// Gap shifts may leave the nominal period; use reject to disallow them.
  Result<Moment, MomentError> startOf(MomentUnit unit, {required Disambiguation disambiguation}) =>
      _boundary(unit, end: false, policy: disambiguation);

  /// Resolves the maximum local fields for [unit], through microsecond 999999.
  ///
  /// This resolves boundary fields, not the boundary nearest this instant.
  /// A day end is not derived by adding 24 elapsed hours to its start.
  Result<Moment, MomentError> endOf(MomentUnit unit, {required Disambiguation disambiguation}) =>
      _boundary(unit, end: true, policy: disambiguation);

  Result<Moment, MomentError> _boundary(
    MomentUnit unit, {
    required bool end,
    required Disambiguation policy,
  }) {
    final p = parts;
    var year = p.year;
    var month = p.month;
    var day = p.day;

    switch (unit) {
      case MomentUnit.year:
        month = end ? 12 : 1;
        day = end ? 31 : 1;
      case MomentUnit.month:
        day = end ? calendarDaysInMonth(year, month) : 1;
      case MomentUnit.week:
        final shift = end ? 7 - p.encode().weekday : 1 - p.encode().weekday;
        final surrogateYear = 2000 + year % 400;
        final date = DateTime.utc(surrogateYear, month, day + shift);
        year += date.year - surrogateYear;
        month = date.month;
        day = date.day;
      case MomentUnit.day || MomentUnit.hour || MomentUnit.minute || MomentUnit.second:
        break;
    }

    final boundary = MomentParts(
      year: year,
      month: month,
      day: day,
      hour: switch (unit) {
        MomentUnit.hour || MomentUnit.minute || MomentUnit.second => p.hour,
        _ => end ? 23 : 0,
      },
      minute: switch (unit) {
        MomentUnit.minute || MomentUnit.second => p.minute,
        _ => end ? 59 : 0,
      },
      second: unit == MomentUnit.second ? p.second : (end ? 59 : 0),
      millisecond: end ? 999 : 0,
      microsecond: end ? 999 : 0,
    );

    return withParts(boundary, disambiguation: policy);
  }

  /// Local weekday, Monday=1 through Sunday=7.
  int get weekday => parts.encode().weekday;

  /// Local day of the year, starting at 1; unaffected by offset changes.
  int get dayOfYear => _dayOfYear(parts);

  static int _dayOfYear(MomentParts p) {
    var days = p.day;
    for (var month = 1; month < p.month; month++) {
      days += calendarDaysInMonth(p.year, month);
    }

    return days;
  }

  /// Number of calendar days in the local month.
  int get daysInMonth {
    final p = parts;
    return calendarDaysInMonth(p.year, p.month);
  }

  /// Whether the local year has February 29.
  bool get isLeapYear => calendarDaysInMonth(parts.year, 2) == 29;

  /// Local calendar quarter from 1 through 4.
  int get quarter => (parts.month - 1) ~/ 3 + 1;

  /// ISO week-year and week number, with Monday weeks containing January 4.
  ({int year, int week}) get isoWeek {
    final p = parts;
    final week = (_dayOfYear(p) - p.encode().weekday + 10) ~/ 7;
    if (week == 0) return (year: p.year - 1, week: _isoWeeksInYear(p.year - 1));
    if (week > _isoWeeksInYear(p.year)) return (year: p.year + 1, week: 1);

    return (year: p.year, week: week);
  }

  // Gregorian weekdays repeat every 400 years, including at native range edges.
  static int _isoWeeksInYear(int year) {
    final januaryWeekday = DateTime.utc(2000 + year % 400).weekday;
    return januaryWeekday == 4 || (januaryWeekday == 3 && calendarDaysInMonth(year, 2) == 29)
        ? 53
        : 52;
  }
}
