import 'package:artificer_openai/artificer_openai.dart';
import 'package:conflux/conflux.dart';

Future<void> main() async {
  final provider = OpenAIProvider(apiKey: 'caller-supplied-key');
  try {
    final create = provider.responses.create(
      OpenAIResponseRequest(
        model: 'caller-supplied-model',
        input: [OpenAIResponseInputMessage.userText('Run this in the background.')],
        background: true,
        store: true,
      ),
    );
    final retrieve = provider.responses.retrieve('caller-supplied-response-id');
    final cancel = provider.responses.cancel('caller-supplied-response-id');
    final models = provider.models.list();

    // These cold operations perform no I/O unless the caller runs each one explicitly.
    if (const bool.fromEnvironment('RUN_OPENAI_EXAMPLE')) {
      await create.runFuture();
      await retrieve.runFuture();
      await cancel.runFuture();
      await models.runFuture();
    }
  } finally {
    await provider.close();
  }
}
