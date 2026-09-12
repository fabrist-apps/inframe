/// Whether a model capability is known to be available.
enum CapabilitySupport {
  /// The capability is known to be available.
  supported,

  /// The capability is known to be unavailable.
  unsupported,

  /// The provider has not declared whether the capability is available.
  unknown,
}
