/// Metric instrument registry borrowed from one Chronicler runtime.
abstract interface class ChroniclerMetrics {
  /// Returns a counter that records nonnegative interval changes.
  ChroniclerCounter counter(String name, {String unit = '1'});

  /// Returns an up/down counter that records signed interval changes.
  ChroniclerUpDownCounter upDownCounter(String name, {String unit = '1'});

  /// Returns a setter gauge that records the latest interval observation.
  ChroniclerGauge gauge(String name, {String unit = '1'});

  /// Returns a histogram with explicit upper-inclusive bucket boundaries.
  ChroniclerHistogram histogram(
    String name, {
    required List<num> boundaries,
    String unit = '1',
  });
}

/// Records nonnegative changes into bounded interval aggregates.
// The interface keeps construction and lifecycle control inside the runtime.
// ignore: one_member_abstracts
abstract interface class ChroniclerCounter {
  /// Adds [value] to the current interval for [attributes].
  ///
  /// Dimensions are validated and redacted before selecting a series, so
  /// sensitive values replaced by the same marker intentionally share state.
  /// Values use finite double precision and may approximate large integers.
  void add(
    num value, {
    Map<String, Object?> attributes = const {},
  });
}

/// Records signed changes into bounded interval aggregates.
// The interface keeps construction and lifecycle control inside the runtime.
// ignore: one_member_abstracts
abstract interface class ChroniclerUpDownCounter {
  /// Adds [value] to the current interval for [attributes].
  ///
  /// The exported sum is the signed net change during the interval. Use a
  /// gauge for an absolute current value.
  void add(
    num value, {
    Map<String, Object?> attributes = const {},
  });
}

/// Records the latest current value observed during each interval.
// The interface keeps construction and lifecycle control inside the runtime.
// ignore: one_member_abstracts
abstract interface class ChroniclerGauge {
  /// Sets the latest [value] for [attributes] in the current interval.
  ///
  /// Call this method again in every interval that should emit a value.
  void set(
    num value, {
    Map<String, Object?> attributes = const {},
  });
}

/// Records distributions using explicit upper-inclusive bucket boundaries.
// The interface keeps construction and lifecycle control inside the runtime.
// ignore: one_member_abstracts
abstract interface class ChroniclerHistogram {
  /// Records [value] in the current interval for [attributes].
  void record(
    num value, {
    Map<String, Object?> attributes = const {},
  });
}
