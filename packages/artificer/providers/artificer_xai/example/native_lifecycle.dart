import 'package:artificer_xai/artificer_xai.dart';
import 'package:conflux/conflux.dart';

Future<void> main() async {
  final provider = XaiProvider(apiKey: 'caller-supplied-key');
  try {
    final create = provider.responses.create(
      XaiResponseRequest(
        model: 'caller-supplied-model',
        input: [XaiResponseInputMessage.userText('Store this response.')],
        store: true,
        previousResponseId: 'caller-supplied-previous-response-id',
      ),
    );
    final retrieve = provider.responses.retrieve('caller-supplied-response-id');
    final inputItems = provider.responses.listInputItems('caller-supplied-response-id');
    final compact = provider.responses.compact(
      XaiCompactResponseRequest(
        model: 'caller-supplied-model',
        input: [XaiResponseInputMessage.userText('Compact this explicit history.')],
      ),
    );

    // These cold operations perform no I/O unless the caller runs each one explicitly.
    if (const bool.fromEnvironment('RUN_XAI_EXAMPLE')) {
      await create.runFuture();
      await retrieve.runFuture();
      await inputItems.runFuture();
      await compact.runFuture();
    }
  } finally {
    await provider.close();
  }
}
