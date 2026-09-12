import 'dart:convert';
import 'dart:io';

import 'package:artificer_core/artificer_core.dart';
import 'package:artificer_openai/artificer_openai.dart';
import 'package:conflux/conflux.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

void main() {
  test('operations stay lazy and repeated or concurrent runs use fresh requests', () async {
    var requests = 0;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      requests++;
      await request.drain<void>();
      request.response
        ..headers.contentType = ContentType.json
        ..write(jsonEncode(_response));
      await request.response.close();
    });
    final provider = OpenAIProvider(
      apiKey: 'secret',
      baseUrl: Uri.parse('http://${server.address.address}:${server.port}/v1/'),
    );
    addTearDown(provider.close);
    final operation = provider
        .languageModel('unlisted-future-model')
        .generate(GenerationRequest(messages: [UserMessage.text('hello')]));

    expect(requests, 0);
    final results = await Future.wait([
      operation.runFuture(),
      operation.runFuture(),
      operation.runFuture(),
    ]);

    expect(requests, 3);
    expect(results.map((result) => result.text), everyElement('Hello.'));
  });

  test('provider close rejects new work and leaves a borrowed client usable', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      if (request.uri.path == '/unrelated') {
        request.response.write('ok');
      } else {
        await request.drain<void>();
        request.response
          ..headers.contentType = ContentType.json
          ..write(jsonEncode(_response));
      }
      await request.response.close();
    });
    final borrowed = http.Client();
    addTearDown(borrowed.close);
    final root = Uri.parse('http://${server.address.address}:${server.port}/');
    final provider = OpenAIProvider(
      apiKey: 'secret',
      baseUrl: root.resolve('v1/'),
      httpClient: borrowed,
    );

    await Future.wait([provider.close(), provider.close()]);
    final closed = await provider
        .languageModel('model')
        .generate(GenerationRequest(messages: [UserMessage.text('hello')]))
        .runFutureExit();
    final unrelated = await borrowed.get(root.resolve('unrelated'));

    expect(closed, _failedWith<ClientClosedError>());
    expect(unrelated.body, 'ok');
  });

  test('premature native and common streams fail without a final result', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      await request.drain<void>();
      request.response
        ..headers.contentType = ContentType('text', 'event-stream')
        ..write(
          'data: ${jsonEncode({'type': 'response.output_text.delta', 'sequence_number': 0, 'item_id': 'msg', 'output_index': 0, 'content_index': 0, 'delta': 'partial', 'logprobs': <Object?>[]})}\n\n',
        );
      await request.response.close();
    });
    final provider = OpenAIProvider(
      apiKey: 'secret',
      baseUrl: Uri.parse('http://${server.address.address}:${server.port}/v1/'),
    );
    addTearDown(provider.close);
    final request = GenerationRequest(messages: [UserMessage.text('hello')]);

    final native = await provider.responses
        .stream(
          OpenAIResponseRequest(
            model: 'model',
            input: [OpenAIResponseInputMessage.userText('hello')],
          ),
        )
        .runCollect()
        .runFutureExit();
    final common = await provider
        .languageModel('model')
        .stream(request)
        .runCollect()
        .runFutureExit();

    expect(native, _failedWith<ProtocolError>());
    expect(common, _failedWith<ProtocolError>());
  });
}

Matcher _failedWith<E extends AiError>() => isA<Failed<Object?, AiError>>().having(
  (failure) => failure.cause,
  'cause',
  isA<Expected<AiError>>().having((expected) => expected.error, 'error', isA<E>()),
);

const _response = <String, Object?>{
  'id': 'resp_1',
  'object': 'response',
  'created_at': 1,
  'status': 'completed',
  'model': 'future-model',
  'output': [
    {
      'id': 'msg_1',
      'type': 'message',
      'status': 'completed',
      'role': 'assistant',
      'content': [
        {'type': 'output_text', 'text': 'Hello.', 'annotations': <Object?>[]},
      ],
    },
  ],
  'usage': {'input_tokens': 2, 'output_tokens': 1, 'total_tokens': 3},
};
