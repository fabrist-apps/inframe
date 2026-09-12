import 'dart:convert';
import 'dart:io';

import 'package:artificer_core/artificer_core.dart';
import 'package:artificer_openai/artificer_openai.dart';
import 'package:conflux/conflux.dart';
import 'package:test/test.dart';

void main() {
  test('native token inputs and common text batches share one indexed decoder', () async {
    final bodies = <Map<String, Object?>>[];
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      expect(request.method, 'POST');
      expect(request.uri.path, '/v1/embeddings');
      bodies.add(jsonDecode(await utf8.decoder.bind(request).join())! as Map<String, Object?>);
      request.response
        ..headers.contentType = ContentType.json
        ..headers.set('x-request-id', 'embedding-${bodies.length}')
        ..write(
          jsonEncode({
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
            'future': {'keep': true},
          }),
        );
      await request.response.close();
    });
    final provider = _provider(server);
    addTearDown(provider.close);

    final native = await provider.embeddings
        .create(
          OpenAIEmbeddingRequest(
            model: 'future-model',
            input: [
              OpenAITextEmbeddingInput('hello'),
              OpenAITokenEmbeddingInput([1, 2, 3]),
            ],
            dimensions: 2,
          ),
        )
        .runFuture();
    final common = await provider
        .embeddingModel(
          'future-model',
          options: OpenAIEmbeddingOptions(
            encodingFormat: const Setting.set(OpenAIEmbeddingEncoding.float),
            dimensions: const Setting.set(8),
          ),
        )
        .embed(
          EmbeddingRequest(
            items: [EmbeddingInput.text('first'), EmbeddingInput.text('second')],
          ),
          options: OpenAIEmbeddingOptions(
            dimensions: const Setting.set(2),
            encodingFormat: const Setting.clear(),
          ),
        )
        .runFuture();

    expect(native.value.data.first.index, 1);
    expect(native.value.extensions.toDart()['future'], {'keep': true});
    expect(native.metadata.requestId, 'embedding-1');
    expect(common.modelId, 'actual-model');
    expect(common.vectors, [
      [1, 2],
      [3, 4],
    ]);
    expect(common.usage!.totalTokens, 4);
    expect(bodies, [
      {
        'model': 'future-model',
        'input': [
          'hello',
          [1, 2, 3],
        ],
        'dimensions': 2,
      },
      {
        'model': 'future-model',
        'input': ['first', 'second'],
        'dimensions': 2,
      },
    ]);
  });

  test('unsupported common shapes and invalid vectors fail explicitly', () async {
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
            'object': 'list',
            'model': 'actual-model',
            'data': [
              {'object': 'embedding', 'index': 0, 'embedding': <Object?>[]},
            ],
          }),
        );
      await request.response.close();
    });
    final provider = _provider(server);
    addTearDown(provider.close);
    final model = provider.embeddingModel('future-model');
    final unsupported = await model
        .embed(
          EmbeddingRequest(
            items: [
              EmbeddingInput([TextInputPart('one'), TextInputPart('two')]),
            ],
          ),
        )
        .runFutureExit();

    expect(unsupported, _failedWith<UnsupportedFeatureError>());
    expect(requests, 0);

    final invalid = await model
        .embed(EmbeddingRequest(items: [EmbeddingInput.text('one')]))
        .runFutureExit();
    expect(invalid, _failedWith<ProtocolError>());
    expect(requests, 1);
  });
}

OpenAIProvider _provider(HttpServer server) => OpenAIProvider(
  apiKey: 'secret',
  baseUrl: Uri.parse('http://${server.address.address}:${server.port}/v1/'),
);

Matcher _failedWith<E extends AiError>() => isA<Failed<Object?, AiError>>().having(
  (failure) => (failure.cause as Expected<AiError>).error,
  'error',
  isA<E>(),
);
