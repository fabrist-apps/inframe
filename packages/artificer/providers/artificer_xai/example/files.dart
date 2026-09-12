import 'package:artificer_core/transport.dart';
import 'package:artificer_xai/artificer_xai.dart';
import 'package:conflux/conflux.dart';

Future<void> main() async {
  final provider = XaiProvider(apiKey: 'caller-supplied-key');
  try {
    final upload = provider.files.create(
      UploadSource.bytes(
        [1, 2, 3],
        filename: 'context.txt',
        mimeType: 'text/plain',
      ),
      expiresAfter: 3600,
    );

    if (const bool.fromEnvironment('RUN_XAI_EXAMPLE')) {
      final file = (await upload.runFuture()).value;
      try {
        await provider.files.retrieve(file.id).runFuture();
        await provider.files.content(file.id).runDrain().runFuture();
      } finally {
        await provider.files.delete(file.id).runFuture();
      }
    }
  } finally {
    // Closing the provider releases local I/O only; remote deletion is explicit.
    await provider.close();
  }
}
