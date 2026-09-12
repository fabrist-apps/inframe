import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:artificer_baseten/artificer_baseten.dart';
import 'package:artificer_core/artificer_core.dart';
import 'package:artificer_core/json.dart';
import 'package:conflux/conflux.dart';
import 'package:test/test.dart';

void main() {
  test('maps image, tools, structured output, and resolved options', () async {
    Map<String, Object?>? received;
    var requests = 0;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      requests++;
      received = jsonDecode(await utf8.decoder.bind(request).join())! as Map<String, Object?>;
      request.response
        ..headers.contentType = ContentType.json
        ..write(jsonEncode(_toolCompletion));
      await request.response.close();
    });
    final provider = BasetenProvider(
      apiKey: 'secret',
      catalogBaseUrl: Uri.parse('http://${server.address.address}:${server.port}/v1'),
    );
    addTearDown(provider.close);
    final model = provider.languageModel(
      'catalog/model',
      options: BasetenModelOptions(
        topK: const Setting.set(40),
        repetitionPenalty: const Setting.set(1.1),
        extraBody: JsonObject({'seed': 7}),
      ),
    );
    final request = GenerationRequest(
      instructions: 'Be concise.',
      messages: [
        UserMessage([
          TextInputPart('Describe '),
          MediaInputPart(
            kind: MediaKind.image,
            mimeType: 'image/png',
            source: BytesMediaSource(Uint8List.fromList([1, 2, 3])),
          ),
        ]),
      ],
      tools: [
        FunctionTool(name: 'lookup', inputSchema: JsonObject({'type': 'object'})),
      ],
      toolChoice: FunctionToolChoice('lookup'),
      output: JsonSchemaOutputFormat(
        name: 'answer',
        schema: JsonObject({'type': 'object'}),
      ),
    );

    final result = await model
        .generate(
          request,
          options: BasetenModelOptions(
            topK: const Setting.clear(),
            extraBody: JsonObject({'seed': 8}),
          ),
        )
        .runFuture();

    expect(requests, 1);
    expect(received, containsPair('seed', 8));
    expect(received!.containsKey('top_k'), isFalse);
    expect(received, containsPair('repetition_penalty', 1.1));
    expect(received!['messages'], [
      {'role': 'system', 'content': 'Be concise.'},
      {
        'role': 'user',
        'content': [
          {'type': 'text', 'text': 'Describe '},
          {
            'type': 'image_url',
            'image_url': {'url': 'data:image/png;base64,AQID'},
          },
        ],
      },
    ]);
    expect(received!['tool_choice'], {
      'type': 'function',
      'function': {'name': 'lookup'},
    });
    expect(received!['response_format'], {
      'type': 'json_schema',
      'json_schema': {
        'name': 'answer',
        'schema': {'type': 'object'},
      },
    });
    final call = result.message.parts.whereType<ApplicationToolCallPart>().single;
    expect(call.id, 'call_1');
    expect((call.arguments as MalformedToolArguments).originalText, '{bad');
    expect(result.message.replay, isNotNull);
  });

  test('known unsupported media and extra-body collisions fail before I/O', () async {
    var requests = 0;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      requests++;
      await request.drain<void>();
      await request.response.close();
    });
    final provider = BasetenProvider(
      apiKey: 'secret',
      catalogBaseUrl: Uri.parse('http://${server.address.address}:${server.port}/v1'),
    );
    addTearDown(provider.close);
    final unsupported = GenerationRequest(
      messages: [
        UserMessage([
          MediaInputPart(
            kind: MediaKind.audio,
            mimeType: 'audio/wav',
            source: BytesMediaSource([1]),
          ),
        ]),
      ],
    );
    final insecureImage = GenerationRequest(
      messages: [
        UserMessage([
          MediaInputPart(
            kind: MediaKind.image,
            mimeType: 'image/png',
            source: UrlMediaSource(Uri.parse('http://example.test/image.png')),
          ),
        ]),
      ],
    );

    expect(
      BasetenModelOptions(topK: const Setting.set(-1)).topK,
      isA<SetSetting<int>>().having((setting) => setting.value, 'value', -1),
    );
    for (final topK in [0, -2]) {
      expect(
        () => BasetenModelOptions(topK: Setting.set(topK)),
        throwsArgumentError,
      );
    }
    expect(
      () => BasetenModelOptions(extraBody: JsonObject({'top_k': 42})),
      throwsArgumentError,
    );
    expect(
      () => BasetenModelOptions(extraBody: JsonObject({'repetition_penalty': 1.2})),
      throwsArgumentError,
    );
    expect(
      await provider.languageModel('model').generate(unsupported).runFutureExit(),
      isA<Failed<GenerationResult, AiError>>(),
    );
    expect(
      await provider.languageModel('model').generate(insecureImage).runFutureExit(),
      isA<Failed<GenerationResult, AiError>>(),
    );
    expect(
      await provider
          .languageModel(
            'model',
            options: BasetenModelOptions(extraBody: JsonObject({'messages': <Object?>[]})),
          )
          .generate(GenerationRequest(messages: [UserMessage.text('hello')]))
          .runFutureExit(),
      isA<Failed<GenerationResult, AiError>>(),
    );
    expect(requests, 0);
  });
}

const _toolCompletion = <String, Object?>{
  'id': 'chat_1',
  'model': 'catalog/model',
  'choices': [
    {
      'index': 0,
      'message': {
        'role': 'assistant',
        'content': null,
        'tool_calls': [
          {
            'id': 'call_1',
            'type': 'function',
            'function': {'name': 'lookup', 'arguments': '{bad'},
          },
        ],
        'baseten_extension': {'keep': true},
      },
      'finish_reason': 'tool_calls',
    },
  ],
};
