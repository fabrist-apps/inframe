import 'dart:convert';
import 'dart:io';

import 'package:artificer_baseten/artificer_baseten.dart';
import 'package:artificer_core/artificer_core.dart';
import 'package:artificer_core/json.dart';
import 'package:conflux/conflux.dart';
import 'package:test/test.dart';

void main() {
  test('dedicated native and common text batches share indexed decoding', () async {
    final bodies = <Map<String, Object?>>[];
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      expect(request.uri.path, '/environments/production/sync/v1/embeddings');
      bodies.add(jsonDecode(await utf8.decoder.bind(request).join())! as Map<String, Object?>);
      request.response
        ..headers.contentType = ContentType.json
        ..headers.set('x-request-id', 'embedding-${bodies.length}')
        ..write(jsonEncode(_response));
      await request.response.close();
    });
    final provider = BasetenProvider(apiKey: 'secret');
    addTearDown(provider.close);
    final deployment = provider.deployment(
      baseUrl: Uri.parse(
        'http://${server.address.address}:${server.port}/environments/production/sync/v1',
      ),
    );

    final native = await deployment.embeddings
        .create(
          BasetenEmbeddingRequest(
            model: 'served-model',
            input: ['first', 'second'],
            dimensions: 2,
            extraBody: JsonObject({'future_request': true}),
          ),
        )
        .runFuture();
    final common = await deployment
        .embeddingModel(
          'served-model',
          options: BasetenEmbeddingOptions(
            dimensions: const Setting.set(8),
            extraBody: JsonObject({'future_request': false}),
          ),
        )
        .embed(
          EmbeddingRequest(
            items: [EmbeddingInput.text('first'), EmbeddingInput.text('second')],
          ),
          options: BasetenEmbeddingOptions(dimensions: const Setting.set(2)),
        )
        .runFuture();
    await deployment
        .embeddingModel(
          'served-model',
          options: BasetenEmbeddingOptions(
            dimensions: const Setting.set(8),
          ),
        )
        .embed(
          EmbeddingRequest(
            items: [EmbeddingInput.text('first'), EmbeddingInput.text('second')],
          ),
          options: BasetenEmbeddingOptions(dimensions: const Setting.clear()),
        )
        .runFuture();

    expect(native.value.extensions.toDart()['future_response'], {'keep': true});
    expect(native.metadata.requestId, 'embedding-1');
    expect(common.modelId, 'actual-model');
    expect(common.vectors, [
      [1, 2],
      [3, 4],
    ]);
    expect(common.usage!.totalTokens, 4);
    expect(bodies, [
      {
        'future_request': true,
        'model': 'served-model',
        'input': ['first', 'second'],
        'dimensions': 2,
      },
      {
        'future_request': false,
        'model': 'served-model',
        'input': ['first', 'second'],
        'dimensions': 2,
      },
      {
        'model': 'served-model',
        'input': ['first', 'second'],
      },
    ]);
  });

  test('invalid common inputs and indexed vectors fail explicitly', () async {
    var requests = 0;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      requests++;
      await request.drain<void>();
      request.response
        ..headers.contentType = ContentType.json
        ..write(
          jsonEncode({
            ..._response,
            'data': [(_response['data']! as List<Object?>).first],
          }),
        );
      await request.response.close();
    });
    final provider = BasetenProvider(apiKey: 'secret');
    addTearDown(provider.close);
    final model = provider
        .deployment(
          baseUrl: Uri.parse('http://${server.address.address}:${server.port}/v1'),
        )
        .embeddingModel('served-model');
    final unsupported = EmbeddingRequest(
      items: [
        EmbeddingInput([
          MediaInputPart(
            kind: MediaKind.image,
            mimeType: 'image/png',
            source: BytesMediaSource([1]),
          ),
        ]),
      ],
    );

    expect(await model.embed(unsupported).runFutureExit(), isA<Failed<EmbeddingResult, AiError>>());
    expect(requests, 0);
    expect(
      await model
          .embed(
            EmbeddingRequest(
              items: [EmbeddingInput.text('one'), EmbeddingInput.text('two')],
            ),
          )
          .runFutureExit(),
      isA<Failed<EmbeddingResult, AiError>>(),
    );
    expect(requests, 1);
  });
}

const _response = <String, Object?>{
  'object': 'list',
  'model': 'actual-model',
  'data': [
    {
      'object': 'embedding',
      'index': 1,
      'embedding': [3.0, 4.0],
    },
    {
      'object': 'embedding',
      'index': 0,
      'embedding': [1.0, 2.0],
    },
  ],
  'usage': {'prompt_tokens': 4, 'total_tokens': 4},
  'future_response': {'keep': true},
};
