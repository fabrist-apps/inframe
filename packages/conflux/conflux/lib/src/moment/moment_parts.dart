// All value fields are final; no annotation-only runtime dependency is needed.
// ignore_for_file: avoid_equals_and_hash_code_on_mutable_classes

import 'package:ack/ack.dart';
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

  factory MomentParts._fromMap(Map<String, Object?> fields) => MomentParts(
    year: fields['year']! as int,
    month: fields['month']! as int,
    day: fields['day']! as int,
    hour: (fields['hour'] as int?) ?? 0,
    minute: (fields['minute'] as int?) ?? 0,
    second: (fields['second'] as int?) ?? 0,
    millisecond: (fields['millisecond'] as int?) ?? 0,
    microsecond: (fields['microsecond'] as int?) ?? 0,
  );

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

  /// Decodes calendar-field maps and validates models when encoding them.
  ///
  /// Clock fields default to zero. Invalid dates and times are never normalized.
  static AckSchema<Map<String, Object?>, MomentParts> schema() =>
      Ack.object({
            'year': Ack.integer().min(-271821).max(275760),
            'month': Ack.integer().min(1).max(12),
            'day': Ack.integer().min(1),
            'hour': Ack.integer().min(0).max(23).withDefault(0),
            'minute': Ack.integer().min(0).max(59).withDefault(0),
            'second': Ack.integer().min(0).max(59).withDefault(0),
            'millisecond': Ack.integer().min(0).max(999).withDefault(0),
            'microsecond': Ack.integer().min(0).max(999).withDefault(0),
          })
          .refine((fields) {
            final parts = MomentParts._fromMap(fields);
            if (_daySchema(parts.year, parts.month).safeParse(parts.day).isFail) {
              throw _InvalidMomentParts(
                MomentError(
                  MomentErrorKind.invalidField,
                  'day must be 1–${calendarDaysInMonth(parts.year, parts.month)}.',
                  field: 'day',
                ),
              );
            }
            final micros = parts.encodeCalendar();
            if (micros < BigInt.from(minimumMomentMicros) ||
                micros > BigInt.from(maximumMomentMicros)) {
              throw const _InvalidMomentParts(
                MomentError(
                  MomentErrorKind.outOfRange,
                  'Calendar fields are outside Dart DateTime’s range.',
                ),
              );
            }
            return true;
          })
          .codec<MomentParts>(
            decode: MomentParts._fromMap,
            encode: (parts) => {
              'year': parts.year,
              'month': parts.month,
              'day': parts.day,
              'hour': parts.hour,
              'minute': parts.minute,
              'second': parts.second,
              'millisecond': parts.millisecond,
              'microsecond': parts.microsecond,
            },
          );

  static AckSchema<int, int> _daySchema(int year, int month) =>
      Ack.integer().min(1).max(calendarDaysInMonth(year, month));

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
  /// Validates without allowing the native constructor to normalize input.
  MomentError? validate() {
    final result = MomentParts.schema().safeEncode(this);
    if (result case Fail(:final error)) {
      if (error.cause case _InvalidMomentParts(:final error)) return error;
      if (error is! SchemaNestedError) throw AckException([error]);
      final first = error.errors.first;
      var field = first.name;
      if (field == 'year') {
        return const MomentError(
          MomentErrorKind.outOfRange,
          'Year is outside Dart DateTime’s range.',
          field: 'year',
        );
      }
      // Ack checks primitive fields before cross-field rules. Preserve the
      // factory's date-before-clock diagnostic when both inputs are invalid.
      if (field != 'month' && MomentParts._daySchema(year, month).safeParse(day).isFail) {
        field = 'day';
      }
      final (min, max) = switch (field) {
        'month' => (1, 12),
        'day' => (1, calendarDaysInMonth(year, month)),
        'hour' => (0, 23),
        'minute' || 'second' => (0, 59),
        'millisecond' || 'microsecond' => (0, 999),
        _ => throw AckException([error]),
      };
      return MomentError(MomentErrorKind.invalidField, '$field must be $min–$max.', field: field);
    }
    return null;
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
  DateTime encode() => DateTime.fromMicrosecondsSinceEpoch(encodeCalendar().toInt(), isUtc: true);
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

final class _InvalidMomentParts implements Exception {
  const _InvalidMomentParts(this.error);

  final MomentError error;

  @override
  String toString() => error.message;
}
