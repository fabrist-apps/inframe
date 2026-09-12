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
        .create(
          GoogleInteractionRequest(
            model: 'gemini-3-flash-preview',
            input: GoogleInteractionInput.text('Name one moon of Jupiter.'),
            store: true,
          ),
        )
        .runFuture();
    stdout.writeln('Created ${first.value.id}: ${first.value.status.name}');

    final interactionId = first.value.id;
    if (interactionId != null) {
      final current = await provider.interactions.retrieve(interactionId).runFuture();
      stdout.writeln('Retrieved ${current.value.id}: ${current.value.status.name}');

      // Continuation is explicit; the provider stores no last interaction.
      final next = await provider.interactions
          .create(
            GoogleInteractionRequest(
              model: 'gemini-3-flash-preview',
              input: GoogleInteractionInput.text('Name another one.'),
              previousInteractionId: interactionId,
              store: true,
            ),
          )
          .runFuture();
      final nextId = next.value.id;
      if (nextId != null) {
        await provider.interactions.cancel(nextId).runFuture();
        await provider.interactions.delete(nextId).runFuture();
      }
      await provider.interactions.delete(interactionId).runFuture();
    }
  } finally {
    await provider.close();
  }
}
