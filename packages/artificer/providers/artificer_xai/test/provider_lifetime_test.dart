import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:artificer_core/artificer_core.dart';
import 'package:artificer_xai/artificer_xai.dart';
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
    final provider = XaiProvider(
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
    final provider = XaiProvider(
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
    final provider = XaiProvider(
      apiKey: 'secret',
      baseUrl: Uri.parse('http://${server.address.address}:${server.port}/v1/'),
    );
    addTearDown(provider.close);
    final request = GenerationRequest(messages: [UserMessage.text('hello')]);

    final native = await provider.responses
        .stream(
          XaiResponseRequest(
            model: 'model',
            input: [XaiResponseInputMessage.userText('hello')],
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

  test('cancellation before headers and during body preserves interruption', () async {
    final beforeHeaders = Completer<void>();
    final bodyStarted = Completer<void>();
    var requests = 0;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      requests++;
      await request.drain<void>();
      if (requests == 1) {
        beforeHeaders.complete();
        return;
      }
      request.response.write('{"id":"resp_1","output":[');
      await request.response.flush();
      bodyStarted.complete();
    });
    final provider = XaiProvider(
      apiKey: 'secret',
      baseUrl: Uri.parse('http://${server.address.address}:${server.port}/v1/'),
    );
    final runtime = Runtime();
    addTearDown(runtime.close);
    addTearDown(provider.close);
    final operation = provider
        .languageModel('model')
        .generate(GenerationRequest(messages: [UserMessage.text('hello')]));

    final acquiring = runtime.fork(operation);
    await beforeHeaders.future;
    final beforeExit = await acquiring
        .interrupt('before headers')
        .timeout(const Duration(seconds: 2));
    final consuming = runtime.fork(operation);
    await bodyStarted.future;
    final bodyExit = await consuming.interrupt('during body').timeout(const Duration(seconds: 2));

    expect((beforeExit as Failed<Object?, AiError>).cause.containsInterruption, isTrue);
    expect((bodyExit as Failed<Object?, AiError>).cause.containsInterruption, isTrue);
    expect(requests, 2);
  });

  test('early stream termination releases the response and keeps the provider usable', () async {
    var requests = 0;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      requests++;
      final body = jsonDecode(await utf8.decoder.bind(request).join())! as Map<String, Object?>;
      if (body['stream'] == true) {
        final created = jsonEncode({
          'type': 'response.created',
          'response': {
            ..._response,
            'status': 'in_progress',
            'output': <Object?>[],
          },
        });
        request.response
          ..bufferOutput = false
          ..headers.contentType = ContentType('text', 'event-stream')
          ..write('data: $created\n\n');
        await request.response.flush();
        return;
      }
      request.response
        ..headers.contentType = ContentType.json
        ..write(jsonEncode(_response));
      await request.response.close();
    });
    final provider = XaiProvider(
      apiKey: 'secret',
      baseUrl: Uri.parse('http://${server.address.address}:${server.port}/v1/'),
    );
    addTearDown(provider.close);
    final model = provider.languageModel('model');

    final first = await model
        .stream(GenerationRequest(messages: [UserMessage.text('hello')]))
        .runFirst()
        .runFuture()
        .timeout(const Duration(seconds: 2));
    final generated = await model
        .generate(GenerationRequest(messages: [UserMessage.text('next')]))
        .runFuture()
        .timeout(const Duration(seconds: 2));

    expect(first, isA<Some<GenerationEvent>>());
    expect(generated.text, 'Hello.');
    expect(requests, 2);
  });

  test('redirects are returned as one provider failure without retrying', () async {
    var requests = 0;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      requests++;
      await request.drain<void>();
      request.response
        ..statusCode = HttpStatus.temporaryRedirect
        ..headers.set(HttpHeaders.locationHeader, '/redirected')
        ..headers.contentType = ContentType.json
        ..write(
          jsonEncode({
            'error': {'code': 'redirect', 'message': 'redirect'},
          }),
        );
      await request.response.close();
    });
    final provider = XaiProvider(
      apiKey: 'secret',
      baseUrl: Uri.parse('http://${server.address.address}:${server.port}/v1/'),
    );
    addTearDown(provider.close);

    final exit = await provider
        .languageModel('model')
        .generate(GenerationRequest(messages: [UserMessage.text('hello')]))
        .runFutureExit();

    expect(exit, _failedWith<ProviderError>());
    expect(requests, 1);
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
