import 'dart:io';

import 'package:artificer_google/artificer_google.dart';
import 'package:conflux/conflux.dart';

Future<void> main() async {
  final apiKey = Platform.environment['GEMINI_API_KEY'];
  if (apiKey == null || apiKey.isEmpty) {
    stderr.writeln('Set GEMINI_API_KEY before running this example.');
    exitCode = 64;
    return;
  }

  final provider = GoogleProvider(apiKey: apiKey);
  try {
    final first = await provider.interactions
        .stream(
          GoogleInteractionRequest(
            model: 'gemini-3-flash-preview',
            input: GoogleInteractionInput.text('Write one sentence about Jupiter.'),
          ),
        )
        .runFirst()
        .runFuture();
    if (first case Some(value: final GoogleInteractionCreatedEvent created)) {
      final interactionId = created.interaction.id;
      final cursor = created.eventId;
      if (interactionId != null && cursor != null) {
        await provider.interactions
            .streamRetrieve(interactionId, lastEventId: cursor)
            .runForEach(
              (event, _) => Effect.sync((_) {
                switch (event) {
                  case GoogleInteractionStepDeltaEvent(:final delta):
                    if (delta.text case final text?) stdout.write(text);
                  case GoogleInteractionCompletedEvent(:final interaction):
                    stdout.writeln('\n${interaction.status.name}');
                  default:
                }
              }),
            )
            .runFuture();
      }
    }
  } finally {
    await provider.close();
  }
}
