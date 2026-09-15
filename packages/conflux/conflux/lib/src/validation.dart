/// Rejects negative durations while retaining the original argument value.
void checkDuration(Duration value, String name) {
  if (value.isNegative) {
    throw ArgumentError.value(value, name, 'Must be non-negative');
  }
}

/// Rejects zero and negative counts.
void checkPositive(int value, String name) {
  if (value <= 0) {
    throw ArgumentError.value(value, name, 'Must be positive');
  }
}

/// Rejects negative counts, allowing zero.
void checkNonNegative(int value, String name) {
  if (value < 0) {
    throw ArgumentError.value(value, name, 'Must be non-negative');
  }
}
