import 'dart:convert';
import 'dart:io';

import 'package:artificer_anthropic/artificer_anthropic.dart';
import 'package:artificer_core/artificer_core.dart';
import 'package:conflux/conflux.dart';
import 'package:test/test.dart';

void main() {
  group('AnthropicMessagesResource', () {
    test('should share typed decoding between native and common generation', () async {
      final bodies = <Map<String, Object?>>[];
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        expect(request.uri.path, '/v1/messages');
        expect(request.headers.value('x-api-key'), 'secret');
        expect(request.headers.value('anthropic-version'), '2023-06-01');
        expect(request.headers.value('anthropic-beta'), 'structured-outputs-2025-11-13');
        expect(request.headers.value('anthropic-user-profile-id'), 'profile-1');
        bodies.add(jsonDecode(await utf8.decoder.bind(request).join())! as Map<String, Object?>);
        request.response
          ..headers.contentType = ContentType.json
          ..headers.set('request-id', 'request-1')
          ..write(jsonEncode(_message));
        await request.response.close();
      });
      final provider = AnthropicProvider(
        apiKey: 'secret',
        betaFeatures: const [AnthropicBeta.structuredOutputs20251113],
        userProfileId: 'profile-1',
        baseUrl: Uri.parse('http://${server.address.address}:${server.port}/v1'),
      );
      addTearDown(provider.close);

      final native = await provider.messages
          .create(
            AnthropicMessageRequest(
              model: 'future-model',
              maxTokens: 4096,
              messages: [AnthropicInputMessage.userText('hello')],
              system: [AnthropicTextBlock('Be direct.')],
            ),
          )
          .runFuture();
      final common = await provider
          .languageModel('future-model')
          .generate(
            GenerationRequest(
              instructions: 'Be direct.',
              messages: [UserMessage.text('hello')],
            ),
          )
          .runFuture();
      final mappedAgain = provider.messages.normalize(native);

      expect(native.value.id, 'msg_1');
      expect(native.value.extensions.toDart()['future_field'], {'keep': true});
      expect(native.metadata.requestId, 'request-1');
      expect(common.text, 'Hello.');
      expect(common.toJson().toDart(), mappedAgain.toJson().toDart());
      expect(bodies, hasLength(2));
      expect(bodies.last, {
        'model': 'future-model',
        'max_tokens': 4096,
        'messages': [
          {
            'role': 'user',
            'content': [
              {'type': 'text', 'text': 'hello'},
            ],
          },
        ],
        'system': [
          {'type': 'text', 'text': 'Be direct.'},
        ],
        'stream': false,
      });
    });

    test('should stream text only after message_stop', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        await request.drain<void>();
        request.response
          ..headers.contentType = ContentType('text', 'event-stream')
          ..headers.set('request-id', 'request-stream')
          ..write(_sse('message_start', {'type': 'message_start', 'message': _streamStart}))
          ..write(
            _sse('content_block_start', {
              'type': 'content_block_start',
              'index': 0,
              'content_block': {'type': 'text', 'text': '', 'citations': null},
            }),
          )
          ..write(
            _sse('content_block_delta', {
              'type': 'content_block_delta',
              'index': 0,
              'delta': {'type': 'text_delta', 'text': 'Hello.'},
            }),
          )
          ..write(_sse('content_block_stop', {'type': 'content_block_stop', 'index': 0}))
          ..write(
            _sse('message_delta', {
              'type': 'message_delta',
              'delta': {'stop_reason': 'end_turn', 'stop_sequence': null},
              'usage': {'output_tokens': 1},
            }),
          )
          ..write(_sse('ping', {'type': 'ping'}))
          ..write(_sse('message_stop', {'type': 'message_stop'}));
        await request.response.close();
      });
      final provider = AnthropicProvider(
        apiKey: 'secret',
        baseUrl: Uri.parse('http://${server.address.address}:${server.port}/v1/'),
      );
      addTearDown(provider.close);

      final native = await provider.messages
          .stream(
            AnthropicMessageRequest(
              model: 'future-model',
              maxTokens: 32,
              messages: [AnthropicInputMessage.userText('hello')],
            ),
          )
          .runCollect()
          .runFuture();
      final common = await provider
          .languageModel('future-model')
          .stream(GenerationRequest(messages: [UserMessage.text('hello')]))
          .runCollect()
          .runFuture();

      expect(native.map((event) => event.type), [
        'message_start',
        'content_block_start',
        'content_block_delta',
        'content_block_stop',
        'message_delta',
        'ping',
        'message_stop',
      ]);
      expect(native.last, isA<AnthropicMessageStopEvent>());
      expect(common.whereType<TextPartDelta>().single.text, 'Hello.');
      expect(common.whereType<GenerationFinished>().single.result.text, 'Hello.');
    });
  });
}

String _sse(String event, Map<String, Object?> data) =>
    'event: $event\ndata: ${jsonEncode(data)}\n\n';

const _streamStart = <String, Object?>{
  'id': 'msg_1',
  'type': 'message',
  'role': 'assistant',
  'content': <Object?>[],
  'model': 'future-model',
  'stop_reason': null,
  'stop_sequence': null,
  'usage': {'input_tokens': 2, 'output_tokens': 0},
};

const _message = <String, Object?>{
  'id': 'msg_1',
  'type': 'message',
  'role': 'assistant',
  'content': [
    {'type': 'text', 'text': 'Hello.', 'citations': null},
  ],
  'model': 'future-model',
  'stop_reason': 'end_turn',
  'stop_sequence': null,
  'usage': {'input_tokens': 2, 'output_tokens': 1},
  'future_field': {'keep': true},
};
