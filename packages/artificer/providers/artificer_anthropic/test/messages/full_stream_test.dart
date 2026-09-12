import 'dart:convert';
import 'dart:io';

import 'package:artificer_anthropic/artificer_anthropic.dart';
import 'package:artificer_core/artificer_core.dart';
import 'package:conflux/conflux.dart';
import 'package:test/test.dart';

void main() {
  group('Anthropic full Messages stream', () {
    test('should assemble interleaved blocks, late metadata, and replay', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        final body = jsonDecode(await utf8.decoder.bind(request).join())! as Map<String, Object?>;
        if (body['stream'] == true) {
          request.response
            ..headers.contentType = ContentType('text', 'event-stream')
            ..headers.set('request-id', 'stream-request')
            ..write(_completeStream);
        } else {
          request.response
            ..headers.contentType = ContentType.json
            ..headers.set('request-id', 'json-request')
            ..write(jsonEncode(_completeMessage));
        }
        await request.response.close();
      });
      final provider = AnthropicProvider(
        apiKey: 'secret',
        baseUrl: Uri.parse('http://${server.address.address}:${server.port}/v1'),
      );
      addTearDown(provider.close);
      final nativeRequest = AnthropicMessageRequest(
        model: 'future-model',
        maxTokens: 4096,
        messages: [AnthropicInputMessage.userText('research')],
      );
      final commonRequest = GenerationRequest(messages: [UserMessage.text('research')]);

      final nativeEvents = await provider.messages.stream(nativeRequest).runCollect().runFuture();
      final streamedEvents = await provider
          .languageModel('future-model')
          .stream(commonRequest)
          .runCollect()
          .runFuture();
      final nonstream = await provider
          .languageModel('future-model')
          .generate(commonRequest)
          .runFuture();
      final streamed = streamedEvents.whereType<GenerationFinished>().single.result;

      expect(nativeEvents.whereType<AnthropicUnknownMessageEvent>().single.type, 'future_event');
      expect(streamed.message.parts.map((part) => part.runtimeType), [
        ReasoningSummaryPart,
        TextOutputPart,
        ApplicationToolCallPart,
        ProviderToolRecordPart,
        OpaqueOutputPart,
        ProviderToolRecordPart,
        OpaqueOutputPart,
      ]);
      expect(
        streamed.message.parts.map((part) => part.toDart()),
        nonstream.message.parts.map((part) => part.toDart()),
      );
      expect(streamed.finishReason, FinishReason.paused);
      expect(streamed.nativePayload.json.toDart(), _completeMessage);
      expect(streamed.metadata.requestId, 'stream-request');
      expect(streamedEvents.whereType<PartStarted>().map((event) => event.index), [
        0,
        1,
        2,
        3,
        4,
        5,
        6,
      ]);
      expect(streamedEvents.whereType<ReasoningPartDelta>().single.text, 'Check sources.');
      expect(streamedEvents.whereType<TextPartDelta>().single.text, 'Found it.');
      expect(
        streamedEvents.whereType<ToolArgumentsPartDelta>().map((event) => event.text).join(),
        '{"action":"screenshot"}',
      );
      expect(streamedEvents.whereType<UsageUpdated>().map((event) => event.usage.outputTokens), [
        0,
        14,
      ]);
      expect(
        streamedEvents.whereType<ProviderEvent>().map((event) => event.name),
        containsAll(['signature_delta', 'citations_delta', 'ping', 'future_event']),
      );
      final replay = streamed.message.replay!;
      expect(
        replay.items.where((item) => item.phase == null).map((item) => item.data.toDart()),
        _completeMessage['content'],
      );
      expect(replay.items.where((item) => item.phase == 'unknown-event').single.data.toDart(), {
        'type': 'future_event',
        'detail': {'keep': true},
      });
    });

    test('should retain malformed tool argument fragments without inventing JSON', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        await request.drain<void>();
        request.response
          ..headers.contentType = ContentType('text', 'event-stream')
          ..write(_malformedStream);
        await request.response.close();
      });
      final provider = AnthropicProvider(
        apiKey: 'secret',
        baseUrl: Uri.parse('http://${server.address.address}:${server.port}/v1'),
      );
      addTearDown(provider.close);

      final events = await provider
          .languageModel('future-model')
          .stream(GenerationRequest(messages: [UserMessage.text('weather')]))
          .runCollect()
          .runFuture();
      final call = events
          .whereType<GenerationFinished>()
          .single
          .result
          .message
          .parts
          .whereType<ApplicationToolCallPart>()
          .single;

      expect(call.arguments, isA<MalformedToolArguments>());
      expect((call.arguments as MalformedToolArguments).originalText, '{"city":');
      expect(call.arguments.toDart()['issue'], contains('Unexpected end'));
    });

    test('should attach partial output and request metadata to in-stream errors', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        await request.drain<void>();
        request.response
          ..headers.contentType = ContentType('text', 'event-stream')
          ..headers.set('request-id', 'failed-stream')
          ..write(_errorStream);
        await request.response.close();
      });
      final provider = AnthropicProvider(
        apiKey: 'secret',
        baseUrl: Uri.parse('http://${server.address.address}:${server.port}/v1'),
      );
      addTearDown(provider.close);

      final exit = await provider
          .languageModel('future-model')
          .stream(GenerationRequest(messages: [UserMessage.text('hello')]))
          .runCollect()
          .runFutureExit();

      final error =
          ((exit as Failed<List<GenerationEvent>, AiError>).cause as Expected<AiError>).error
              as ProviderError;
      expect(error.requestId, 'failed-stream');
      expect((error.partialOutput! as AssistantMessage).text, 'Partial');
      expect(error.details!.toDart(), {'type': 'overloaded_error', 'message': 'busy'});
    });
  });
}

String _sse(String event, Map<String, Object?> data) =>
    'event: $event\ndata: ${jsonEncode(data)}\n\n';

final String _completeStream = [
  _sse('message_start', {'type': 'message_start', 'message': _streamStart}),
  _start(0, {'type': 'thinking', 'thinking': '', 'signature': ''}),
  _start(1, {'type': 'text', 'text': '', 'citations': null}),
  _delta(0, {'type': 'thinking_delta', 'thinking': 'Check sources.'}),
  _delta(1, {'type': 'text_delta', 'text': 'Found it.'}),
  _start(2, {'type': 'tool_use', 'id': 'computer_1', 'name': 'computer', 'input': {}}),
  _delta(2, {'type': 'input_json_delta', 'partial_json': '{"action":'}),
  _start(3, {
    'type': 'server_tool_use',
    'id': 'search_1',
    'name': 'web_search',
    'input': {},
    'caller': {'type': 'direct'},
  }),
  _delta(3, {'type': 'input_json_delta', 'partial_json': '{"query":"docs"}'}),
  _delta(2, {'type': 'input_json_delta', 'partial_json': '"screenshot"}'}),
  _delta(0, {'type': 'signature_delta', 'signature': 'signed-thinking'}),
  _delta(1, {
    'type': 'citations_delta',
    'citation': {
      'type': 'web_search_result_location',
      'url': 'https://example.com/source',
      'title': 'Source',
    },
  }),
  _start(4, {'type': 'redacted_thinking', 'data': 'encrypted'}),
  _start(5, {
    'type': 'web_search_tool_result',
    'tool_use_id': 'search_1',
    'content': [
      {'type': 'web_search_result', 'url': 'https://example.com/source', 'title': 'Source'},
    ],
  }),
  _start(6, {'type': 'container_upload', 'file_id': 'file_artifact'}),
  for (final index in [1, 0, 4, 2, 3, 5, 6])
    _sse('content_block_stop', {'type': 'content_block_stop', 'index': index}),
  _sse('ping', {'type': 'ping'}),
  _sse('future_event', {
    'type': 'future_event',
    'detail': {'keep': true},
  }),
  _sse('message_delta', {
    'type': 'message_delta',
    'delta': {
      'stop_reason': 'pause_turn',
      'stop_sequence': null,
      'stop_details': {'type': 'pause_turn', 'reason': 'provider work pending'},
      'container': {'id': 'container_1'},
    },
    'usage': {'output_tokens': 14},
  }),
  _sse('message_stop', {'type': 'message_stop'}),
].join();

String _start(int index, Map<String, Object?> block) => _sse('content_block_start', {
  'type': 'content_block_start',
  'index': index,
  'content_block': block,
});

String _delta(int index, Map<String, Object?> delta) => _sse('content_block_delta', {
  'type': 'content_block_delta',
  'index': index,
  'delta': delta,
});

final String _malformedStream = [
  _sse('message_start', {'type': 'message_start', 'message': _streamStart}),
  _start(0, {'type': 'tool_use', 'id': 'weather_1', 'name': 'weather', 'input': {}}),
  _delta(0, {'type': 'input_json_delta', 'partial_json': '{"city":'}),
  _sse('content_block_stop', {'type': 'content_block_stop', 'index': 0}),
  _sse('message_delta', {
    'type': 'message_delta',
    'delta': {'stop_reason': 'tool_use', 'stop_sequence': null},
    'usage': {'output_tokens': 2},
  }),
  _sse('message_stop', {'type': 'message_stop'}),
].join();

final String _errorStream = [
  _sse('message_start', {'type': 'message_start', 'message': _streamStart}),
  _start(0, {'type': 'text', 'text': '', 'citations': null}),
  _delta(0, {'type': 'text_delta', 'text': 'Partial'}),
  _sse('error', {
    'type': 'error',
    'error': {'type': 'overloaded_error', 'message': 'busy'},
  }),
].join();

const _streamStart = <String, Object?>{
  'id': 'msg_stream',
  'type': 'message',
  'role': 'assistant',
  'content': <Object?>[],
  'model': 'future-model',
  'stop_reason': null,
  'stop_sequence': null,
  'usage': {'input_tokens': 10, 'output_tokens': 0},
  'future_start_field': {'keep': true},
};

const _completeMessage = <String, Object?>{
  'id': 'msg_stream',
  'type': 'message',
  'role': 'assistant',
  'content': [
    {'type': 'thinking', 'thinking': 'Check sources.', 'signature': 'signed-thinking'},
    {
      'type': 'text',
      'text': 'Found it.',
      'citations': [
        {
          'type': 'web_search_result_location',
          'url': 'https://example.com/source',
          'title': 'Source',
        },
      ],
    },
    {
      'type': 'tool_use',
      'id': 'computer_1',
      'name': 'computer',
      'input': {'action': 'screenshot'},
    },
    {
      'type': 'server_tool_use',
      'id': 'search_1',
      'name': 'web_search',
      'input': {'query': 'docs'},
      'caller': {'type': 'direct'},
    },
    {'type': 'redacted_thinking', 'data': 'encrypted'},
    {
      'type': 'web_search_tool_result',
      'tool_use_id': 'search_1',
      'content': [
        {'type': 'web_search_result', 'url': 'https://example.com/source', 'title': 'Source'},
      ],
    },
    {'type': 'container_upload', 'file_id': 'file_artifact'},
  ],
  'model': 'future-model',
  'stop_reason': 'pause_turn',
  'stop_sequence': null,
  'stop_details': {'type': 'pause_turn', 'reason': 'provider work pending'},
  'container': {'id': 'container_1'},
  'usage': {'input_tokens': 10, 'output_tokens': 14},
  'future_start_field': {'keep': true},
};
