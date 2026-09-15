import 'package:conflux/moment.dart';
import 'package:conflux/result.dart';

/// Constructs a validated UTC instant for test fixtures.
Moment utcMoment(
  int year, [
  int month = 1,
  int day = 1,
  int hour = 0,
  int minute = 0,
  int second = 0,
  int millisecond = 0,
  int microsecond = 0,
]) => Moment.utc(
  MomentParts(
    year: year,
    month: month,
    day: day,
    hour: hour,
    minute: minute,
    second: second,
    millisecond: millisecond,
    microsecond: microsecond,
  ),
).getOrThrowWith((error) => StateError('$error'));
