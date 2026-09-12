import 'dart:io';

import 'package:artificer_core/artificer_core.dart';
import 'package:artificer_core/json.dart';
import 'package:artificer_core/transport.dart';
import 'package:conflux/conflux.dart';
import 'package:test/test.dart';

void main() {
  group('EmbeddingModel consumer', () {
    test('should issue one synchronous batch and restore provider order', () async {
      var requests = 0;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        requests++;
        request.response.write('''
          {"model":"actual-model","data":[
            {"index":1,"embedding":[3,4]},
            {"index":0,"embedding":[1,2]}
          ]}
        ''');
        await request.response.close();
      });
      final client = ProviderHttpClient(
        baseUrl: Uri.parse('http://${server.address.address}:${server.port}/'),
      );
      addTearDown(client.close);
      final model = _LoopbackEmbeddingModel(client, 'future-model');

      final result = await model
          .embed(
            EmbeddingRequest(
              items: [EmbeddingInput.text('first'), EmbeddingInput.text('second')],
              dimensions: 2,
            ),
          )
          .runFuture();

      expect(requests, 1);
      expect(result.modelId, 'actual-model');
      expect(result.vectors, [
        [1, 2],
        [3, 4],
      ]);
    });

    test('should fail unsupported multimodal input before I/O', () async {
      var requests = 0;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        requests++;
        await request.response.close();
      });
      final client = ProviderHttpClient(
        baseUrl: Uri.parse('http://${server.address.address}:${server.port}/'),
      );
      addTearDown(client.close);
      final model = _LoopbackEmbeddingModel(client, 'model');

      final exit = await model
          .embed(
            EmbeddingRequest(
              items: [
                EmbeddingInput([
                  MediaInputPart(
                    kind: MediaKind.video,
                    mimeType: 'video/mp4',
                    source: UrlMediaSource(Uri.parse('https://example.com/video.mp4')),
                  ),
                ]),
              ],
            ),
          )
          .runFutureExit();

      expect(requests, 0);
      expect(exit, _expectedError<UnsupportedFeatureError>());
    });
  });
}

Matcher _expectedError<E extends AiError>() => isA<Failed<Object?, AiError>>().having(
  (failure) => failure.cause,
  'cause',
  isA<Expected<AiError>>().having((cause) => cause.error, 'error', isA<E>()),
);

final class _LoopbackEmbeddingModel implements EmbeddingModel {
  _LoopbackEmbeddingModel(this._client, this.modelId);

  final ProviderHttpClient _client;

  @override
  final String modelId;

  @override
  String get providerId => 'fixture';

  @override
  EmbeddingCapabilities get capabilities => EmbeddingCapabilities({
    EmbeddingCapability.text: CapabilitySupport.supported,
    EmbeddingCapability.video: CapabilitySupport.unsupported,
    EmbeddingCapability.batching: CapabilitySupport.supported,
    EmbeddingCapability.dimensions: CapabilitySupport.supported,
  });

  @override
  Effect<EmbeddingResult, AiError> embed(EmbeddingRequest request) {
    final unsupported = capabilities.validate(request);
    if (unsupported != null) return Effect.fail(unsupported);
    return _client
        .sendJson(
          ProviderHttpRequest(
            method: 'POST',
            path: 'embeddings',
            body: JsonObject({
              'model': modelId,
              'input': [
                for (final item in request.items)
                  [
                    for (final part in item.parts)
                      if (part is TextInputPart) part.text,
                  ],
              ],
              'dimensions': ?request.dimensions,
            }),
          ),
          providerId: providerId,
          api: 'embeddings',
          modelId: modelId,
        )
        .flatMap((response, _) => _normalize(response, request));
  }

  Effect<EmbeddingResult, AiError> _normalize(
    NativeResponse<JsonObject> response,
    EmbeddingRequest request,
  ) {
    try {
      final json = response.value.toDart();
      final data = json['data']! as List<Object?>;
      return Effect.succeed(
        EmbeddingResult.fromIndexed(
          embeddings: data.map((item) {
            final object = item! as Map<String, Object?>;
            return IndexedEmbedding(
              index: object['index']! as int,
              vector: (object['embedding']! as List<Object?>).cast<num>(),
            );
          }),
          inputCount: request.items.length,
          requestedDimensions: request.dimensions,
          modelId: json['model']! as String,
          nativePayload: response.payload,
          metadata: response.metadata,
        ),
      );
    } on FormatException catch (error) {
      return Effect.fail(ProtocolError(error.message));
    }
  }
}
