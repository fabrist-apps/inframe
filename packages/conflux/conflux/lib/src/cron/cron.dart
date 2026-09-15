import 'dart:collection';

import 'package:conflux/moment.dart';
import 'package:conflux/result.dart';
import 'package:conflux/src/moment/local_resolution.dart';
import 'package:timezone/timezone.dart' show Location;

/// A validation or calendar-search failure produced by [Cron].
final class CronError implements Exception {
  /// Creates a typed Cron failure with a human-readable [message].
  const CronError(this.message, {this.field});

  /// What made the expression or search invalid.
  final String message;

  /// The failing field name, when the error belongs to one field.
  final String? field;

  @override
  String toString() => field == null ? message : '$field: $message';
}

/// An immutable Cron expression evaluated in an explicit [Location].
///
/// Applications initialize their chosen `timezone` database and pass a
/// location into [parse] or [fromFields]. Constructing and matching a Cron does
/// not start timers or modify the package's global local-time configuration.
final class Cron {
  Cron._({
    required this._seconds,
    required this._minutes,
    required this._hours,
    required this._days,
    required this._months,
    required this._weekdays,
    required this.location,
  }) : _zone = TimeZone.fromLocation(location);

  final NamedTimeZone _zone;

  final _CronField _seconds;
  final _CronField _minutes;
  final _CronField _hours;
  final _CronField _days;
  final _CronField _months;
  final _CronField _weekdays;

  /// The timezone in which calendar fields are evaluated.
  final Location location;

  /// Allowed seconds, from 0 through 59.
  Set<int> get seconds => _seconds.values;

  /// Allowed minutes, from 0 through 59.
  Set<int> get minutes => _minutes.values;

  /// Allowed hours, from 0 through 23.
  Set<int> get hours => _hours.values;

  /// Allowed days of the month, from 1 through 31.
  Set<int> get days => _days.values;

  /// Allowed months, from 1 through 12.
  Set<int> get months => _months.values;

  /// Allowed weekdays, where Sunday is 0 and Saturday is 6.
  Set<int> get weekdays => _weekdays.values;

  /// Parses a five- or six-field Cron expression.
  ///
  /// Five fields use second zero. Six fields put seconds first. Lists, ranges,
  /// steps, case-insensitive month and weekday names, and Sunday as either 0 or
  /// 7 are supported. Invalid syntax or values return [CronError].
  static Result<Cron, CronError> parse(String expression, Location location) {
    try {
      final source = expression.trim();
      if (source.isEmpty) {
        return const Failure(CronError('The expression is empty.'));
      }
      final fields = source.split(RegExp(r'\s+'));
      if (fields.length == 5) fields.insert(0, '0');
      if (fields.length != 6) {
        return Failure(
          CronError('Expected five or six fields, found ${fields.length}.'),
        );
      }
      final seconds = _secondSpec.parse(fields[0]);
      final minutes = _minuteSpec.parse(fields[1]);
      final hours = _hourSpec.parse(fields[2]);
      final days = _daySpec.parse(fields[3]);
      final months = _monthSpec.parse(fields[4]);
      final weekdays = _weekdaySpec.parse(fields[5]);
      return Success(
        Cron._(
          seconds: seconds,
          minutes: minutes,
          hours: hours,
          days: days,
          months: months,
          weekdays: weekdays,
          location: location,
        ),
      );
    } on CronError catch (error) {
      return Failure(error);
    }
  }

  /// Constructs a Cron from explicit field values.
  ///
  /// An omitted field is a wildcard. An explicitly empty set or a value outside
  /// its field range returns [CronError]. Every supplied set is copied.
  static Result<Cron, CronError> fromFields({
    required Location location,
    Set<int>? seconds,
    Set<int>? minutes,
    Set<int>? hours,
    Set<int>? days,
    Set<int>? months,
    Set<int>? weekdays,
  }) {
    try {
      return Success(
        Cron._(
          seconds: _secondSpec.fromValues(seconds),
          minutes: _minuteSpec.fromValues(minutes),
          hours: _hourSpec.fromValues(hours),
          days: _daySpec.fromValues(days),
          months: _monthSpec.fromValues(months),
          weekdays: _weekdaySpec.fromValues(weekdays),
          location: location,
        ),
      );
    } on CronError catch (error) {
      return Failure(error);
    }
  }

  /// Whether [instant] has allowed calendar fields in [location].
  ///
  /// When both day fields are restricted, either may match. When either field
  /// starts with `*`, including `*/step`, both must match. A conversion outside
  /// the supported local range does not match.
  bool matches(Moment instant) {
    final converted = instant.setZone(_zone);
    if (converted case Failure<ZonedMoment, MomentError>()) return false;
    final zoned = (converted as Success<ZonedMoment, MomentError>).value;
    final local = zoned.parts;
    if (!_supportedYear(local.year) || !_supportedYear(instant.partsUtc.year)) return false;
    if (!_seconds.values.contains(local.second) ||
        !_minutes.values.contains(local.minute) ||
        !_hours.values.contains(local.hour) ||
        !_months.values.contains(local.month)) {
      return false;
    }

    return _matchesDay(local.day, zoned.weekday % 7);
  }

  /// Returns a normalized six-field expression without the location.
  ///
  /// Parsed expressions retain their field syntax in lowercase. Equivalent
  /// expressions need not format identically. Reparse with the same [location]
  /// to preserve matching behavior.
  String format() => [
    _seconds.text,
    _minutes.text,
    _hours.text,
    _days.text,
    _months.text,
    _weekdays.text,
  ].join(' ');

  /// Finds the first matching occurrence strictly after [instant].
  ///
  /// Each query examines at most 10,000 calendar-day candidates in years 1
  /// through 9999. Exhaustion returns [CronError] and does not prove that no
  /// later occurrence exists. Nonexistent local times are skipped and repeated
  /// local times represent two distinct occurrences. Results retain [location].
  Result<ZonedMoment, CronError> next(Moment instant) {
    final local = instant.setZone(_zone);
    if (local case Failure<ZonedMoment, MomentError>(:final error)) {
      return Failure(CronError(error.message));
    }

    if (!_supportedYear(instant.partsUtc.year) ||
        !_supportedYear((local as Success<ZonedMoment, MomentError>).value.parts.year)) {
      return const Failure(_searchRangeError);
    }

    final boundaryMicros = instant.microsecondsSinceEpoch;
    final offsets = _zone.candidateOffsets;

    // A rollback can revisit the previous calendar date. Start with every date
    // that could contain an eligible instant under any offset in this location.
    final wallBoundary = DateTime.fromMicrosecondsSinceEpoch(
      boundaryMicros + offsets.first.inMicroseconds,
      isUtc: true,
    );
    var wallDate = DateTime.utc(wallBoundary.year, wallBoundary.month, wallBoundary.day);
    if (wallDate.year < _minimumYear) wallDate = DateTime.utc(_minimumYear);
    ZonedMoment? best;
    CronError? rangeError;

    for (var iteration = 0; iteration < _searchBudget; iteration += 1) {
      if (wallDate.year < _minimumYear || wallDate.year > _maximumYear) {
        if (best != null) return Success(best);
        return Failure(
          rangeError ?? const CronError('The search reached the supported date range.'),
        );
      }

      if (_matchesDate(wallDate)) {
        final found = _findOnDate(
          wallDate,
          boundaryMicros: boundaryMicros,
          offsets: offsets,
        );
        switch (found) {
          case Failure<ZonedMoment?, CronError>(:final error):
            rangeError = error;
          case Success<ZonedMoment?, CronError>(:final value):
            if (value != null && (best == null || value.isBefore(best))) {
              best = value;
            }
        }
      }

      wallDate = wallDate.add(const Duration(days: 1));

      // Calendar-date order is not necessarily instant order across a rollback.
      // Return only once no candidate on this or a later searched date can win.
      final dateLimit = wallDate.microsecondsSinceEpoch - offsets.last.inMicroseconds;
      if (best != null && dateLimit >= best.microsecondsSinceEpoch) {
        return Success(best);
      }
    }

    return const Failure(
      CronError('The search exhausted its 10,000 candidate-iteration budget.'),
    );
  }

  /// Lazily yields occurrences strictly after [instant].
  ///
  /// A search failure is yielded once as the terminal element. The iterable is
  /// synchronous and does not own a timer or impose an end date.
  Iterable<Result<ZonedMoment, CronError>> sequence(Moment instant) sync* {
    var cursor = instant;
    while (true) {
      final result = next(cursor);
      yield result;
      switch (result) {
        case Success<ZonedMoment, CronError>(:final value):
          cursor = value;
        case Failure<ZonedMoment, CronError>():
          return;
      }
    }
  }

  bool _matchesDate(DateTime wallDate) {
    if (!_months.values.contains(wallDate.month)) return false;

    return _matchesDay(wallDate.day, wallDate.weekday % 7);
  }

  bool _matchesDay(int day, int weekday) {
    final dayMatches = _days.values.contains(day);
    final weekdayMatches = _weekdays.values.contains(weekday);
    if (!_days.startsWithWildcard && !_weekdays.startsWithWildcard) {
      return dayMatches || weekdayMatches;
    }

    return dayMatches && weekdayMatches;
  }

  Result<ZonedMoment?, CronError> _findOnDate(
    DateTime wallDate, {
    required int boundaryMicros,
    required List<Duration> offsets,
  }) {
    final minimumOffset = offsets.first;
    final maximumOffset = offsets.last;
    ZonedMoment? best;
    CronError? rangeError;

    for (final hour in _hours.values) {
      for (final minute in _minutes.values) {
        for (final second in _seconds.values) {
          final wallMicros =
              wallDate.microsecondsSinceEpoch +
              Duration(hours: hour, minutes: minute, seconds: second).inMicroseconds;
          final earliestPossible = wallMicros - maximumOffset.inMicroseconds;
          final latestPossible = wallMicros - minimumOffset.inMicroseconds;
          if (latestPossible <= boundaryMicros) continue;
          if (best != null && earliestPossible > best.microsecondsSinceEpoch) {
            return Success(best);
          }

          for (final candidateMicros in _zone.localCandidates(wallMicros, offsets)) {
            if (candidateMicros <= boundaryMicros) continue;

            final result = Moment.fromEpochMicroseconds(candidateMicros)
                .flatMap((utc) => utc.setZone(_zone));
            if (result case Failure<ZonedMoment, MomentError>(:final error)) {
              // Conservative historical-offset bounds can enumerate beyond UTC
              // range after finding a valid occurrence. Keep ordering the valid
              // candidates; a range failure must not discard one already found.
              rangeError = CronError(error.message);
              continue;
            }

            final candidate = (result as Success<ZonedMoment, MomentError>).value;
            if (!_supportedYear(candidate.partsUtc.year)) {
              rangeError = _searchRangeError;
              continue;
            }

            if (best == null || candidate.isBefore(best)) {
              best = candidate;
            }
          }
        }
      }
    }

    if (best == null && rangeError != null) return Failure(rangeError);

    return Success(best);
  }
}

bool _supportedYear(int year) => year >= _minimumYear && year <= _maximumYear;

const _searchRangeError = CronError('Cron searches require UTC and local years 1–9999.');

const _searchBudget = 10000;
const _minimumYear = 1;
const _maximumYear = 9999;

final class _CronField {
  // The builder transfers ownership of its sorted set; callers only see a view.
  _CronField(SplayTreeSet<int> values, this.text) : values = UnmodifiableSetView(values);

  final Set<int> values;
  final String text;

  bool get startsWithWildcard => text.startsWith('*');
}

final class _FieldSpec {
  const _FieldSpec(this.name, this.minimum, this.maximum, {this.names = const {}});

  final String name;
  final int minimum;
  final int maximum;
  final Map<String, int> names;

  _CronField fromValues(Set<int>? source) {
    if (source == null) return parse('*');
    if (source.isEmpty) throw CronError('The field must not be empty.', field: name);

    final values = SplayTreeSet<int>();
    for (final value in source) {
      _validate(value);
      values.add(_normalize(value));
    }

    return _CronField(values, values.join(','));
  }

  _CronField parse(String source) {
    final token = source.toLowerCase();
    final values = SplayTreeSet<int>();
    for (final part in token.split(',')) {
      if (part.isEmpty) throw CronError('Empty list item in "$source".', field: name);

      final stepParts = part.split('/');
      if (stepParts.length > 2 || stepParts.any((value) => value.isEmpty)) {
        throw CronError('Invalid step "$part".', field: name);
      }
      final stepText = stepParts.length == 1 ? '1' : stepParts[1];
      final step = _decimal.hasMatch(stepText) ? int.tryParse(stepText) : null;
      if (step == null || step <= 0) {
        throw CronError('Step must be a positive integer in "$part".', field: name);
      }

      final base = stepParts[0];
      late final int start;
      late final int end;
      if (base == '*') {
        start = minimum;
        end = maximum;
      } else {
        final range = base.split('-');
        if (range.length > 2 || range.any((value) => value.isEmpty)) {
          throw CronError('Invalid range "$base".', field: name);
        }
        start = _parseValue(range[0]);
        end = range.length == 2 ? _parseValue(range[1]) : (stepParts.length == 2 ? maximum : start);
        if (start > end) {
          throw CronError('Range start must not exceed its end in "$base".', field: name);
        }
      }

      for (var value = start; value <= end; value += step) {
        values.add(_normalize(value));
        // Stop before addition so an oversized step cannot overflow the integer.
        if (step > end - value) break;
      }
    }

    return _CronField(values, token);
  }

  int _parseValue(String source) {
    final value = names[source] ?? (_decimal.hasMatch(source) ? int.tryParse(source) : null);
    if (value == null) throw CronError('Invalid value "$source".', field: name);

    _validate(value);
    return value;
  }

  void _validate(int value) {
    if (value < minimum || value > maximum) {
      throw CronError('$value is outside $minimum..$maximum.', field: name);
    }
  }

  int _normalize(int value) => identical(this, _weekdaySpec) && value == 7 ? 0 : value;

  static final _decimal = RegExp(r'^\d+$');
}

const _secondSpec = _FieldSpec('seconds', 0, 59);
const _minuteSpec = _FieldSpec('minutes', 0, 59);
const _hourSpec = _FieldSpec('hours', 0, 23);
const _daySpec = _FieldSpec('days', 1, 31);
const _monthSpec = _FieldSpec(
  'months',
  1,
  12,
  names: {
    'jan': 1,
    'feb': 2,
    'mar': 3,
    'apr': 4,
    'may': 5,
    'jun': 6,
    'jul': 7,
    'aug': 8,
    'sep': 9,
    'oct': 10,
    'nov': 11,
    'dec': 12,
  },
);
const _weekdaySpec = _FieldSpec(
  'weekdays',
  0,
  7,
  names: {'sun': 0, 'mon': 1, 'tue': 2, 'wed': 3, 'thu': 4, 'fri': 5, 'sat': 6},
);
