import 'package:artificer_core/artificer_core.dart';
import 'package:artificer_openai/artificer_openai.dart';
import 'package:conflux/conflux.dart';

Future<void> main() async {
  const credential = 'caller-supplied-key';
  const modelId = 'caller-supplied-model';
  final provider = OpenAIProvider(apiKey: credential);
  try {
    // Constructing the operation is lazy. Applications run it in their own Conflux runtime.
    final operation = provider
        .languageModel(modelId)
        .generate(GenerationRequest(messages: [UserMessage.text('Explain this change.')]));
    if (const bool.fromEnvironment('RUN_OPENAI_EXAMPLE')) {
      await operation.runFuture();
    }
  } finally {
    await provider.close();
  }
}
