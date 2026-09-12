import 'dart:async';

import 'package:artificer_baseten/src/chat/chat_resource.dart';
import 'package:artificer_baseten/src/embeddings/embedding_models.dart';
import 'package:artificer_baseten/src/embeddings/embeddings_resource.dart';
import 'package:artificer_baseten/src/messages/messages_resource.dart';
import 'package:artificer_baseten/src/options.dart';
import 'package:artificer_baseten/src/prediction/prediction_endpoint.dart';
import 'package:artificer_core/artificer_core.dart';
import 'package:artificer_core/json.dart';
import 'package:artificer_core/transport.dart';
import 'package:conflux/conflux.dart';
import 'package:http/http.dart' as http;

const _providerId = 'baseten';

/// A Baseten client for catalog and caller-configured deployment inference.
final class BasetenProvider {
  /// Creates a provider with an explicit credential and optional catalog URL.
  BasetenProvider({
    required String apiKey,
    Uri? catalogBaseUrl,
    http.Client? httpClient,
  }) : _apiKey = _nonEmpty(apiKey, 'apiKey'),
       // The public parameter name is part of the required API.
       // ignore: prefer_initializing_formals
       _httpClient = httpClient {
    final client = _newClient(
      catalogBaseUrl ?? Uri.parse('https://inference.baseten.co/v1'),
      authorization: 'Bearer $_apiKey',
    );
    _clients.add(client);
    chatCompletions = BasetenChatCompletionsResource(client);
    final messagesClient = _newClient(
      catalogBaseUrl ?? Uri.parse('https://inference.baseten.co/v1'),
      authorization: 'Api-Key $_apiKey',
    );
    _clients.add(messagesClient);
    messages = BasetenMessagesResource(messagesClient);
  }

  final String _apiKey;
  final http.Client? _httpClient;
  final List<ProviderHttpClient> _clients = [];
  Future<void>? _closeFuture;

  /// Typed native catalog Chat Completions operations.
  late final BasetenChatCompletionsResource chatCompletions;

  /// Typed native beta Messages operations using Baseten authentication.
  late final BasetenMessagesResource messages;

  /// Creates a common catalog language model.
  BasetenLanguageModel languageModel(
    String modelId, {
    BasetenModelOptions? options,
  }) => BasetenLanguageModel._(
    chatCompletions,
    _nonEmpty(modelId, 'modelId'),
    options ?? BasetenModelOptions(),
  );

  /// Binds explicitly compatible operations to a deployment base URL.
  BasetenDeployment deployment({required Uri baseUrl}) {
    final client = _newClient(baseUrl, authorization: 'Api-Key $_apiKey');
    _clients.add(client);
    return BasetenDeployment._(
      BasetenChatCompletionsResource(client),
      BasetenEmbeddingsResource(client),
    );
  }

  /// Binds caller-defined JSON codecs to one exact custom prediction URL.
  ///
  /// [encode] and [decode] must be pure because every execution invokes them
  /// independently and concurrent executions may overlap.
  BasetenPredictionEndpoint<I, O> predictionEndpoint<I, O>({
    required Uri endpoint,
    required JsonValue Function(I input) encode,
    required O Function(JsonValue json) decode,
  }) {
    final binding = _predictionBinding(endpoint);
    final client = _newClient(
      binding.baseUrl,
      authorization: 'Api-Key $_apiKey',
    );
    _clients.add(client);
    return BasetenPredictionEndpoint(client, binding.path, encode, decode);
  }

  ProviderHttpClient _newClient(
    Uri baseUrl, {
    required String authorization,
  }) => ProviderHttpClient(
    baseUrl: _directoryUri(baseUrl),
    client: _httpClient,
    headers: {'authorization': authorization},
  );

  /// Interrupts provider-owned work and releases all owned HTTP resources.
  Future<void> close() => _closeFuture ??= Future.wait(
    _clients.map((client) => client.close()),
  );
}

({Uri baseUrl, String path}) _predictionBinding(Uri endpoint) {
  if (!endpoint.isAbsolute ||
      (endpoint.scheme != 'http' && endpoint.scheme != 'https') ||
      endpoint.host.isEmpty) {
    throw ArgumentError.value(endpoint, 'endpoint', 'must be an absolute HTTP(S) URL');
  }
  if (endpoint.hasFragment) {
    throw ArgumentError.value(endpoint, 'endpoint', 'must not contain a fragment');
  }
  final path = endpoint.hasQuery ? '${endpoint.path}?${endpoint.query}' : endpoint.path;
  return (
    baseUrl: endpoint.replace(path: '/', queryParameters: const {}),
    path: path,
  );
}

/// Compatible inference operations bound to one explicit deployment location.
final class BasetenDeployment {
  BasetenDeployment._(this.chatCompletions, this.embeddings);

  /// Typed native Chat Completions operations at this deployment.
  final BasetenChatCompletionsResource chatCompletions;

  /// Typed native embedding operations at this dedicated deployment.
  final BasetenEmbeddingsResource embeddings;

  /// Creates a common language model with a separate served model name.
  BasetenLanguageModel languageModel(
    String modelId, {
    BasetenModelOptions? options,
  }) => BasetenLanguageModel._(
    chatCompletions,
    _nonEmpty(modelId, 'modelId'),
    options ?? BasetenModelOptions(),
  );

  /// Creates a common text embedding model with a separate served model name.
  BasetenEmbeddingModel embeddingModel(
    String modelId, {
    BasetenEmbeddingOptions? options,
  }) => BasetenEmbeddingModel(
    embeddings,
    _nonEmpty(modelId, 'modelId'),
    options ?? BasetenEmbeddingOptions(),
  );
}

/// A Baseten compatible-chat adapter for the common language-model contract.
final class BasetenLanguageModel implements LanguageModel {
  BasetenLanguageModel._(this._chat, this.modelId, this.options);

  final BasetenChatCompletionsResource _chat;

  /// Immutable model defaults.
  final BasetenModelOptions options;

  @override
  final String modelId;

  @override
  String get providerId => _providerId;

  @override
  ModelCapabilities get capabilities => ModelCapabilities({
    ModelCapability.textGeneration: CapabilitySupport.supported,
    ModelCapability.streaming: CapabilitySupport.supported,
    ModelCapability.tools: CapabilitySupport.unknown,
    ModelCapability.structuredOutput: CapabilitySupport.unknown,
    ModelCapability.imageInput: CapabilitySupport.unknown,
    ModelCapability.audioInput: CapabilitySupport.unknown,
    ModelCapability.videoInput: CapabilitySupport.unknown,
    ModelCapability.documentInput: CapabilitySupport.unknown,
  });

  @override
  Effect<GenerationResult, AiError> generate(
    GenerationRequest request, {
    BasetenModelOptions? options,
  }) => _chat.generate(
    request,
    modelId: modelId,
    options: this.options,
    overrides: options,
  );

  @override
  Flow<GenerationEvent, AiError> stream(
    GenerationRequest request, {
    BasetenModelOptions? options,
  }) => _chat.streamCommon(
    request,
    modelId: modelId,
    options: this.options,
    overrides: options,
  );
}

Uri _directoryUri(Uri value) {
  if (!value.isAbsolute || (value.scheme != 'http' && value.scheme != 'https')) {
    throw ArgumentError.value(value, 'baseUrl', 'must be an absolute HTTP(S) URL');
  }
  return value.path.endsWith('/') ? value : value.replace(path: '${value.path}/');
}

String _nonEmpty(String value, String name) {
  if (value.isEmpty) throw ArgumentError.value(value, name, 'must not be empty');
  return value;
}
