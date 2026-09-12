import 'package:artificer_anthropic/artificer_anthropic.dart';
import 'package:conflux/conflux.dart';

Future<void> main() async {
  final provider = AnthropicProvider(apiKey: 'caller-supplied-key');
  try {
    final count = provider.messages.countTokens(
      AnthropicMessageTokensRequest(
        model: 'caller-supplied-model',
        messages: [AnthropicInputMessage.userText('Count this prompt.')],
      ),
    );
    final firstPage = provider.models.list(limit: 20);
    final exactModel = provider.models.retrieve('caller-supplied-model');

    if (const bool.fromEnvironment('RUN_ANTHROPIC_EXAMPLE')) {
      await count.runFuture();
      await firstPage.runFuture();
      await exactModel.runFuture();
    }
  } finally {
    await provider.close();
  }
}
