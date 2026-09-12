import 'package:artificer_core/json.dart';

/// Immutable Baseten-specific defaults for compatible chat inference.
final class BasetenModelOptions {
  /// Creates provider-specific model options.
  BasetenModelOptions({
    this.topK,
    this.repetitionPenalty,
    JsonObject? extraBody,
  }) : extraBody = extraBody ?? JsonObject({}) {
    if (topK != null && topK! <= 0) {
      throw ArgumentError.value(topK, 'topK', 'must be positive');
    }
    if (repetitionPenalty != null && repetitionPenalty! <= 0) {
      throw ArgumentError.value(
        repetitionPenalty,
        'repetitionPenalty',
        'must be positive',
      );
    }
  }

  /// Limits sampling to the most likely tokens when supported by the model.
  final int? topK;

  /// Penalizes repeated tokens when supported by the model.
  final double? repetitionPenalty;

  /// Forward-compatible Baseten fields outside the typed snapshot.
  final JsonObject extraBody;
}
