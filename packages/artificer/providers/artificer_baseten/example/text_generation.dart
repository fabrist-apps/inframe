import 'package:artificer_baseten/artificer_baseten.dart';
import 'package:artificer_core/artificer_core.dart';
import 'package:artificer_core/json.dart';
import 'package:conflux/conflux.dart';

Future<void> main() async {
  const credential = 'caller-supplied-key';
  const catalogModelId = 'caller-supplied-catalog-model';
  const servedModelId = 'caller-supplied-served-model';
  final deploymentBaseUrl = Uri.parse(
    'https://model-id.api.baseten.co/environments/production/sync/v1',
  );
  final predictionUrl = Uri.parse(
    'https://model-id.api.baseten.co/environments/production/predict',
  );
  final provider = BasetenProvider(apiKey: credential);
  try {
    final request = GenerationRequest(
      messages: [UserMessage.text('Explain this change.')],
    );
    final catalogOperation = provider.languageModel(catalogModelId).generate(request);
    final deploymentOperation = provider
        .deployment(baseUrl: deploymentBaseUrl)
        .languageModel(servedModelId)
        .stream(request)
        .runCollect();
    final embeddingOperation = provider
        .deployment(baseUrl: deploymentBaseUrl)
        .embeddingModel(servedModelId)
        .embed(
          EmbeddingRequest(
            items: [EmbeddingInput.text('Deployment documentation')],
          ),
        );
    final rawPredictionOperation = provider
        .predictionEndpoint<String, JsonValue>(
          endpoint: predictionUrl,
          encode: (prompt) => JsonObject({'prompt': prompt, 'stream': true}),
          decode: (json) => json,
        )
        .predictRawStream('Explain this change.')
        .runCollect();
    if (const bool.fromEnvironment('RUN_BASETEN_EXAMPLE')) {
      await catalogOperation.runFuture();
      await deploymentOperation.runFuture();
      await embeddingOperation.runFuture();
      await rawPredictionOperation.runFuture();
    }
  } finally {
    await provider.close();
  }
}
