import 'dart:collection';

import 'package:conflux/result.dart';
import 'package:timezone/timezone.dart';

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
  });

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
  /// starts with `*`, including `*/step`, both must match.
  bool matches(DateTime instant) {
    final local = TZDateTime.from(instant, location);
    if (!_seconds.values.contains(local.second) ||
        !_minutes.values.contains(local.minute) ||
        !_hours.values.contains(local.hour) ||
        !_months.values.contains(local.month)) {
      return false;
    }
    final dayMatches = _days.values.contains(local.day);
    final weekdayMatches = _weekdays.values.contains(local.weekday % 7);
    if (!_days.startsWithWildcard && !_weekdays.startsWithWildcard) {
      return dayMatches || weekdayMatches;
    }
    return dayMatches && weekdayMatches;
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
}

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
    final step = stepParts.length == 1 ? 1 : int.tryParse(stepParts[1]);
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
    for (var value = start; value <= end; value += step) {
      values.add(_normalize(value, spec));
    }
  }
  if (values.isEmpty) throw _InvalidCron(spec.name, 'The field matches no values.');
  return _CronField(
    values,
    text: token,
    startsWithWildcard: token.startsWith('*'),
  );
}

int _parseValue(String source, _FieldSpec spec) {
  final value = spec.names[source] ?? int.tryParse(source);
  if (value == null) throw _InvalidCron(spec.name, 'Invalid value "$source".');
  _validate(value, spec);
  return value;
}

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

Iterable<int> _range(int start, int end) sync* {
  for (var value = start; value <= end; value += 1) {
    yield value;
  }
}

final class _InvalidCron implements Exception {
  const _InvalidCron(this.field, this.message);

  final String field;
  final String message;
}
