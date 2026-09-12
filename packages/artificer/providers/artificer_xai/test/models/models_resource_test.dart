import 'dart:convert';
import 'dart:io';

import 'package:artificer_core/artificer_core.dart';
import 'package:artificer_xai/artificer_xai.dart';
import 'package:conflux/conflux.dart';
import 'package:test/test.dart';

void main() {
  test('compatible and detailed model discovery are explicit', () async {
    final requests = <String>[];
    final compatible = {
      'id': 'grok-future',
      'aliases': ['grok-latest'],
      'created': 123,
      'object': 'model',
      'owned_by': 'xai',
      'context_length': 131072,
    };
    final detailed = {
      'id': 'grok-future',
      'fingerprint': 'fp_123',
      'created': 123,
      'object': 'model',
      'owned_by': 'xai',
      'version': '2026-09-01',
      'aliases': ['grok-latest'],
      'input_modalities': ['text', 'image'],
      'output_modalities': ['text'],
      'prompt_text_token_price': 42,
    };
    final replies = <Map<String, Object?>>[
      {
        'object': 'list',
        'data': [compatible],
        'future_page': true,
      },
      {...compatible, 'future': 'keep'},
      {
        'models': [detailed],
        'future_page': true,
      },
      {...detailed, 'future': 'keep'},
      {
        'models': [detailed],
        'future_page': true,
      },
      {...detailed, 'future': 'keep'},
    ];
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      requests.add('${request.method} ${request.uri}');
      request.response
        ..headers.contentType = ContentType.json
        ..write(jsonEncode(replies[requests.length - 1]));
      await request.response.close();
    });
    final provider = XaiProvider(
      apiKey: 'secret',
      baseUrl: Uri.parse('http://${server.address.address}:${server.port}/v1/'),
    );
    addTearDown(provider.close);

    final models = await provider.models.list().runFuture();
    final model = await provider.models.retrieve('grok/future').runFuture();
    final languageModels = await provider.models.listLanguage().runFuture();
    final languageModel = await provider.models.retrieveLanguage('grok/future').runFuture();
    final embeddingModels = await provider.models.listEmbedding().runFuture();
    final embeddingModel = await provider.models.retrieveEmbedding('grok/future').runFuture();

    expect(models.value.data.single.aliases, ['grok-latest']);
    expect(models.value.extensions.toDart()['future_page'], isTrue);
    expect(model.value.extensions.toDart()['context_length'], 131072);
    expect(languageModels.value.models.single.inputModalities, ['text', 'image']);
    expect(languageModels.value.extensions.toDart()['future_page'], isTrue);
    expect(languageModel.value.extensions.toDart()['prompt_text_token_price'], 42);
    expect(embeddingModels.value.models.single.outputModalities, ['text']);
    expect(embeddingModel.value.extensions.toDart()['future'], 'keep');
    expect(requests, [
      'GET /v1/models',
      'GET /v1/models/grok%2Ffuture',
      'GET /v1/language-models',
      'GET /v1/language-models/grok%2Ffuture',
      'GET /v1/embedding-models',
      'GET /v1/embedding-models/grok%2Ffuture',
    ]);
  });

  test('malformed model page members fail through the typed channel', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      request.response
        ..headers.contentType = ContentType.json
        ..write(
          jsonEncode({
            'object': 'list',
            'data': [null],
          }),
        );
      await request.response.close();
    });
    final provider = XaiProvider(
      apiKey: 'secret',
      baseUrl: Uri.parse('http://${server.address.address}:${server.port}/v1/'),
    );
    addTearDown(provider.close);

    final exit = await provider.models.list().runFutureExit();

    expect(exit, _failedWith<ProtocolError>());
  });
}

Matcher _failedWith<E extends AiError>() => isA<Failed<Object?, AiError>>().having(
  (failure) => (failure.cause as Expected<AiError>).error,
  'error',
  isA<E>(),
);
