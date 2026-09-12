import 'package:artificer_anthropic/artificer_anthropic.dart';
import 'package:artificer_core/transport.dart';
import 'package:conflux/conflux.dart';

Future<void> main() async {
  final provider = AnthropicProvider(apiKey: 'caller-supplied-key');
  try {
    final upload = provider.files.upload(
      UploadSource.bytes(
        [1, 2, 3],
        filename: 'context.txt',
        mimeType: 'text/plain',
      ),
      expiresInSeconds: 3600,
    );

    if (const bool.fromEnvironment('RUN_ANTHROPIC_FILES_EXAMPLE')) {
      final file = (await upload.runFuture()).value;
      final reference = file.asMessageSource();
      final firstPage = (await provider.files.list(limit: 20).runFuture()).value;
      if (firstPage.nextPage case final nextPage?) {
        await provider.files.list(limit: 20, page: nextPage).runFuture();
      }
      if (file.downloadable ?? false) {
        await provider.files.download(file.id).runDrain().runFuture();
      }

      // Passing this reference to Messages does not fetch, upload, poll, or
      // delete the file. Remote deletion remains an explicit caller decision.
      reference.toDart();
      await provider.files.delete(file.id).runFuture();
    }
  } finally {
    // Closing the provider releases local HTTP resources, not remote files.
    await provider.close();
  }
}
