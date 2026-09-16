import 'package:artificer_core/src/errors.dart';
import 'package:artificer_core/src/generation/generation.dart';
import 'package:conflux/effect.dart';
import 'package:conflux/flow.dart';
import 'package:dart_mappable/dart_mappable.dart';

part 'models.mapper.dart';

/// Whether a feature is known to be supported.
@MappableEnum()
enum CapabilitySupport {
  /// Supported.
  supported,

  /// Unsupported.
  unsupported,

  /// Unknown.
  unknown,
}

/// Common text inference features.
@MappableEnum()
enum ModelCapability {
  /// Text generation.
  textGeneration,

  /// Streaming.
  streaming,

  /// Tools.
  tools,

  /// Structured output.
  structuredOutput,
}

/// Declared capabilities; unfamiliar models retain unknown support.
@MappableClass(generateMethods: GenerateMethods.encode | GenerateMethods.decode)
final class ModelCapabilities with ModelCapabilitiesMappable {
  /// Creates a [ModelCapabilities] retaining the supplied values.
  const ModelCapabilities([this.values = const {}]);

  /// Declared feature support; absent entries remain unknown.
  final Map<ModelCapability, CapabilitySupport> values;

  /// Returns declared support, or unknown for an unlisted feature.
  CapabilitySupport operator [](ModelCapability feature) =>
      values[feature] ?? CapabilitySupport.unknown;

  /// Decodes a map using the shipped generated mapper.
  static const fromMap = ModelCapabilitiesMapper.fromMap;

  /// Decodes a JSON string using the shipped generated mapper.
  static const fromJson = ModelCapabilitiesMapper.fromJson;
}

/// Common language generation with caller-owned history and execution.
abstract interface class LanguageModel {
  /// Stable provider identity.
  String get providerId;

  /// Nonempty provider-local model identifier.
  String get modelId;

  /// Known model capabilities, with unknown as the default.
  ModelCapabilities get capabilities;

  /// Describes one lazy generation request.
  Effect<GenerationResult, AiError> generate(GenerationRequest request);

  /// Describes one independent request per stream consumption.
  Flow<GenerationEvent, AiError> stream(GenerationRequest request);
}

/// Factory capability implemented only by providers offering text generation.
abstract interface class LanguageModelProvider {
  /// Creates a model handle without network discovery.
  LanguageModel languageModel(String modelId);
}
