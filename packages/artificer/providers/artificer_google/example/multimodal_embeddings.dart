import 'dart:io';

import 'package:artificer_core/artificer_core.dart';
import 'package:artificer_google/artificer_google.dart';
import 'package:conflux/conflux.dart';

Future<void> main() async {
  const credential = 'caller-supplied-key';
  final provider = GoogleProvider(apiKey: credential);
  try {
    final model = provider.embeddingModel('gemini-embedding-2');
    final imagePart = MediaInputPart(
      kind: MediaKind.image,
      mimeType: 'image/png',
      source: BytesMediaSource(const [137, 80, 78, 71]),
    );
    final operation = model.embed(
      EmbeddingRequest(
        items: [
          EmbeddingInput.text('A diagram of the deployment'),
          EmbeddingInput([imagePart]),
        ],
      ),
    );

    // The two inputs use one synchronous batch request and produce two vectors.
    if (const bool.fromEnvironment('RUN_GOOGLE_EXAMPLE')) {
      final result = await operation.runFuture();
      stdout.writeln('Received ${result.vectors.length} vectors.');
    }
  } finally {
    await provider.close();
  }
}
