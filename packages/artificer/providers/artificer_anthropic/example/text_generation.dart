import 'package:artificer_anthropic/artificer_anthropic.dart';
import 'package:artificer_core/artificer_core.dart';
import 'package:conflux/conflux.dart';

Future<void> main() async {
  const credential = 'caller-supplied-key';
  const modelId = 'caller-supplied-model';
  final provider = AnthropicProvider(apiKey: credential);
  try {
    final request = GenerationRequest(
      messages: [UserMessage.text('Explain this change.')],
    );
    final generation = provider.languageModel(modelId).generate(request);
    final stream = provider.languageModel(modelId).stream(request).runCollect();
    if (const bool.fromEnvironment('RUN_ANTHROPIC_EXAMPLE')) {
      await generation.runFuture();
      await stream.runFuture();
    }
  } finally {
    await provider.close();
  }
}
