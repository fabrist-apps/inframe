import 'package:conflux/conflux.dart';

import 'errors.dart';
import 'generation/generation.dart';

/// Whether a model capability is known to be available.
enum CapabilitySupport { supported, unsupported, unknown }

/// Shared language-model capabilities.
final class ModelCapabilities {
  ModelCapabilities(Map<ModelCapability, CapabilitySupport> values)
    : _values = Map.unmodifiable(values);

  final Map<ModelCapability, CapabilitySupport> _values;

  CapabilitySupport operator [](ModelCapability capability) =>
      _values[capability] ?? CapabilitySupport.unknown;

  /// Returns a typed preflight error for the first known unsupported feature.
  UnsupportedFeatureError? validateRequested(Iterable<ModelCapability> requested) {
    for (final capability in requested) {
      if (this[capability] == CapabilitySupport.unsupported) {
        return UnsupportedFeatureError(
          'The model does not support ${capability.name}.',
          feature: capability.name,
        );
      }
    }
    return null;
  }
}

/// A shared language-model feature.
enum ModelCapability {
  textGeneration,
  streaming,
  tools,
  structuredOutput,
  imageInput,
  audioInput,
  videoInput,
  documentInput,
}

/// Common language generation implemented by provider-specific models.
abstract interface class LanguageModel {
  String get providerId;
  String get modelId;
  ModelCapabilities get capabilities;

  Effect<GenerationResult, AiError> generate(GenerationRequest request);
  Flow<GenerationEvent, AiError> stream(GenerationRequest request);
}
