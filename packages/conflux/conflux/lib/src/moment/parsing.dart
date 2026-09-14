import 'package:conflux/result.dart';

import 'package:conflux/src/moment/moment_error.dart';
import 'package:conflux/src/moment/moment_parts.dart';

final _timestamp = RegExp(
  r'^(\d{4}|-\d{4}|[+-]\d{6})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.(\d{1,6}))?(Z|([+-])(\d{2}):(\d{2})(?::(\d{2}))?)$',
);

/// Strictly decodes syntax; a null offset denotes the UTC marker, not fixed zero.
Result<({MomentParts parts, Duration? offset}), MomentError> parseTimestamp(String input) {
  final match = _timestamp.firstMatch(input);
  if (match == null || match.end != input.length) {
    return const Failure(
      MomentError(
        MomentErrorKind.invalidFormat,
        'Expected an ISO year and -MM-DDTHH:mm:ss[.fraction](Z|±HH:MM[:SS]).',
      ),
    );
  }
  int number(int index) => int.parse(match[index]!);
  if (formatYear(number(1)) != match[1]) {
    return const Failure(
      MomentError(
        MomentErrorKind.invalidFormat,
        'Use four year digits (with a minus for negative years), or signed six digits outside -9999–9999.',
      ),
    );
  }
  final fraction = int.parse((match[7] ?? '').padRight(6, '0'));
  final parts = MomentParts(
    year: number(1),
    month: number(2),
    day: number(3),
    hour: number(4),
    minute: number(5),
    second: number(6),
    millisecond: fraction ~/ 1000,
    microsecond: fraction % 1000,
  );
  final error = validateParts(parts);
  if (error != null) return Failure(error);
  Duration? offset;
  if (match[8] != 'Z') {
    final hours = number(10);
    final minutes = number(11);
    final seconds = int.parse(match[12] ?? '0');
    if (hours > 23 || minutes > 59 || seconds > 59) {
      return const Failure(
        MomentError(
          MomentErrorKind.invalidOffset,
          'Offset components must be 00–23 hours and 00–59 minutes/seconds.',
          field: 'offset',
        ),
      );
    }
    offset = Duration(
      seconds: (hours * 3600 + minutes * 60 + seconds) * (match[9] == '-' ? -1 : 1),
    );
  }
  return Success((parts: parts, offset: offset));
}

/// Renders calendar fields without locale, rounding, or device-zone conversion.
String formatParts(MomentParts p, {bool dateOnly = false}) {
  String pad(int value, int width) => value.toString().padLeft(width, '0');
  final date = '${formatYear(p.year)}-${pad(p.month, 2)}-${pad(p.day, 2)}';
  if (dateOnly) return date;
  return '${date}T${pad(p.hour, 2)}:${pad(p.minute, 2)}:${pad(p.second, 2)}.'
      '${pad(p.millisecond, 3)}${pad(p.microsecond, 3)}';
}

/// Includes historical offset seconds only when nonzero.
String formatOffset(Duration offset) {
  final seconds = offset.inSeconds.abs();
  String pad(int value) => value.toString().padLeft(2, '0');
  return '${offset.isNegative ? '-' : '+'}${pad(seconds ~/ 3600)}:${pad(seconds ~/ 60 % 60)}'
      '${seconds % 60 == 0 ? '' : ':${pad(seconds % 60)}'}';
}

/// Uses Dart's ISO year spelling, including year zero and signed extended years.
String formatYear(int year) {
  if (year >= 0 && year <= 9999) return year.toString().padLeft(4, '0');
  if (year >= -9999 && year < 0) return '-${(-year).toString().padLeft(4, '0')}';
  return '${year < 0 ? '-' : '+'}${year.abs().toString().padLeft(6, '0')}';
}
