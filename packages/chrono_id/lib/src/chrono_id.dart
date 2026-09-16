import 'dart:math';

const _alphabet = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz';
const _timestampLength = 8;
const _minimumSize = 16;
const _timestampLimit = 218340105584896; // 62^8

/// Generates and validates timestamp-bearing string IDs.
abstract final class ChronoID {
  static final _generator = ChronoIdGenerator();

  /// Generates a Chrono ID with an optional [prefix].
  ///
  /// [size] is the body length, excluding the prefix and `_` separator. It
  /// must be at least 16. A non-null prefix must start with an ASCII letter
  /// and contain only ASCII letters and digits.
  static String generate({String? prefix, int size = 24}) =>
      _generator.generate(prefix: prefix, size: size);

  /// Returns whether [value] has the configured Chrono ID structure.
  ///
  /// This checks structure only. It does not normalize the value, establish
  /// provenance, or guarantee uniqueness. Invalid configuration throws an
  /// [ArgumentError].
  static bool isValid(
    String value, {
    String? prefix,
    int size = 24,
  }) => _generator.isValid(value, prefix: prefix, size: size);
}

/// Internal generator with controllable time and randomness for deterministic tests.
final class ChronoIdGenerator {
  /// Creates a generator using system time and secure randomness by default.
  ChronoIdGenerator({
    int Function()? clock,
    Random Function()? randomFactory,
  }) : _clock = clock ?? _systemClock,
       _randomFactory = randomFactory ?? Random.secure;

  final int Function() _clock;
  final Random Function() _randomFactory;
  Random? _random;

  /// Generates a Chrono ID using this generator's time and random sources.
  String generate({String? prefix, int size = 24}) {
    _validateConfiguration(prefix: prefix, size: size);

    final timestamp = _clock();
    final encodedTimestamp = _encodeTimestamp(timestamp);
    final suffix = _generateSuffix(size - _timestampLength);
    final body = '$encodedTimestamp$suffix';

    return prefix == null ? body : '${prefix}_$body';
  }

  /// Returns whether [value] has the configured Chrono ID structure.
  bool isValid(
    String value, {
    String? prefix,
    int size = 24,
  }) {
    _validateConfiguration(prefix: prefix, size: size);

    final separator = prefix == null ? '' : '${prefix}_';
    if (!value.startsWith(separator)) return false;

    final body = value.substring(separator.length);
    return body.length == size && body.codeUnits.every(_isAlphabetCharacter);
  }

  String _generateSuffix(int length) {
    final random = _random ??= _randomFactory();
    return List.generate(length, (_) => _alphabet[random.nextInt(_alphabet.length)]).join();
  }

  static String _encodeTimestamp(int timestamp) {
    if (timestamp < 0 || timestamp >= _timestampLimit) {
      throw RangeError.range(timestamp, 0, _timestampLimit - 1, 'millisecondsSinceEpoch');
    }

    var remaining = timestamp;
    final encoded = List.filled(_timestampLength, _alphabet[0]);
    for (var index = encoded.length - 1; remaining > 0; index--) {
      encoded[index] = _alphabet[remaining % _alphabet.length];
      remaining ~/= _alphabet.length;
    }
    return encoded.join();
  }

  static bool _isAlphabetCharacter(int codeUnit) =>
      codeUnit >= 48 && codeUnit <= 57 ||
      codeUnit >= 65 && codeUnit <= 90 ||
      codeUnit >= 97 && codeUnit <= 122;

  static int _systemClock() => DateTime.now().millisecondsSinceEpoch;
}

void _validateConfiguration({required String? prefix, required int size}) {
  if (size < _minimumSize) {
    throw ArgumentError.value(size, 'size', 'must be at least $_minimumSize');
  }
  if (prefix != null && !RegExp(r'^[A-Za-z][A-Za-z0-9]*$').hasMatch(prefix)) {
    throw ArgumentError.value(
      prefix,
      'prefix',
      'must start with an ASCII letter and contain only ASCII letters and digits',
    );
  }
}
