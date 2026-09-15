import 'package:conflux/src/val/issue.dart';
import 'package:conflux/src/val/schema.dart';

/// A schema with a non-nullable string output.
typedef StringSchema = Schema<String>;

/// String constraints preserve access to other string constraints.
extension StringChecks on Schema<String> {
  /// Requires at least [minimum] UTF-16 code units.
  StringSchema minLength(int minimum, {String? code, String? message}) =>
      _length(minimum, (length) => length >= minimum, 'MIN_LENGTH', 'at least', code, message);

  /// Requires at most [maximum] UTF-16 code units.
  StringSchema maxLength(int maximum, {String? code, String? message}) =>
      _length(maximum, (length) => length <= maximum, 'MAX_LENGTH', 'at most', code, message);

  /// Requires exactly [length] UTF-16 code units.
  StringSchema length(int length, {String? code, String? message}) =>
      _length(length, (actual) => actual == length, 'LENGTH', 'exactly', code, message);

  /// Alias for minLength(1).
  StringSchema notEmpty({String? code, String? message}) =>
      minLength(1, code: code, message: message);

  StringSchema _length(
    int count,
    bool Function(int) accepts,
    String defaultCode,
    String comparison,
    String? code,
    String? message,
  ) => withCheck(
    (value) => accepts(value.length),
    IssueTemplate(
      code ?? defaultCode,
      (name) =>
          message ??
          '${name == null ? 'Must' : '$name must'} contain $comparison $count ${count == 1 ? 'character' : 'characters'}',
    ),
  );
}

/// Explicit, non-normalizing first-version string format profiles.
extension StringFormats on Schema<String> {
  /// Matches the complete email profile, including rejection of trailing newlines.
  StringSchema email({String? code, String? message}) => _format(
    (value) => _fullMatch(_email, value),
    'INVALID_EMAIL',
    (name) => '${name == null ? 'Must' : '$name must'} be a valid email address',
    code,
    message,
  );

  /// Accepts an absolute URI with a scheme and nonempty host, without network I/O.
  StringSchema url({String? code, String? message}) => _format(
    (value) {
      final uri = Uri.tryParse(value);
      return uri != null && uri.hasScheme && uri.host.isNotEmpty;
    },
    'INVALID_URL',
    (name) => '${name == null ? 'Must' : '$name must'} be an absolute URI with a scheme and host',
    code,
    message,
  );

  /// Accepts canonical UUIDs (versions 1–8, RFC variant), nil, or all ones.
  StringSchema uuid({String? code, String? message}) => _format(
    (value) => _fullMatch(_uuid, value),
    'INVALID_UUID',
    (name) => '${name == null ? 'Must' : '$name must'} be a valid UUID',
    code,
    message,
  );

  /// Uses RegExp.hasMatch; callers add anchors when they need a whole-string match.
  StringSchema matches(RegExp pattern, {String? code, String? message}) => _format(
    pattern.hasMatch,
    'PATTERN',
    (name) => '${name == null ? 'Must' : '$name must'} match the required pattern',
    code,
    message,
  );

  /// Requires a case-sensitive literal prefix.
  StringSchema startsWith(String text, {String? code, String? message}) => _format(
    (value) => value.startsWith(text),
    'STARTS_WITH',
    (name) => '${name == null ? 'Must' : '$name must'} start with "$text"',
    code,
    message,
  );

  /// Requires a case-sensitive literal suffix.
  StringSchema endsWith(String text, {String? code, String? message}) => _format(
    (value) => value.endsWith(text),
    'ENDS_WITH',
    (name) => '${name == null ? 'Must' : '$name must'} end with "$text"',
    code,
    message,
  );

  /// Requires case-sensitive literal text, not a regular expression.
  StringSchema contains(String text, {String? code, String? message}) => _format(
    (value) => value.contains(text),
    'CONTAINS',
    (name) => '${name == null ? 'Must' : '$name must'} contain "$text"',
    code,
    message,
  );

  /// Accepts IPv4, IPv6, or either when version is null. Invalid versions throw.
  StringSchema ip({int? version, String? code, String? message}) {
    if (version != null && version != 4 && version != 6) {
      throw ArgumentError.value(version, 'version', 'Must be null, 4, or 6');
    }

    final label = version == null ? 'IP' : 'IPv$version';

    return _format(
      (value) => switch (version) {
        4 => _ipv4(value),
        6 => _ipv6(value),
        _ => _ipv4(value) || _ipv6(value),
      },
      'INVALID_${label.toUpperCase()}',
      (name) => '${name == null ? 'Must' : '$name must'} be a valid $label address',
      code,
      message,
    );
  }

  /// Accepts exactly four decimal octets with no leading zeros or whitespace.
  StringSchema ipv4({String? code, String? message}) =>
      ip(version: 4, code: code, message: message);

  /// Uses Uri.parseIPv6Address, excluding brackets, zone IDs, and whitespace.
  StringSchema ipv6({String? code, String? message}) =>
      ip(version: 6, code: code, message: message);

  StringSchema _format(
    bool Function(String) accepts,
    String defaultCode,
    String Function(String? name) defaultMessage,
    String? code,
    String? message,
  ) => withCheck(
    accepts,
    IssueTemplate(code ?? defaultCode, (name) => message ?? (defaultMessage(name))),
  );

  static final _email = RegExp(
    r"^(?!\.)(?!.*\.\.)([A-Za-z0-9_'+\-\.]*)[A-Za-z0-9_+-]@([A-Za-z0-9][A-Za-z0-9\-]*\.)+[A-Za-z]{2,}$",
  );
  static final _uuid = RegExp(
    r'^([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}|00000000-0000-0000-0000-000000000000|[fF]{8}-[fF]{4}-[fF]{4}-[fF]{4}-[fF]{12})$',
  );
  static final _octet = RegExp(r'^(0|[1-9][0-9]{0,2})$');
  static final _whitespace = RegExp(r'\s');

  static bool _fullMatch(RegExp pattern, String value) {
    final match = pattern.firstMatch(value);

    return match != null && match.start == 0 && match.end == value.length;
  }

  static bool _ipv4(String value) {
    final parts = value.split('.');

    return parts.length == 4 &&
        parts.every((part) => _fullMatch(_octet, part) && int.parse(part) <= 255);
  }

  static bool _ipv6(String value) {
    if (value.isEmpty ||
        value.contains('[') ||
        value.contains(']') ||
        value.contains('%') ||
        _whitespace.hasMatch(value)) {
      return false;
    }

    try {
      Uri.parseIPv6Address(value);
      return true;
    } on FormatException {
      return false;
    }
  }
}
