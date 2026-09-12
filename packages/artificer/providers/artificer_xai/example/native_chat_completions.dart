import 'package:artificer_core/json.dart';
import 'package:artificer_xai/artificer_xai.dart';
import 'package:conflux/conflux.dart';

Future<void> main() async {
  final provider = XaiProvider(apiKey: 'caller-supplied-key');
  try {
    final request = XaiChatRequest(
      model: 'caller-supplied-model',
      messages: [XaiChatMessage.userText('Return structured JSON.')],
      responseFormat: JsonObject({'type': 'json_object'}),
    );
    final create = provider.chatCompletions.create(request);
    final stream = provider.chatCompletions.stream(request).runCollect();

    if (const bool.fromEnvironment('RUN_XAI_EXAMPLE')) {
      final native = await create.runFuture();
      provider.chatCompletions.normalize(native, choiceIndex: 0);
      await stream.runFuture();
    }
  } finally {
    await provider.close();
  }
}
