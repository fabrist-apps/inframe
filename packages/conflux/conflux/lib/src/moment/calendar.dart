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
    final monthIndex = BigInt.from((p.year - 1) * 12 + p.month - 1) + displacement;
    if (monthIndex < BigInt.zero || monthIndex >= BigInt.from(9999 * 12)) {
      return const Failure(_calendarRangeError);
    }
    final index = monthIndex.toInt();
    final year = index ~/ 12 + 1;
    final month = index % 12 + 1;
    final lastDay = calendarDaysInMonth(year, month);
    final clamped = p.copyWith(year: year, month: month, day: p.day > lastDay ? lastDay : p.day);
    final calendarDays = (BigInt.from(weeks) * BigInt.from(7) + BigInt.from(days)) * sign;
    final wallMicros =
        BigInt.from(encodeParts(clamped).microsecondsSinceEpoch) +
        calendarDays * BigInt.from(Duration.microsecondsPerDay);
    if (wallMicros < BigInt.from(minimumMomentMicros) ||
        wallMicros > BigInt.from(maximumMomentMicros)) {
      return const Failure(_calendarRangeError);
    }
    final finalParts = decodeParts(
      DateTime.fromMicrosecondsSinceEpoch(wallMicros.toInt(), isUtc: true),
    );
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
    var p = parts;
    if (unit == MomentUnit.week) {
      final shift = end ? 7 - weekday : 1 - weekday;
      final date = DateTime.utc(p.year, p.month, p.day + shift);
      p = p.copyWith(year: date.year, month: date.month, day: date.day);
    }
    if (unit == MomentUnit.year) p = p.copyWith(month: end ? 12 : 1);
    if (unit == MomentUnit.year || unit == MomentUnit.month) {
      p = p.copyWith(day: end ? calendarDaysInMonth(p.year, p.month) : 1);
    }
    if (unit.index <= MomentUnit.day.index) p = p.copyWith(hour: end ? 23 : 0);
    if (unit.index <= MomentUnit.hour.index) p = p.copyWith(minute: end ? 59 : 0);
    if (unit.index <= MomentUnit.minute.index) p = p.copyWith(second: end ? 59 : 0);
    p = p.copyWith(millisecond: end ? 999 : 0, microsecond: end ? 999 : 0);
    return withParts(p, disambiguation: policy);
  }

  /// Local weekday, Monday=1 through Sunday=7.
  int get weekday => encodeParts(parts).weekday;

  /// Local day of the year, starting at 1; unaffected by offset changes.
  int get dayOfYear {
    final p = parts;
    return DateTime.utc(p.year, p.month, p.day).difference(DateTime.utc(p.year)).inDays + 1;
  }

  /// Number of calendar days in the local month.
  int get daysInMonth => calendarDaysInMonth(parts.year, parts.month);

  /// Whether the local year has February 29.
  bool get isLeapYear => calendarDaysInMonth(parts.year, 2) == 29;

  /// Local calendar quarter from 1 through 4.
  int get quarter => (parts.month - 1) ~/ 3 + 1;

  /// ISO week-year and week number, with Monday weeks containing January 4.
  ({int year, int week}) get isoWeek {
    final p = parts;
    final thursday = DateTime.utc(p.year, p.month, p.day + 4 - weekday);
    final january4 = DateTime.utc(thursday.year, 1, 4);
    final firstThursday = DateTime.utc(thursday.year, 1, 4 + 4 - january4.weekday);
    return (year: thursday.year, week: thursday.difference(firstThursday).inDays ~/ 7 + 1);
  }
}

const _calendarRangeError = MomentError(
  MomentErrorKind.outOfRange,
  'Calendar operation leaves years 1–9999.',
);
