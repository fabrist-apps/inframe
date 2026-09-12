import 'dart:async';

import 'package:artificer_baseten/src/chat/chat_resource.dart';
import 'package:artificer_baseten/src/options.dart';
import 'package:artificer_core/artificer_core.dart';
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
  }

  final String _apiKey;
  final http.Client? _httpClient;
  final List<ProviderHttpClient> _clients = [];
  Future<void>? _closeFuture;

  /// Typed native catalog Chat Completions operations.
  late final BasetenChatCompletionsResource chatCompletions;

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
    return BasetenDeployment._(BasetenChatCompletionsResource(client));
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

/// Compatible inference operations bound to one explicit deployment location.
final class BasetenDeployment {
  BasetenDeployment._(this.chatCompletions);

  /// Typed native Chat Completions operations at this deployment.
  final BasetenChatCompletionsResource chatCompletions;

  /// Creates a common language model with a separate served model name.
  BasetenLanguageModel languageModel(
    String modelId, {
    BasetenModelOptions? options,
  }) => BasetenLanguageModel._(
    chatCompletions,
    _nonEmpty(modelId, 'modelId'),
    options ?? BasetenModelOptions(),
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
