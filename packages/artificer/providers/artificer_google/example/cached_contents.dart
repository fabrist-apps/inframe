import 'dart:io';

import 'package:artificer_core/artificer_core.dart';
import 'package:artificer_google/artificer_google.dart';
import 'package:conflux/conflux.dart';

Future<void> main() async {
  final apiKey = Platform.environment['GEMINI_API_KEY'];
  if (apiKey == null || apiKey.isEmpty) {
    stderr.writeln('Set GEMINI_API_KEY before running this example.');
    return;
  }

  const modelId = 'gemini-2.5-flash';
  final provider = GoogleProvider(apiKey: apiKey);
  String? cacheName;
  try {
    final cache = await provider.cachedContents
        .create(
          GoogleCreateCachedContentRequest(
            model: 'models/$modelId',
            displayName: 'Product reference',
            contents: [
              GoogleContent(
                role: 'user',
                parts: [GooglePart.text('The product ships in blue and green.')],
              ),
            ],
            ttl: '3600s',
          ),
        )
        .runFuture();
    cacheName = cache.value.name;

    final result = await provider
        .languageModel(
          modelId,
          options: GoogleModelOptions(cachedContent: Setting.set(cacheName)),
        )
        .generate(
          GenerationRequest(messages: [UserMessage.text('Which colors are available?')]),
        )
        .runFuture();
    stdout.writeln(result.text);

    // Cache lifetime changes are explicit and limited to one expiration field.
    await provider.cachedContents
        .update(cacheName, GoogleCachedContentExpirationUpdate(ttl: '600s'))
        .runFuture();
  } finally {
    // Closing only releases local I/O. Remote deletion remains an explicit call.
    if (cacheName != null) {
      await provider.cachedContents.delete(cacheName).runFuture();
    }
    await provider.close();
  }
}
