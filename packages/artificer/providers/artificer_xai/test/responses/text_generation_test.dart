import 'dart:convert';
import 'dart:io';

import 'package:artificer_core/artificer_core.dart';
import 'package:artificer_xai/artificer_xai.dart';
import 'package:conflux/conflux.dart';
import 'package:test/test.dart';

void main() {
  test('native and common generation share the typed Responses mapper', () async {
    final bodies = <Map<String, Object?>>[];
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      expect(request.uri.path, '/v1/responses');
      expect(request.headers.value('authorization'), 'Bearer secret');
      bodies.add(jsonDecode(await utf8.decoder.bind(request).join())! as Map<String, Object?>);
      request.response
        ..headers.contentType = ContentType.json
        ..headers.set('x-request-id', 'request-1')
        ..write(jsonEncode(_response));
      await request.response.close();
    });
    final provider = XaiProvider(
      apiKey: 'secret',
      baseUrl: Uri.parse('http://${server.address.address}:${server.port}/v1/'),
    );
    addTearDown(provider.close);

    final native = await provider.responses
        .create(
          XaiResponseRequest(
            model: 'future-model',
            input: [XaiResponseInputMessage.userText('hello')],
            instructions: 'Be direct.',
            store: false,
            maxOutputTokens: 4096,
          ),
        )
        .runFuture();
    final model = provider.languageModel('future-model');
    final common = await model
        .generate(
          GenerationRequest(
            instructions: 'Be direct.',
            messages: [UserMessage.text('hello')],
          ),
        )
        .runFuture();
    final mappedAgain = provider.responses.normalize(native);

    expect(native.value.id, 'resp_1');
    expect(native.value.status, XaiResponseStatus.completed);
    expect(native.value.extensions.toDart()['future_field'], {'keep': true});
    expect(native.metadata.requestId, 'request-1');
    expect(common.text, 'Hello.');
    expect(common.toJson().toDart(), mappedAgain.toJson().toDart());
    expect(bodies, hasLength(2));
    expect(bodies.last, {
      'model': 'future-model',
      'input': [
        {
          'role': 'user',
          'content': [
            {'type': 'input_text', 'text': 'hello'},
          ],
        },
      ],
      'instructions': 'Be direct.',
      'max_output_tokens': 4096,
      'store': false,
      'stream': false,
      'include': ['reasoning.encrypted_content'],
    });
  });

  test('text stream requires terminal semantics and matches ordinary output', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      await request.drain<void>();
      request.response
        ..headers.contentType = ContentType('text', 'event-stream')
        ..headers.set('x-request-id', 'request-stream')
        ..write(
          'data: ${jsonEncode({
            'type': 'response.created',
            'sequence_number': 0,
            'response': {..._response, 'status': 'in_progress', 'output': <Object?>[]},
          })}\n\n',
        )
        ..write(
          'data: ${jsonEncode({'type': 'response.output_text.delta', 'sequence_number': 1, 'item_id': 'msg_1', 'output_index': 0, 'content_index': 0, 'delta': 'Hello.', 'logprobs': <Object?>[]})}\n\n',
        )
        ..write(
          'data: ${jsonEncode({'type': 'response.completed', 'sequence_number': 2, 'response': _response})}\n\n',
        );
      await request.response.close();
    });
    final provider = XaiProvider(
      apiKey: 'secret',
      baseUrl: Uri.parse('http://${server.address.address}:${server.port}/v1/'),
    );
    addTearDown(provider.close);

    final native = await provider.responses
        .stream(
          XaiResponseRequest(
            model: 'future-model',
            input: [XaiResponseInputMessage.userText('hello')],
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
      'response.created',
      'response.output_text.delta',
      'response.completed',
    ]);
    expect(native.last, isA<XaiResponseCompletedEvent>());
    expect(common.whereType<TextPartDelta>().single.text, 'Hello.');
    expect(common.whereType<GenerationFinished>().single.result.text, 'Hello.');
  });
}

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
  'future_field': {'keep': true},
};
