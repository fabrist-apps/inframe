import 'package:artificer_core/artificer_core.dart';
import 'package:artificer_core/json.dart';

/// Immutable Baseten-specific defaults for compatible chat inference.
final class BasetenModelOptions {
  /// Creates provider-specific model options.
  BasetenModelOptions({
    Setting<int> topK = const Setting<int>.inherit(),
    Setting<double> repetitionPenalty = const Setting<double>.inherit(),
    JsonObject? extraBody,
  }) : topK = _normalizeSetting(topK),
       repetitionPenalty = _normalizeSetting(repetitionPenalty),
       extraBody = extraBody ?? JsonObject({}) {
    final collision = this.extraBody.values.keys.where(_typedFields.contains).firstOrNull;
    if (collision != null) {
      throw ArgumentError.value(this.extraBody, 'extraBody', 'field "$collision" is typed');
    }
    if (this.topK case SetSetting<int>(:final value) when value != -1 && value <= 0) {
      throw ArgumentError.value(value, 'topK', 'must be positive or -1');
    }
    if (this.repetitionPenalty case SetSetting<double>(:final value) when value <= 0) {
      throw ArgumentError.value(
        value,
        'repetitionPenalty',
        'must be positive',
      );
    }
  }

  /// Limits sampling to the most likely tokens when supported by the model.
  final Setting<int> topK;

  /// Penalizes repeated tokens when supported by the model.
  final Setting<double> repetitionPenalty;

  /// Forward-compatible Baseten fields outside the typed snapshot.
  final JsonObject extraBody;

  /// Resolves model defaults and optional per-call overrides into one snapshot.
  BasetenModelOptions resolve(BasetenModelOptions? call) {
    final resolvedTopK = call == null ? topK.resolve(null) : call.topK.resolve(topK.resolve(null));
    final resolvedPenalty = call == null
        ? repetitionPenalty.resolve(null)
        : call.repetitionPenalty.resolve(repetitionPenalty.resolve(null));
    return BasetenModelOptions(
      topK: resolvedTopK == null ? const Setting.clear() : Setting.set(resolvedTopK),
      repetitionPenalty: resolvedPenalty == null
          ? const Setting.clear()
          : Setting.set(resolvedPenalty),
      extraBody: JsonObject({
        ...extraBody.toDart(),
        ...?call?.extraBody.toDart(),
      }),
    );
  }
}

const _typedFields = {'top_k', 'repetition_penalty'};

Setting<T> _normalizeSetting<T>(Setting<T> setting) => switch (setting) {
  InheritSetting<T>() => Setting<T>.inherit(),
  SetSetting<T>(:final value) => Setting<T>.set(value),
  ClearSetting<T>() => Setting<T>.clear(),
};
