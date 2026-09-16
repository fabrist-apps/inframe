import 'dart:convert';
import 'dart:io';

import 'package:artificer_core/artificer_core.dart';
import 'package:artificer_core/protocols.dart';
import 'package:artificer_core/transport.dart';
import 'package:conflux/effect.dart';
import 'package:conflux/result.dart';
import 'package:test/test.dart';

void main() {
  test('Chat unary and streamed replies replay through the requested model alias', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final client = ProviderHttpClient();
    final runtime = Runtime();
    addTearDown(() async {
      await client.close();
      await runtime.close();
      await server.close(force: true);
    });
    server.listen((request) async {
      final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map;
      if (body['stream'] == true) {
        request.response.write(
          'data: ${jsonEncode({
            'model': 'resolved-model',
            'choices': [
              {
                'index': 0,
                'delta': {'role': 'assistant', 'content': 'hello'},
                'finish_reason': 'stop',
              },
            ],
          })}\n\ndata: [DONE]\n\n',
        );
      } else {
        request.response.write(jsonEncode(chatResponse()));
      }
      await request.response.close();
    });
    final model = ChatLanguageModel(
      client: client,
      modelId: 'alias',
      dialect: chatDialect(Uri.parse('http://127.0.0.1:${server.port}')),
    );
    final request = GenerationRequest(messages: [UserMessage.text('hello')]);
    final unary = success(await runtime.run(model.generate(request)));
    final stream = success(await runtime.run(model.stream(request).runCollect()))
        .whereType<GenerationFinished>()
        .single
        .result;
    for (final result in [unary, stream]) {
      expect(result.message.replay!.modelId, 'alias');
      expect((result.native.data! as Map)['model'], 'resolved-model');
      final next = GenerationRequest(messages: [result.message, UserMessage.text('continue')]);
      expect(model.codec.request('alias', next), isA<Success<Map<String, Object?>, AiError>>());
    }
  });

  test('Chat normalization rejects a foreign provider or API envelope', () {
    final codec = ChatCodec(chatDialect(Uri.parse('https://example.test')));
    for (final target in [('foreign', 'chat'), ('test', 'foreign')]) {
      final response = NativeResponse(
        value: const ChatResponse(
          model: 'm',
          choices: [
            ChatChoice(index: 0, message: {'role': 'assistant', 'content': 'hello'}),
          ],
        ),
        raw: NativePayload(
          providerId: target.$1,
          api: target.$2,
          modelId: 'm',
          data: chatResponse(),
        ),
        metadata: const ResponseMetadata(statusCode: 200),
      );
      expect(codec.normalize(response), isA<Failure<GenerationResult, AiError>>());
    }
  });

  test(
    'Chat and Responses native errors preserve message and retry metadata at HTTP 200 and 429',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final client = ProviderHttpClient();
      final runtime = Runtime();
      addTearDown(() async {
        await client.close();
        await runtime.close();
        await server.close(force: true);
      });
      server.listen((request) async {
        request.response.statusCode = request.uri.path.endsWith('429') ? 429 : 200;
        request.response.headers.set('retry-after', '13');
        request.response.headers.set('x-request-id', 'request');
        request.response.write('{"error":{"message":"quota exhausted","code":"future_quota"}}');
        await request.response.close();
      });
      for (final status in [200, 429]) {
        final uri = Uri.parse('http://127.0.0.1:${server.port}/$status');
        final request = GenerationRequest(messages: [UserMessage.text('hello')]);
        final chat = ChatLanguageModel(client: client, modelId: 'm', dialect: chatDialect(uri));
        final responses = CompatibleResponsesModel(
          client: client,
          modelId: 'm',
          codec: responsesCodec(uri),
        );
        for (final operation in [chat.generate(request), responses.generate(request)]) {
          final error =
              (await runtime.run(
                    operation,
                  ) as Failed<GenerationResult, AiError>).cause.expectedErrors.single
                  as ProviderError;
          expect(error.message, 'quota exhausted');
          expect(error.code, 'future_quota');
          expect(error.statusCode, status);
          expect(error.requestId, 'request');
          expect(error.retryAfterDelay, const Duration(seconds: 13));
        }
      }
    },
  );

  test('Responses validates original JSON tool values before string conversion', () {
    final codec = responsesCodec(Uri.parse('https://example.test'));
    const invalid = Usage(inputTokens: 1);
    for (final original in [null, '{}']) {
      final request = GenerationRequest(
        messages: [
          AssistantMessage([
            ToolCallPart(
              callId: 'call',
              name: 'tool',
              arguments: JsonToolArguments(value: {'bad': invalid}, original: original),
            ),
          ]),
        ],
      );
      expect(codec.encode(request, 'm'), isA<Failure<ResponsesRequest, AiError>>());
    }
    final request = GenerationRequest(
      messages: [
        AssistantMessage([
          ToolCallPart(
            callId: 'call',
            name: 'tool',
            arguments: const JsonToolArguments(value: {}),
          ),
        ]),
        ToolMessage([
          ToolSuccess(
            callId: 'call',
            content: const JsonToolResultContent(value: {'bad': invalid}),
          ),
        ]),
      ],
    );
    expect(codec.encode(request, 'm'), isA<Failure<ResponsesRequest, AiError>>());
  });

  for (final hook in ['nativeError', 'toolItem']) {
    test('Responses streamed $hook FormatException remains the original defect', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final client = ProviderHttpClient();
      final runtime = Runtime();
      addTearDown(() async {
        await client.close();
        await runtime.close();
        await server.close(force: true);
      });
      server.listen((request) async {
        request.response.write(
          'data: ${jsonEncode({
            'type': 'response.completed',
            'response': {
              'id': 'r',
              'model': 'm',
              'status': 'completed',
              'output': [
                {'type': 'future'},
              ],
            },
          })}\n\n',
        );
        await request.response.close();
      });
      const failure = FormatException('provider hook bug');
      final codec = ResponsesCodec(
        ResponsesDialect(
          providerId: 'test',
          route: (_) => Uri.parse('http://127.0.0.1:${server.port}'),
          authentication: () => {},
          nativeError: hook == 'nativeError' ? (_, _) => throw failure : null,
          toolItem: hook == 'toolItem' ? (_) => throw failure : null,
        ),
      );
      final model = CompatibleResponsesModel(client: client, modelId: 'm', codec: codec);
      final exit = await runtime.run(
        model.stream(GenerationRequest(messages: [UserMessage.text('hello')])).runCollect(),
      );
      final cause = (exit as Failed<List<GenerationEvent>, AiError>).cause;
      expect(cause, isA<Defect<AiError>>());
      expect((cause as Defect).error, same(failure));
    });
  }
}

Map<String, Object?> chatResponse() => {
  'model': 'resolved-model',
  'choices': [
    {
      'index': 0,
      'message': {'role': 'assistant', 'content': 'hello'},
      'finish_reason': 'stop',
    },
  ],
};
ChatDialect chatDialect(Uri uri) => ChatDialect(providerId: 'test', api: 'chat', endpoint: uri);
ResponsesCodec responsesCodec(Uri uri) => ResponsesCodec(
  ResponsesDialect(providerId: 'test', route: (_) => uri, authentication: () => {}),
);
T success<T>(Exit<T, AiError> exit) => (exit as Succeeded<T, AiError>).value;
