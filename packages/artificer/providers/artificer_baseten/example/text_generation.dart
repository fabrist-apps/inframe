import 'package:artificer_baseten/artificer_baseten.dart';
import 'package:artificer_core/artificer_core.dart';
import 'package:conflux/conflux.dart';

Future<void> main() async {
  const credential = 'caller-supplied-key';
  const catalogModelId = 'caller-supplied-catalog-model';
  const servedModelId = 'caller-supplied-served-model';
  final deploymentBaseUrl = Uri.parse(
    'https://model-id.api.baseten.co/environments/production/sync/v1',
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
    if (const bool.fromEnvironment('RUN_BASETEN_EXAMPLE')) {
      await catalogOperation.runFuture();
      await deploymentOperation.runFuture();
    }
  } finally {
    await provider.close();
  }
}
