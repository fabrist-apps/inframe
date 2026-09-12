import 'dart:convert';
import 'dart:io';

import 'package:artificer_baseten/artificer_baseten.dart';
import 'package:artificer_core/artificer_core.dart';
import 'package:artificer_core/json.dart';
import 'package:conflux/conflux.dart';
import 'package:test/test.dart';

void main() {
  test('native chat validates message roots and the top-k disable sentinel', () {
    for (final content in [JsonNumber(1), const JsonBoolean(value: true), JsonObject({})]) {
      expect(
        () => BasetenChatMessage(role: BasetenChatRole.user, content: content),
        throwsArgumentError,
      );
    }

    final request = BasetenChatRequest(
      model: 'catalog/model',
      messages: [BasetenChatMessage.userText('Hello')],
      topK: -1,
    );

    expect(request.toJson(stream: false).toDart()['top_k'], -1);
    for (final topK in [0, -2]) {
      expect(
        () => BasetenChatRequest(
          model: 'catalog/model',
          messages: [BasetenChatMessage.userText('Hello')],
          topK: topK,
        ),
        throwsArgumentError,
      );
    }
  });

  test('catalog and deployment keep endpoint and served model separate', () async {
    final requests = <({String path, String authorization, Map<String, Object?> body})>[];
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      requests.add((
        path: request.uri.path,
        authorization: request.headers.value(HttpHeaders.authorizationHeader)!,
        body: jsonDecode(await utf8.decoder.bind(request).join())! as Map<String, Object?>,
      ));
      request.response
        ..headers.contentType = ContentType.json
        ..headers.set('x-request-id', 'request-${requests.length}')
        ..write(jsonEncode(_completion(requests.last.body['model']! as String)));
      await request.response.close();
    });
    final origin = 'http://${server.address.address}:${server.port}';
    final provider = BasetenProvider(
      apiKey: 'secret',
      catalogBaseUrl: Uri.parse('$origin/catalog/v1'),
    );
    addTearDown(provider.close);

    final catalog = await provider
        .languageModel('catalog/model')
        .generate(GenerationRequest(messages: [UserMessage.text('Hello')]))
        .runFuture();
    final dedicated = await provider
        .deployment(baseUrl: Uri.parse('$origin/environments/production/sync/v1'))
        .languageModel('served-model')
        .generate(GenerationRequest(messages: [UserMessage.text('Hello')]))
        .runFuture();

    expect(catalog.text, 'Hello from catalog/model');
    expect(dedicated.text, 'Hello from served-model');
    expect(requests.map((request) => request.path), [
      '/catalog/v1/chat/completions',
      '/environments/production/sync/v1/chat/completions',
    ]);
    expect(requests.map((request) => request.authorization), [
      'Bearer secret',
      'Api-Key secret',
    ]);
    expect(requests.map((request) => request.body['model']), [
      'catalog/model',
      'served-model',
    ]);
  });

  test('common and native streams require terminal compatible semantics', () async {
    var requestCount = 0;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      requestCount++;
      await request.drain<void>();
      request.response.headers.contentType = ContentType('text', 'event-stream');
      request.response.write('data: ${jsonEncode(_chunk)}\n\n');
      if (requestCount != 3) request.response.write('data: [DONE]\n\n');
      await request.response.close();
    });
    final provider = BasetenProvider(
      apiKey: 'secret',
      catalogBaseUrl: Uri.parse('http://${server.address.address}:${server.port}/v1'),
    );
    addTearDown(provider.close);
    final model = provider.languageModel('catalog/model');

    final first = await model
        .stream(GenerationRequest(messages: [UserMessage.text('Hello')]))
        .runCollect()
        .runFuture();
    final second = await provider.chatCompletions
        .stream(
          BasetenChatRequest(model: 'native/model', messages: [BasetenChatMessage.userText('Hi')]),
        )
        .runCollect()
        .runFuture();
    final premature = await model
        .stream(GenerationRequest(messages: [UserMessage.text('Hello')]))
        .runCollect()
        .runFutureExit();

    expect(first.last, isA<GenerationFinished>());
    expect(second.last, isA<BasetenChatDone>());
    expect(premature, isA<Failed<Object?, AiError>>());
    expect(requestCount, 3);
  });

  test('native responses retain extensions and explicit choice selection', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      await request.drain<void>();
      request.response
        ..headers.contentType = ContentType.json
        ..write(
          jsonEncode({
            ..._completion('native/model'),
            'future': {'keep': true},
            'choices': [
              ...(_completion('native/model')['choices']! as List<Object?>),
              {
                'index': 1,
                'message': {'role': 'assistant', 'content': 'second'},
                'finish_reason': 'stop',
              },
            ],
          }),
        );
      await request.response.close();
    });
    final provider = BasetenProvider(
      apiKey: 'secret',
      catalogBaseUrl: Uri.parse('http://${server.address.address}:${server.port}/v1'),
    );
    addTearDown(provider.close);
    final native = await provider.chatCompletions
        .create(
          BasetenChatRequest(model: 'native/model', messages: [BasetenChatMessage.userText('Hi')]),
        )
        .runFuture();

    expect(native.value.extensions.toDart()['future'], {'keep': true});
    expect(provider.chatCompletions.normalize(native), isA<Failure<GenerationResult, AiError>>());
    final selected = provider.chatCompletions.normalize(native, choiceIndex: 1);
    expect((selected as Success<GenerationResult, AiError>).value.text, 'second');
  });
}

Map<String, Object?> _completion(String model) => {
  'id': 'chat_1',
  'object': 'chat.completion',
  'model': model,
  'choices': [
    {
      'index': 0,
      'message': {'role': 'assistant', 'content': 'Hello from $model'},
      'finish_reason': 'stop',
    },
  ],
  'usage': {'prompt_tokens': 1, 'completion_tokens': 2, 'total_tokens': 3},
};

const _chunk = <String, Object?>{
  'id': 'chat_1',
  'object': 'chat.completion.chunk',
  'model': 'catalog/model',
  'choices': [
    {
      'index': 0,
      'delta': {'role': 'assistant', 'content': 'Hello'},
      'finish_reason': 'stop',
    },
  ],
};
