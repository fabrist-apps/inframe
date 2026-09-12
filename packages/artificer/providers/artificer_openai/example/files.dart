import 'package:artificer_core/artificer_core.dart';
import 'package:artificer_core/transport.dart';
import 'package:artificer_openai/artificer_openai.dart';
import 'package:conflux/conflux.dart';

Future<void> main() async {
  final provider = OpenAIProvider(apiKey: 'caller-supplied-key');
  try {
    final upload = provider.files.create(
      UploadSource.bytes(
        [1, 2, 3],
        filename: 'context.txt',
        mimeType: 'text/plain',
      ),
      purpose: OpenAIFilePurpose.userData,
    );

    if (const bool.fromEnvironment('RUN_OPENAI_EXAMPLE')) {
      final file = (await upload.runFuture()).value;
      final reference = file.asResponseSource(mimeType: 'text/plain');
      await provider
          .languageModel('caller-supplied-model')
          .generate(
            GenerationRequest(
              messages: [
                UserMessage([
                  MediaInputPart(
                    kind: MediaKind.document,
                    mimeType: reference.mimeType,
                    source: reference,
                  ),
                ]),
              ],
            ),
          )
          .runFuture();
      await provider.files.content(file.id).runDrain().runFuture();
      await provider.files.delete(file.id).runFuture();
    }
  } finally {
    // Closing the client releases local I/O only; it never deletes remote files.
    await provider.close();
  }
}
