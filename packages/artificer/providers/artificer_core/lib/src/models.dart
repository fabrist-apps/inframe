import 'package:artificer_core/src/capabilities.dart';
import 'package:artificer_core/src/embeddings/embeddings.dart';
import 'package:artificer_core/src/errors.dart';
import 'package:artificer_core/src/generation/generation.dart';
import 'package:conflux/conflux.dart';

/// Shared language-model capabilities.
final class ModelCapabilities {
  /// Creates a [ModelCapabilities].
  ModelCapabilities(Map<ModelCapability, CapabilitySupport> values)
    : _values = Map.unmodifiable(values);

  final Map<ModelCapability, CapabilitySupport> _values;

  /// Returns the declared support level, or [CapabilitySupport.unknown].
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
  /// Text generation.
  textGeneration,

  /// Streaming generation.
  streaming,

  /// The application tool declarations available to the model.
  tools,

  /// JSON object and JSON Schema output.
  structuredOutput,

  /// The image input.
  imageInput,

  /// The audio input.
  audioInput,

  /// Video input.
  videoInput,

  /// The document input.
  documentInput,
}

/// Common language generation implemented by provider-specific models.
abstract interface class LanguageModel {
  /// The stable provider identifier used in diagnostics and replay data.
  String get providerId;

  /// The provider-local model identifier.
  String get modelId;

  /// The model capabilities known by this provider.
  ModelCapabilities get capabilities;

  /// Runs one language-generation request.
  Effect<GenerationResult, AiError> generate(GenerationRequest request);

  /// Creates a cold stream for one generation request per consumption.
  Flow<GenerationEvent, AiError> stream(GenerationRequest request);
}

/// Common embeddings implemented by provider-specific models.
abstract interface class EmbeddingModel {
  /// The stable provider identifier used in diagnostics and replay data.
  String get providerId;

  /// The provider-local model identifier.
  String get modelId;

  /// The model capabilities known by this provider.
  EmbeddingCapabilities get capabilities;

  /// Runs one synchronous embedding request.
  Effect<EmbeddingResult, AiError> embed(EmbeddingRequest request);
}
