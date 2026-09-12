import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:artificer_anthropic/artificer_anthropic.dart';
import 'package:artificer_core/artificer_core.dart';
import 'package:conflux/conflux.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

void main() {
  group('AnthropicProvider', () {
    test('should keep operations lazy and allocate a request for every run', () async {
      var requests = 0;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        requests++;
        await request.drain<void>();
        _json(request, _message);
        await request.response.close();
      });
      final provider = _provider(server);
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

    test('should reject new work after close and preserve a borrowed client', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        if (request.uri.path == '/unrelated') {
          request.response.write('ok');
        } else {
          await request.drain<void>();
          _json(request, _message);
        }
        await request.response.close();
      });
      final borrowed = http.Client();
      addTearDown(borrowed.close);
      final root = Uri.parse('http://${server.address.address}:${server.port}/');
      final provider = AnthropicProvider(
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

    test('should fail premature and in-stream-error responses without success', () async {
      var requestCount = 0;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        requestCount++;
        await request.drain<void>();
        request.response.headers.contentType = ContentType('text', 'event-stream');
        if (requestCount == 1) {
          request.response.write(
            _sse('message_start', {'type': 'message_start', 'message': _streamStart}),
          );
        } else {
          request.response
            ..headers.set('request-id', 'stream-request')
            ..write(
              _sse('error', {
                'type': 'error',
                'error': {'type': 'overloaded_error', 'message': 'busy'},
              }),
            );
        }
        await request.response.close();
      });
      final provider = _provider(server);
      addTearDown(provider.close);
      final request = AnthropicMessageRequest(
        model: 'model',
        maxTokens: 32,
        messages: [AnthropicInputMessage.userText('hello')],
      );

      final premature = await provider.messages.stream(request).runCollect().runFutureExit();
      final serviceError = await provider.messages.stream(request).runCollect().runFutureExit();

      expect(premature, _failedWith<ProtocolError>());
      expect(serviceError, _failedWith<ProviderError>());
      final providerError =
          ((serviceError as Failed<List<AnthropicMessageEvent>, AiError>).cause
                      as Expected<AiError>)
                  .error
              as ProviderError;
      expect(providerError.requestId, 'stream-request');
    });
  });
}

Matcher _failedWith<E extends AiError>() => isA<Failed<Object?, AiError>>().having(
  (failure) => failure.cause,
  'cause',
  isA<Expected<AiError>>().having((expected) => expected.error, 'error', isA<E>()),
);

void _json(HttpRequest request, Map<String, Object?> value) {
  request.response
    ..headers.contentType = ContentType.json
    ..write(jsonEncode(value));
}

String _sse(String event, Map<String, Object?> data) =>
    'event: $event\ndata: ${jsonEncode(data)}\n\n';

AnthropicProvider _provider(HttpServer server) => AnthropicProvider(
  apiKey: 'secret',
  baseUrl: Uri.parse('http://${server.address.address}:${server.port}/v1/'),
);

const _streamStart = <String, Object?>{
  'id': 'msg_1',
  'type': 'message',
  'role': 'assistant',
  'content': <Object?>[],
  'model': 'model',
  'stop_reason': null,
  'stop_sequence': null,
  'usage': {'input_tokens': 1, 'output_tokens': 0},
};

const _message = <String, Object?>{
  'id': 'msg_1',
  'type': 'message',
  'role': 'assistant',
  'content': [
    {'type': 'text', 'text': 'Hello.', 'citations': null},
  ],
  'model': 'model',
  'stop_reason': 'end_turn',
  'stop_sequence': null,
  'usage': {'input_tokens': 2, 'output_tokens': 1},
};
