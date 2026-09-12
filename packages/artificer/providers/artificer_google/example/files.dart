import 'package:artificer_core/artificer_core.dart';
import 'package:artificer_core/transport.dart';
import 'package:artificer_google/artificer_google.dart';
import 'package:conflux/conflux.dart';

Future<void> main() async {
  final provider = GoogleProvider(apiKey: 'caller-supplied-key');
  try {
    final upload = provider.files.upload(
      UploadSource.bytes(
        [1, 2, 3],
        filename: 'context.txt',
        mimeType: 'text/plain',
      ),
    );

    if (const bool.fromEnvironment('RUN_GOOGLE_EXAMPLE')) {
      var file = (await upload.runFuture()).value;

      // Upload completion is not readiness. Inspect once, then let the caller
      // choose whether and when to check again; the SDK never polls for it.
      if (file.state == GoogleFileState.processing) {
        file = (await provider.files.retrieve(file.name).runFuture()).value;
      }
      if (file.state == GoogleFileState.active) {
        final source = file.asMediaSource();
        await provider
            .languageModel('caller-supplied-model')
            .generate(
              GenerationRequest(
                messages: [
                  UserMessage([
                    MediaInputPart(
                      kind: MediaKind.document,
                      mimeType: source.mimeType,
                      source: source,
                    ),
                  ]),
                ],
              ),
            )
            .runFuture();
      }

      // Pagination and deletion are always explicit caller decisions.
      await provider.files.list(pageSize: 20).runFuture();
      await provider.files.delete(file.name).runFuture();
    }
  } finally {
    // Closing releases local I/O only; it never deletes remote files.
    await provider.close();
  }
}
