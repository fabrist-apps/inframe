import 'package:artificer_core/json.dart';
import 'package:artificer_openai/artificer_openai.dart';
import 'package:conflux/conflux.dart';

Future<void> main() async {
  final provider = OpenAIProvider(apiKey: 'caller-supplied-key');
  try {
    final request = OpenAIChatRequest(
      model: 'caller-supplied-model',
      messages: [OpenAIChatMessage.userText('Return structured JSON.')],
      responseFormat: JsonObject({'type': 'json_object'}),
    );
    final create = provider.chatCompletions.create(request);
    final stream = provider.chatCompletions.stream(request).runCollect();

    if (const bool.fromEnvironment('RUN_OPENAI_EXAMPLE')) {
      final native = await create.runFuture();
      provider.chatCompletions.normalize(native, choiceIndex: 0);
      await stream.runFuture();
    }
  } finally {
    await provider.close();
  }
}
