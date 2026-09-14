/// Internal calendar coordinate for recurrence enumeration, not a UTC instant.
///
/// A native UTC date is used only to normalize Gregorian day arithmetic. The
/// coordinate can briefly leave Moment's range so searches can detect an edge.
final class CalendarDate {
  /// Creates a calendar date for internal enumeration.
  CalendarDate(int year, [int month = 1, int day = 1]) : _date = DateTime.utc(year, month, day);

  CalendarDate._(this._date);

  /// Selects the date of an encoded local-field coordinate.
  factory CalendarDate.fromWallMicroseconds(int micros) {
    final date = DateTime.fromMicrosecondsSinceEpoch(micros, isUtc: true);
    return CalendarDate(date.year, date.month, date.day);
  }

  final DateTime _date;

  /// Calendar year, including a search sentinel outside 1–9999.
  int get year => _date.year;

  /// Calendar month.
  int get month => _date.month;

  /// Day of month.
  int get day => _date.day;

  /// Monday-based Gregorian weekday.
  int get weekday => _date.weekday;

  /// The local midnight coordinate, before applying any timezone offset.
  int get wallMicroseconds => _date.microsecondsSinceEpoch;

  /// Advances calendar dates without resolving them in a zone.
  CalendarDate addDays(int days) => CalendarDate._(_date.add(Duration(days: days)));

  /// Encodes clock fields within this candidate date without creating an instant.
  int at(int hour, int minute, int second) =>
      wallMicroseconds + Duration(hours: hour, minutes: minute, seconds: second).inMicroseconds;
}
