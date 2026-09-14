import 'dart:collection';

import 'package:conflux/moment.dart';
import 'package:conflux/result.dart';
import 'package:conflux/src/moment/calendar_date.dart';
import 'package:conflux/src/moment/time_zone.dart' show zoneOffset;
import 'package:timezone/timezone.dart' show Location;

/// A validation or calendar-search failure produced by [Cron].
final class CronError {
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
      final seconds = _parseField(fields[0], _secondSpec);
      final minutes = _parseField(fields[1], _minuteSpec);
      final hours = _parseField(fields[2], _hourSpec);
      final days = _parseField(fields[3], _daySpec);
      final months = _parseField(fields[4], _monthSpec);
      final weekdays = _parseField(fields[5], _weekdaySpec);
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
    } on _InvalidCron catch (failure) {
      return Failure(CronError(failure.message, field: failure.field));
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
          seconds: _fieldFromValues(seconds, _secondSpec),
          minutes: _fieldFromValues(minutes, _minuteSpec),
          hours: _fieldFromValues(hours, _hourSpec),
          days: _fieldFromValues(days, _daySpec),
          months: _fieldFromValues(months, _monthSpec),
          weekdays: _fieldFromValues(weekdays, _weekdaySpec),
          location: location,
        ),
      );
    } on _InvalidCron catch (failure) {
      return Failure(CronError(failure.message, field: failure.field));
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
  /// Reparse the result with the same [location] to preserve matching behavior.
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
  Result<ZonedMoment, CronError> next(Moment instant) => _find(instant, forward: true);

  /// Finds the first matching occurrence strictly before [instant].
  ///
  /// This uses the same date range, search budget, and timezone-transition
  /// behavior as [next].
  Result<ZonedMoment, CronError> previous(Moment instant) => _find(instant, forward: false);

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

  Result<ZonedMoment, CronError> _find(Moment instant, {required bool forward}) {
    final local = instant.setZone(_zone);
    if (local case Failure<ZonedMoment, MomentError>(:final error)) {
      return Failure(CronError(error.message));
    }
    if (!_supportedYear(instant.partsUtc.year) ||
        !_supportedYear((local as Success<ZonedMoment, MomentError>).value.parts.year)) {
      return const Failure(_searchRangeError);
    }
    final boundaryMicros = instant.microsecondsSinceEpoch;
    final offsets = location.zones.isEmpty
        ? const [Duration.zero]
        : SplayTreeSet<Duration>.of(location.zones.map((zone) => zone.offset)).toList();
    // A rollback can revisit the previous calendar date. Start with every date
    // that could contain an eligible instant under any offset in this location.
    final wallBoundary = boundaryMicros + (forward ? offsets.first : offsets.last).inMicroseconds;
    var date = CalendarDate.fromWallMicroseconds(wallBoundary);
    if (forward && date.year < _minimumYear) date = CalendarDate(_minimumYear);
    if (!forward && date.year > _maximumYear) date = CalendarDate(_maximumYear, 12, 31);
    ZonedMoment? best;
    CronError? rangeError;

    for (var iteration = 0; iteration < _searchBudget; iteration += 1) {
      if (date.year < _minimumYear || date.year > _maximumYear) {
        if (best != null) return Success(best);
        return Failure(
          rangeError ?? const CronError('The search reached the supported date range.'),
        );
      }
      if (_matchesDate(date)) {
        final found = _findOnDate(
          date,
          boundaryMicros: boundaryMicros,
          offsets: offsets,
          forward: forward,
        );
        switch (found) {
          case Failure<ZonedMoment?, CronError>(:final error):
            rangeError = error;
          case Success<ZonedMoment?, CronError>(:final value):
            if (value != null &&
                (best == null || (forward ? value.isBefore(best) : value.isAfter(best)))) {
              best = value;
            }
        }
      }
      date = date.addDays(forward ? 1 : -1);
      // Calendar-date order is not necessarily instant order across a rollback.
      // Return only once no candidate on this or a later searched date can win.
      final dateLimit = forward
          ? date.wallMicroseconds - offsets.last.inMicroseconds
          : date.addDays(1).wallMicroseconds - offsets.first.inMicroseconds;
      if (best != null &&
          (forward
              ? dateLimit >= best.microsecondsSinceEpoch
              : dateLimit <= best.microsecondsSinceEpoch)) {
        return Success(best);
      }
    }
    return const Failure(
      CronError('The search exhausted its 10,000 candidate-iteration budget.'),
    );
  }

  bool _matchesDate(CalendarDate date) {
    if (!_months.values.contains(date.month)) return false;
    return _matchesDay(date.day, date.weekday % 7);
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
    CalendarDate date, {
    required int boundaryMicros,
    required List<Duration> offsets,
    required bool forward,
  }) {
    final orderedHours = forward ? _hours.values : _hours.values.toList().reversed;
    final orderedMinutes = forward ? _minutes.values : _minutes.values.toList().reversed;
    final orderedSeconds = forward ? _seconds.values : _seconds.values.toList().reversed;
    final minimumOffset = offsets.first;
    final maximumOffset = offsets.last;
    ZonedMoment? best;
    CronError? rangeError;

    for (final hour in orderedHours) {
      for (final minute in orderedMinutes) {
        for (final second in orderedSeconds) {
          final wallMicros = date.at(hour, minute, second);
          final earliestPossible = wallMicros - maximumOffset.inMicroseconds;
          final latestPossible = wallMicros - minimumOffset.inMicroseconds;
          if (forward) {
            if (latestPossible <= boundaryMicros) continue;
            if (best != null && earliestPossible > best.microsecondsSinceEpoch) {
              return Success(best);
            }
          } else {
            if (earliestPossible >= boundaryMicros) continue;
            if (best != null && latestPossible < best.microsecondsSinceEpoch) return Success(best);
          }

          for (final offset in offsets) {
            final candidateMicros = wallMicros - offset.inMicroseconds;
            if (forward ? candidateMicros <= boundaryMicros : candidateMicros >= boundaryMicros) {
              continue;
            }
            // Only a currently applicable offset reproduces the local fields.
            // This skips gaps and keeps both actual overlap occurrences.
            if (zoneOffset(_zone, candidateMicros) != offset) continue;
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
            if (best == null || (forward ? candidate.isBefore(best) : candidate.isAfter(best))) {
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
  _CronField(Iterable<int> values, {required this.text, required this.startsWithWildcard})
    : values = UnmodifiableSetView(SplayTreeSet<int>.of(values));

  final Set<int> values;
  final String text;
  final bool startsWithWildcard;
}

final class _FieldSpec {
  const _FieldSpec(this.name, this.minimum, this.maximum, {this.names = const {}});

  final String name;
  final int minimum;
  final int maximum;
  final Map<String, int> names;
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

_CronField _fieldFromValues(Set<int>? source, _FieldSpec spec) {
  if (source == null) {
    return _CronField(
      _range(spec.minimum, spec.maximum).map((value) => _normalize(value, spec)),
      text: '*',
      startsWithWildcard: true,
    );
  }
  if (source.isEmpty) throw _InvalidCron(spec.name, 'The field must not be empty.');
  final values = SplayTreeSet<int>();
  for (final value in source) {
    _validate(value, spec);
    values.add(_normalize(value, spec));
  }
  return _CronField(values, text: values.join(','), startsWithWildcard: false);
}

_CronField _parseField(String source, _FieldSpec spec) {
  final token = source.toLowerCase();
  if (token.isEmpty) throw _InvalidCron(spec.name, 'The field is empty.');
  final values = SplayTreeSet<int>();
  for (final part in token.split(',')) {
    if (part.isEmpty) throw _InvalidCron(spec.name, 'Empty list item in "$source".');
    final stepParts = part.split('/');
    if (stepParts.length > 2 || stepParts.any((value) => value.isEmpty)) {
      throw _InvalidCron(spec.name, 'Invalid step "$part".');
    }
    final stepText = stepParts.length == 1 ? '1' : stepParts[1];
    final step = _decimal.hasMatch(stepText) ? int.tryParse(stepText) : null;
    if (step == null || step <= 0) {
      throw _InvalidCron(spec.name, 'Step must be a positive integer in "$part".');
    }
    final base = stepParts[0];
    late final int start;
    late final int end;
    if (base == '*') {
      start = spec.minimum;
      end = spec.maximum;
    } else {
      final range = base.split('-');
      if (range.length > 2 || range.any((value) => value.isEmpty)) {
        throw _InvalidCron(spec.name, 'Invalid range "$base".');
      }
      start = _parseValue(range[0], spec);
      end = range.length == 2
          ? _parseValue(range[1], spec)
          : (stepParts.length == 2 ? spec.maximum : start);
      if (start > end) {
        throw _InvalidCron(spec.name, 'Range start must not exceed its end in "$base".');
      }
    }
    for (final value in _range(start, end, step: step)) {
      values.add(_normalize(value, spec));
    }
  }
  if (values.isEmpty) throw _InvalidCron(spec.name, 'The field matches no values.');
  return _CronField(
    values,
    text: _canonicalFieldText(token, values, spec),
    startsWithWildcard: token.startsWith('*'),
  );
}

String _canonicalFieldText(String token, Set<int> values, _FieldSpec spec) {
  if (!token.startsWith('*')) return values.join(',');
  final allValues = _range(
    spec.minimum,
    spec.maximum,
  ).map((value) => _normalize(value, spec)).toSet();
  if (values.length == allValues.length && values.containsAll(allValues)) {
    return '*';
  }

  final wildcard = token.split(',').first;
  final separator = wildcard.indexOf('/');
  final step = separator == -1 ? 1 : int.parse(wildcard.substring(separator + 1));
  final wildcardValues = <int>{
    for (final value in _range(spec.minimum, spec.maximum, step: step)) _normalize(value, spec),
  };
  final extras = values.where((value) => !wildcardValues.contains(value));
  final prefix = step == 1 ? '*' : '*/$step';
  return extras.isEmpty ? prefix : '$prefix,${extras.join(',')}';
}

int _parseValue(String source, _FieldSpec spec) {
  final named = spec.names[source];
  final value = named ?? (_decimal.hasMatch(source) ? int.tryParse(source) : null);
  if (value == null) throw _InvalidCron(spec.name, 'Invalid value "$source".');
  _validate(value, spec);
  return value;
}

final _decimal = RegExp(r'^\d+$');

void _validate(int value, _FieldSpec spec) {
  if (value < spec.minimum || value > spec.maximum) {
    throw _InvalidCron(
      spec.name,
      '$value is outside ${spec.minimum}..${spec.maximum}.',
    );
  }
}

int _normalize(int value, _FieldSpec spec) {
  return identical(spec, _weekdaySpec) && value == 7 ? 0 : value;
}

Iterable<int> _range(int start, int end, {int step = 1}) sync* {
  for (var value = start; value <= end; value += step) {
    yield value;
    // Stop before addition so an oversized step cannot overflow the integer.
    if (step > end - value) return;
  }
}

final class _InvalidCron implements Exception {
  const _InvalidCron(this.field, this.message);

  final String field;
  final String message;
}
