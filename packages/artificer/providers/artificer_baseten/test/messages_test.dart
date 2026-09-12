import 'dart:convert';
import 'dart:io';

import 'package:artificer_baseten/artificer_baseten.dart';
import 'package:artificer_core/artificer_core.dart';
import 'package:artificer_core/json.dart';
import 'package:conflux/conflux.dart';
import 'package:test/test.dart';

void main() {
  test('beta Messages uses Baseten authentication and retains native data', () async {
    Map<String, Object?>? body;
    String? authorization;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      expect(request.uri.path, '/v1/messages');
      authorization = request.headers.value(HttpHeaders.authorizationHeader);
      body = jsonDecode(await utf8.decoder.bind(request).join())! as Map<String, Object?>;
      request.response
        ..headers.contentType = ContentType.json
        ..headers.set('x-request-id', 'message-1')
        ..write(jsonEncode(_message));
      await request.response.close();
    });
    final provider = BasetenProvider(
      apiKey: 'secret',
      catalogBaseUrl: Uri.parse('http://${server.address.address}:${server.port}/v1'),
    );
    addTearDown(provider.close);
    final response = await provider.messages
        .create(
          BasetenMessageRequest(
            model: 'catalog/model',
            maxTokens: 128,
            messages: [BasetenInputMessage.userText('Hello')],
            tools: [
              JsonObject({
                'name': 'lookup',
                'input_schema': {'type': 'object'},
              }),
            ],
          ),
        )
        .runFuture();

    expect(authorization, 'Bearer secret');
    expect(body, containsPair('stream', false));
    expect(response.value.content.single.toDart()['type'], 'text');
    expect(response.value.extensions.toDart()['future'], {'keep': true});
    expect(response.metadata.requestId, 'message-1');
  });

  test('beta Messages streams typed events and requires message_stop', () async {
    var requests = 0;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      requests++;
      await request.drain<void>();
      request.response.headers.contentType = ContentType('text', 'event-stream');
      request.response.write(
        'event: message_start\ndata: ${jsonEncode({'type': 'message_start', 'message': _message})}\n\n',
      );
      if (requests == 1) {
        request.response.write(
          'event: future_event\ndata: ${jsonEncode({'type': 'future_event', 'value': 1})}\n\n',
        );
        request.response.write(
          'event: message_stop\ndata: ${jsonEncode({'type': 'message_stop'})}\n\n',
        );
      }
      await request.response.close();
    });
    final provider = BasetenProvider(
      apiKey: 'secret',
      catalogBaseUrl: Uri.parse('http://${server.address.address}:${server.port}/v1'),
    );
    addTearDown(provider.close);
    final request = BasetenMessageRequest(
      model: 'catalog/model',
      maxTokens: 128,
      messages: [BasetenInputMessage.userText('Hello')],
    );

    final events = await provider.messages.stream(request).runCollect().runFuture();
    final premature = await provider.messages.stream(request).runCollect().runFutureExit();

    expect(events, hasLength(3));
    expect(events[0], isA<BasetenKnownMessageEvent>());
    expect(events[1], isA<BasetenUnknownMessageEvent>());
    expect(events[2], isA<BasetenMessageStopEvent>());
    expect(premature, isA<Failed<Object?, AiError>>());
  });

  test('beta Messages keeps malformed responses and stream errors typed', () async {
    var requests = 0;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      requests++;
      await request.drain<void>();
      if (requests == 1) {
        request.response
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({'type': 'message', 'content': <Object?>[]}));
      } else if (requests == 2) {
        request.response
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({..._message, 'stop_reason': 42}));
      } else {
        request.response.headers.contentType = ContentType('text', 'event-stream');
        request.response.write(
          'event: error\ndata: ${jsonEncode({
            'type': 'error',
            'error': {'type': 'overloaded_error', 'message': 'Try later.'},
          })}\n\n',
        );
      }
      await request.response.close();
    });
    final provider = BasetenProvider(
      apiKey: 'secret',
      catalogBaseUrl: Uri.parse('http://${server.address.address}:${server.port}/v1'),
    );
    addTearDown(provider.close);
    final request = BasetenMessageRequest(
      model: 'catalog/model',
      maxTokens: 128,
      messages: [BasetenInputMessage.userText('Hello')],
    );

    expect(await provider.messages.create(request).runFutureExit(), _failedWith<ProtocolError>());
    final malformedStop = await provider.messages.create(request).runFutureExit();
    expect(
      malformedStop,
      isA<Failed<Object?, AiError>>().having(
        (failure) => (failure.cause as Expected<AiError>).error,
        'error',
        isA<ProtocolError>().having(
          (error) => error.partialOutput,
          'partialOutput',
          isA<JsonObject>(),
        ),
      ),
    );
    expect(
      await provider.messages.stream(request).runCollect().runFutureExit(),
      _failedWith<ProviderError>(),
    );
  });
}

Matcher _failedWith<E extends AiError>() => isA<Failed<Object?, AiError>>().having(
  (failure) => (failure.cause as Expected<AiError>).error,
  'error',
  isA<E>(),
);

const _message = <String, Object?>{
  'id': 'msg_1',
  'type': 'message',
  'role': 'assistant',
  'model': 'catalog/model',
  'content': [
    {'type': 'text', 'text': 'Hello'},
  ],
  'stop_reason': 'end_turn',
  'stop_sequence': null,
  'usage': {'input_tokens': 2, 'output_tokens': 1},
  'future': {'keep': true},
};
