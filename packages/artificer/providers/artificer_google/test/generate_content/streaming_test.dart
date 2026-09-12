import 'dart:convert';
import 'dart:io';

import 'package:artificer_core/artificer_core.dart';
import 'package:artificer_core/json.dart';
import 'package:artificer_core/transport.dart';
import 'package:artificer_google/artificer_google.dart';
import 'package:conflux/conflux.dart';
import 'package:test/test.dart';

void main() {
  group('GoogleGenerateContentResource', () {
    test('should stream every ordered content kind with stable identities and replay', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        await request.drain<void>();
        if (request.uri.path.endsWith(':generateContent')) {
          request.response
            ..headers.contentType = ContentType.json
            ..write(jsonEncode(_completeContentResponse));
          await request.response.close();
          return;
        }
        request.response
          ..headers.contentType = ContentType('text', 'event-stream')
          ..write('data: ${jsonEncode(_streamChunk('Answer '))}\n\n')
          ..write('data: ${jsonEncode(_streamChunk('done'))}\n\n')
          ..write(
            'data: ${jsonEncode({
              'candidates': [
                {
                  'content': {
                    'role': 'model',
                    'parts': [
                      {'text': 'Thought', 'thought': true, 'thoughtSignature': 'signature'},
                      {
                        'functionCall': {
                          'id': 'call-1',
                          'name': 'lookup',
                          'args': {'query': 'dart'},
                        },
                      },
                      {
                        'executableCode': {'language': 'PYTHON', 'code': 'print(1)'},
                      },
                      {
                        'inlineData': {'mimeType': 'image/png', 'data': 'AA=='},
                      },
                    ],
                  },
                  'finishReason': 'STOP',
                  'index': 0,
                  'groundingMetadata': {
                    'groundingChunks': [
                      {
                        'web': {'uri': 'https://example.test/source', 'title': 'Source'},
                      },
                    ],
                  },
                },
              ],
              'responseId': 'response-stream',
            })}\n\n',
          );
        await request.response.close();
      });
      final provider = _provider(server);
      addTearDown(provider.close);

      final nativeRequest = GoogleGenerateContentRequest(
        model: 'models/future-model',
        contents: [
          GoogleContent(role: 'user', parts: [GooglePart.text('hello')]),
        ],
        tools: [
          GoogleFunctionDeclarationsTool([
            GoogleFunctionDeclaration(
              name: 'lookup',
              parameters: JsonObject({
                'type': 'object',
                'properties': <String, Object?>{},
              }),
            ),
          ]),
        ],
      );
      final ordinaryNative = await provider.models.generateContent(nativeRequest).runFuture();
      final ordinary = provider.models.normalizeGenerateContent(
        ordinaryNative,
        request: nativeRequest,
      );

      final events = await provider
          .languageModel('future-model')
          .stream(
            GenerationRequest(
              messages: [UserMessage.text('hello')],
              tools: [
                FunctionTool(
                  name: 'lookup',
                  inputSchema: JsonObject({
                    'type': 'object',
                    'properties': <String, Object?>{},
                  }),
                ),
              ],
            ),
          )
          .runCollect()
          .runFuture();

      final starts = events.whereType<PartStarted>().toList();
      expect(starts.map((event) => event.partId), [
        'part-0',
        'part-1',
        'part-2',
        'part-3',
        'part-4',
      ]);
      expect(starts.map((event) => event.kind), [
        GenerationPartKind.text,
        GenerationPartKind.reasoning,
        GenerationPartKind.applicationToolCall,
        GenerationPartKind.providerTool,
        GenerationPartKind.opaque,
      ]);
      expect(events.whereType<TextPartDelta>().map((event) => event.text), ['Answer ', 'done']);
      expect(events.whereType<ReasoningPartDelta>().single.text, 'Thought');

      final result = events.whereType<GenerationFinished>().single.result;
      expect(result.message.parts, [
        isA<TextOutputPart>().having((part) => part.text, 'text', 'Answer done'),
        isA<ReasoningSummaryPart>().having((part) => part.text, 'text', 'Thought'),
        isA<ApplicationToolCallPart>().having((part) => part.id, 'id', 'call-1'),
        isA<ProviderToolRecordPart>(),
        isA<OpaqueOutputPart>(),
      ]);
      expect((result.message.parts.first as TextOutputPart).citations.single.title, 'Source');
      expect(result.message.replay!.items.map((item) => item.phase), [
        'content',
        'candidate-metadata',
      ]);
      expect(
        result.message.replay!.items.first.data.encode(),
        contains('thoughtSignature'),
      );
      expect(
        result.message.parts.map((part) => part.toDart()),
        ordinary.message.parts.map((part) => part.toDart()),
      );
      final streamedReplay = result.message.replay!.items;
      final ordinaryReplay = ordinary.message.replay!.items;
      expect(streamedReplay.map((item) => item.phase), ordinaryReplay.map((item) => item.phase));
      for (final (index, item) in streamedReplay.indexed) {
        expect(item.data.toDart(), ordinaryReplay[index].data.toDart());
      }
    });

    test('should stream native chunks and common text through normal EOF', () async {
      final requests = <String>[];
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        requests.add('${request.method} ${request.uri}');
        await request.drain<void>();
        request.response
          ..headers.contentType = ContentType('text', 'event-stream')
          ..headers.set('x-request-id', 'stream-request')
          ..write('data: ${jsonEncode(_streamChunk('Hel'))}\n\n')
          ..write('data: ${jsonEncode(_streamChunk('lo', finishReason: 'STOP'))}\n\n')
          ..write(
            'data: ${jsonEncode({
              'usageMetadata': {
                'promptTokenCount': 2,
                'candidatesTokenCount': 1,
                'totalTokenCount': 3,
                'futureUsage': true,
              },
              'responseId': 'response-stream',
            })}\n\n',
          );
        await request.response.close();
      });
      final provider = _provider(server);
      addTearDown(provider.close);
      final nativeRequest = GoogleGenerateContentRequest(
        model: 'models/future-model',
        contents: [
          GoogleContent(role: 'user', parts: [GooglePart.text('hello')]),
        ],
      );

      final native = await provider.models
          .streamGenerateContent(nativeRequest)
          .runCollect()
          .runFuture();
      final LanguageModel erased = provider.languageModel('future-model');
      final common = await erased
          .stream(GenerationRequest(messages: [UserMessage.text('hello')]))
          .runCollect()
          .runFuture();

      expect(native, hasLength(3));
      expect(native.last.value.usageMetadata?.extensions.toDart()['futureUsage'], isTrue);
      expect(native.last.metadata.requestId, 'stream-request');
      expect(common.whereType<TextPartDelta>().map((event) => event.text), ['Hel', 'lo']);
      final finished = common.whereType<GenerationFinished>().single.result;
      expect(finished.text, 'Hello');
      expect(finished.finishReason, FinishReason.stop);
      expect(finished.usage?.totalTokens, 3);
      expect(finished.nativePayload.json.toDart()['chunks']! as List, hasLength(3));
      expect(requests, [
        'POST /v1beta/models/future-model:streamGenerateContent?alt=sse',
        'POST /v1beta/models/future-model:streamGenerateContent?alt=sse',
      ]);
    });

    test('should keep synthesized call IDs unique across streaming tool rounds', () async {
      final bodies = <Map<String, Object?>>[];
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        bodies.add(jsonDecode(await utf8.decoder.bind(request).join())! as Map<String, Object?>);
        request.response
          ..headers.contentType = ContentType('text', 'event-stream')
          ..write('data: ${jsonEncode(_streamToolCall('response-${bodies.length}'))}\n\n');
        await request.response.close();
      });
      final provider = _provider(server);
      addTearDown(provider.close);
      final model = provider.languageModel('future-model');
      final tool = FunctionTool(
        name: 'lookup',
        inputSchema: JsonObject({'type': 'object'}),
      );
      final firstEvents = await model
          .stream(
            GenerationRequest(
              messages: [UserMessage.text('Call the tool.')],
              tools: [tool],
            ),
          )
          .runCollect()
          .runFuture();
      final first = firstEvents.whereType<GenerationFinished>().single.result;
      final firstCall = first.message.parts.whereType<ApplicationToolCallPart>().single;

      final secondEvents = await model
          .stream(
            GenerationRequest(
              messages: [
                UserMessage.text('Call the tool.'),
                first.message,
                ToolMessage([
                  JsonToolResult(
                    callId: firstCall.id,
                    value: JsonValue.fromDart({'value': 42}),
                  ),
                ]),
              ],
              tools: [tool],
            ),
          )
          .runCollect()
          .runFuture();
      final second = secondEvents.whereType<GenerationFinished>().single.result;
      final secondCall = second.message.parts.whereType<ApplicationToolCallPart>().single;

      expect(first.finishReason, FinishReason.toolCalls);
      expect(second.finishReason, FinishReason.toolCalls);
      expect(firstCall.id, 'google-call-response-1-0');
      expect(secondCall.id, 'google-call-response-2-0');
      final replayedResult =
          ((((bodies.last['contents']! as List).last as Map)['parts']! as List).single
                  as Map)['functionResponse']!
              as Map;
      expect(replayedResult.containsKey('id'), isFalse);
    });

    test('should fail a streamed candidate that has no parts', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        await request.drain<void>();
        request.response
          ..headers.contentType = ContentType('text', 'event-stream')
          ..write(
            'data: ${jsonEncode({
              'candidates': [
                {
                  'content': {'role': 'model', 'parts': <Object?>[]},
                  'finishReason': 'STOP',
                },
              ],
            })}\n\n',
          );
        await request.response.close();
      });
      final provider = _provider(server);
      addTearDown(provider.close);

      final exit = await provider
          .languageModel('future-model')
          .stream(GenerationRequest(messages: [UserMessage.text('Hello')]))
          .runCollect()
          .runFutureExit();

      expect(exit, _failedWith<ProtocolError>());
    });

    test('should finish an inspectable blocked stream with trailing usage', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        await request.drain<void>();
        request.response
          ..headers.contentType = ContentType('text', 'event-stream')
          ..write(
            'data: ${jsonEncode({
              'promptFeedback': {
                'blockReason': 'SAFETY',
                'safetyRatings': [
                  {'category': 'HARM_CATEGORY_HATE_SPEECH', 'blocked': true},
                ],
              },
            })}\n\n',
          )
          ..write(
            'data: ${jsonEncode({
              'usageMetadata': {'promptTokenCount': 2, 'totalTokenCount': 2},
            })}\n\n',
          );
        await request.response.close();
      });
      final provider = _provider(server);
      addTearDown(provider.close);

      final events = await provider
          .languageModel('model')
          .stream(GenerationRequest(messages: [UserMessage.text('hello')]))
          .runCollect()
          .runFuture();

      final result = events.whereType<GenerationFinished>().single.result;
      expect(result.finishReason, FinishReason.contentFilter);
      expect(result.message.parts.single, isA<RefusalPart>());
      expect(result.usage?.totalTokens, 2);
    });

    test('should normalize a blocked ordinary response without another request', () async {
      var requests = 0;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        requests++;
        await request.drain<void>();
        request.response
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode({
              'promptFeedback': {
                'blockReason': 'PROHIBITED_CONTENT',
                'futureFeedback': {'keep': true},
              },
            }),
          );
        await request.response.close();
      });
      final provider = _provider(server);
      addTearDown(provider.close);

      final native = await provider.models
          .generateContent(
            GoogleGenerateContentRequest(
              model: 'models/model',
              contents: [
                GoogleContent(role: 'user', parts: [GooglePart.text('hello')]),
              ],
            ),
          )
          .runFuture();
      final result = provider.models.normalizeGenerateContent(native);

      expect(result.finishReason, FinishReason.contentFilter);
      expect(result.message.parts.single, isA<RefusalPart>());
      expect(native.value.promptFeedback?.extensions.toDart()['futureFeedback'], {'keep': true});
      expect(requests, 1);
    });

    test('should fail premature EOF without final success', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        await request.drain<void>();
        request.response
          ..headers.contentType = ContentType('text', 'event-stream')
          ..write('data: ${jsonEncode(_streamChunk('partial'))}\n\n');
        await request.response.close();
      });
      final provider = _provider(server);
      addTearDown(provider.close);

      final exit = await provider
          .languageModel('model')
          .stream(GenerationRequest(messages: [UserMessage.text('hello')]))
          .runCollect()
          .runFutureExit();

      expect(exit, _failedWith<ProtocolError>());
    });

    test('should decode split UTF-8 and retain unknown SSE event metadata', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        await request.drain<void>();
        request.response.headers.contentType = ContentType('text', 'event-stream');
        final record = utf8.encode(
          'event: future-content\n'
          'id: native-event-1\n'
          'data: ${jsonEncode(_streamChunk('Hello 🙂', finishReason: 'STOP'))}\n\n',
        );
        final emoji = record.indexOf(0xf0);
        var offset = 0;
        for (final boundary in [1, emoji + 1, emoji + 3, record.length - 1]) {
          request.response.add(record.sublist(offset, boundary));
          offset = boundary;
        }
        request.response.add(record.sublist(offset));
        await request.response.close();
      });
      final provider = _provider(server);
      addTearDown(provider.close);

      final native = await provider.models
          .streamGenerateContent(_request())
          .runCollect()
          .runFuture();
      final events = await provider
          .languageModel('future-model')
          .stream(GenerationRequest(messages: [UserMessage.text('hello')]))
          .runCollect()
          .runFuture();

      expect(native.single.event, 'future-content');
      expect(native.single.eventId, 'native-event-1');
      expect(events.whereType<TextPartDelta>().single.text, 'Hello 🙂');
      final nativeEvent = events.whereType<ProviderEvent>().single;
      expect(nativeEvent.name, 'future-content');
      expect(nativeEvent.data.toDart()['id'], 'native-event-1');
      final replay = events.whereType<GenerationFinished>().single.result.message.replay!;
      expect(replay.items.last.phase, 'sse-event');
      expect(replay.items.last.data.toDart()['event'], 'future-content');
    });

    test('should fail malformed and service-error records with immutable partial output', () async {
      for (final serviceError in [false, true]) {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        server.listen((request) async {
          await request.drain<void>();
          request.response
            ..headers.contentType = ContentType('text', 'event-stream')
            ..write('data: ${jsonEncode(_streamChunk('partial'))}\n\n')
            ..write(
              serviceError
                  ? 'data: ${jsonEncode({
                      'error': {'code': 429, 'message': 'quota', 'status': 'RESOURCE_EXHAUSTED'},
                    })}\n\n'
                  : 'data: {malformed\n\n',
            );
          await request.response.close();
        });
        final provider = _provider(server);
        final observed = <GenerationEvent>[];

        final exit = await provider
            .languageModel('future-model')
            .stream(GenerationRequest(messages: [UserMessage.text('hello')]))
            .runForEach((event, _) {
              observed.add(event);
              return Effect.succeed(null);
            })
            .runFutureExit();

        final error = _errorFrom(exit);
        expect(error, serviceError ? isA<ProviderError>() : isA<ProtocolError>());
        final partial = switch (error) {
          ProviderError(:final partialOutput) => partialOutput,
          ProtocolError(:final partialOutput) => partialOutput,
          _ => null,
        };
        expect((partial! as AssistantMessage).text, 'partial');
        expect(observed.whereType<GenerationFinished>(), isEmpty);
        await provider.close();
        await server.close(force: true);
      }
    });

    test('should enforce event, stream, and assembled-response limits', () async {
      Future<AiError> runNative({required int maxEventBytes, int? maxStreamBytes}) async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        server.listen((request) async {
          await request.drain<void>();
          request.response
            ..headers.contentType = ContentType('text', 'event-stream')
            ..write(
              'data: ${jsonEncode(_streamChunk('a long response', finishReason: 'STOP'))}\n\n',
            );
          await request.response.close();
        });
        final provider = _provider(server);
        final exit = await provider.models
            .streamGenerateContent(
              _request(),
              decodedEventCapacity: 1,
              maxEventBytes: maxEventBytes,
              maxStreamBytes: maxStreamBytes,
            )
            .runCollect()
            .runFutureExit();
        await provider.close();
        await server.close(force: true);
        return _errorFrom(exit);
      }

      expect(await runNative(maxEventBytes: 12), isA<ResponseLimitError>());
      expect(
        await runNative(maxEventBytes: 1024, maxStreamBytes: 20),
        isA<ResponseLimitError>(),
      );

      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        await request.drain<void>();
        request.response
          ..headers.contentType = ContentType('text', 'event-stream')
          ..write('data: ${jsonEncode(_streamChunk('too long', finishReason: 'STOP'))}\n\n');
        await request.response.close();
      });
      final client = ProviderHttpClient(
        baseUrl: Uri.parse('http://${server.address.address}:${server.port}'),
      );
      addTearDown(client.close);
      final exit = await GoogleGenerateContentResource(client)
          .streamCommon(_request(), maxAssembledBytes: 4)
          .runCollect()
          .runFutureExit();
      expect(exit, _failedWith<ResponseLimitError>());
    });

    test('should fail HTTP-200 service error records with native details', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        await request.drain<void>();
        request.response
          ..headers.contentType = ContentType('text', 'event-stream')
          ..headers.set('x-request-id', 'request-error')
          ..headers.set('retry-after', '5')
          ..write(
            'data: ${jsonEncode({
              'error': {
                'code': 429,
                'message': 'Quota exceeded.',
                'status': 'RESOURCE_EXHAUSTED',
                'details': [
                  {'@type': 'future-detail', 'reason': 'RATE_LIMIT'},
                ],
              },
            })}\n\n',
          );
        await request.response.close();
      });
      final provider = _provider(server);
      addTearDown(provider.close);

      final exit = await provider.models
          .streamGenerateContent(
            GoogleGenerateContentRequest(
              model: 'models/model',
              contents: [
                GoogleContent(role: 'user', parts: [GooglePart.text('hello')]),
              ],
            ),
          )
          .runCollect()
          .runFutureExit();

      final error = _errorFrom(exit) as ProviderError;
      expect(error.code, 'RESOURCE_EXHAUSTED');
      expect(error.statusCode, 429);
      expect(error.requestId, 'request-error');
      expect(error.retryAfter, const Duration(seconds: 5));
      expect(error.details?.toDart(), containsPair('details', isA<List<Object?>>()));
      expect(error.toString(), 'ProviderError');
      expect(error.toString(), isNot(contains('Quota')));
    });
  });
}

Matcher _failedWith<E extends AiError>() => isA<Failed<Object?, AiError>>().having(
  _errorFrom,
  'error',
  isA<E>(),
);

AiError _errorFrom(Object exit) =>
    ((exit as Failed<Object?, AiError>).cause as Expected<AiError>).error;

GoogleProvider _provider(HttpServer server) => GoogleProvider(
  apiKey: 'secret',
  baseUrl: Uri.parse('http://${server.address.address}:${server.port}'),
);

GoogleGenerateContentRequest _request() => GoogleGenerateContentRequest(
  model: 'models/future-model',
  contents: [
    GoogleContent(role: 'user', parts: [GooglePart.text('hello')]),
  ],
);

Map<String, Object?> _streamChunk(String text, {String? finishReason}) => {
  'candidates': [
    {
      'content': {
        'role': 'model',
        'parts': [
          {'text': text},
        ],
      },
      'finishReason': ?finishReason,
      'index': 0,
    },
  ],
  'modelVersion': 'future-model-001',
  'responseId': 'response-stream',
};

Map<String, Object?> _streamToolCall(String responseId) => {
  'candidates': [
    {
      'content': {
        'role': 'model',
        'parts': [
          {
            'functionCall': {
              'name': 'lookup',
              'args': {'query': 'answer'},
            },
          },
        ],
      },
      'finishReason': 'STOP',
      'index': 0,
    },
  ],
  'responseId': responseId,
};

const _completeContentResponse = <String, Object?>{
  'candidates': [
    {
      'content': {
        'role': 'model',
        'parts': [
          {'text': 'Answer done'},
          {'text': 'Thought', 'thought': true, 'thoughtSignature': 'signature'},
          {
            'functionCall': {
              'id': 'call-1',
              'name': 'lookup',
              'args': {'query': 'dart'},
            },
          },
          {
            'executableCode': {'language': 'PYTHON', 'code': 'print(1)'},
          },
          {
            'inlineData': {'mimeType': 'image/png', 'data': 'AA=='},
          },
        ],
      },
      'finishReason': 'STOP',
      'index': 0,
      'groundingMetadata': {
        'groundingChunks': [
          {
            'web': {'uri': 'https://example.test/source', 'title': 'Source'},
          },
        ],
      },
    },
  ],
  'responseId': 'response-stream',
};
