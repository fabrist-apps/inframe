/// Whether [value] is a nonempty HTTP token.
bool isHttpToken(String value) => value.isNotEmpty && value.codeUnits.every(_isTokenCodeUnit);

bool _isTokenCodeUnit(int unit) {
  const separators = <int>{
    0x28,
    0x29,
    0x3c,
    0x3e,
    0x40,
    0x2c,
    0x3b,
    0x3a,
    0x5c,
    0x22,
    0x2f,
    0x5b,
    0x5d,
    0x3f,
    0x3d,
    0x7b,
    0x7d,
  };

  return unit > 0x20 && unit < 0x7f && !separators.contains(unit);
}

/// Returns a valid method token unchanged, preserving case.
String validateMethod(String method) {
  if (!isHttpToken(method)) {
    throw ArgumentError.value(method, 'method', 'must be a nonempty HTTP token');
  }

  return method;
}

/// Checks a port range, including zero for ephemeral binding.
void validatePort(int port, String name) {
  if (port < 0 || port > 65535) {
    throw ArgumentError.value(port, name, 'must be from 0 through 65535');
  }
}
