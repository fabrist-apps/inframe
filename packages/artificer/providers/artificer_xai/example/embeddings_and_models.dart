import 'package:artificer_core/artificer_core.dart';
import 'package:artificer_xai/artificer_xai.dart';
import 'package:conflux/conflux.dart';

Future<void> main() async {
  final provider = XaiProvider(apiKey: 'caller-supplied-key');
  try {
    final embedding = provider
        .embeddingModel('caller-supplied-embedding-model')
        .embed(EmbeddingRequest(items: [EmbeddingInput.text('Embed this text.')]));
    final models = provider.models.listEmbedding();

    // These cold operations perform no I/O until the caller runs them.
    if (const bool.fromEnvironment('RUN_XAI_EXAMPLE')) {
      await embedding.runFuture();
      await models.runFuture();
    }
  } finally {
    await provider.close();
  }
}
