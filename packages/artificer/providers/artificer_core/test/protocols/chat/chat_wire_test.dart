import 'dart:convert';
import 'dart:io';

import 'package:artificer_core/artificer_core.dart';
import 'package:artificer_core/src/protocols/chat/chat_dialect.dart';
import 'package:artificer_core/src/protocols/chat/chat_model.dart';
import 'package:artificer_core/src/protocols/chat/chat_models.dart';
import 'package:artificer_core/src/protocols/text_request_policy.dart';
import 'package:conflux/effect.dart';
import 'package:conflux/result.dart';
import 'package:test/test.dart';

void main() {
  group('ChatLanguageModel wire', () {
    late HttpServer server;
    late Runtime runtime;
    setUp(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      runtime = Runtime();
    });
    tearDown(() async {
      await server.close(force: true);
      await runtime.close();
    });
    Uri endpoint(String path) => Uri.parse('http://127.0.0.1:${server.port}$path');
    Map<String, Object?> reply(String model) => {
      'id': 'r',
      'model': model,
      'choices': [
        {
          'index': 0,
          'message': {'role': 'assistant', 'content': 'hello'},
          'finish_reason': 'stop',
        },
      ],
      'unknown': {'retained': true},
    };

    test(
      'should configure two dialects and execute common and native calls exactly once',
      () async {
        final requests = <Map<String, Object?>>[];
        server.listen((request) async {
          final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map<String, Object?>;
          expect(
            request.headers.value('x-fixture-auth'),
            request.uri.path == '/first' ? 'one' : 'two',
          );
          requests.add(body);
          final response = reply(body['model']! as String);
          if (body['n'] == 2) {
            (response['choices']! as List).add({
              'index': 1,
              'message': {'role': 'assistant', 'content': 'second'},
              'finish_reason': 'stop',
            });
          }
          request.response.headers.set('x-request-id', 'request-id');
          request.response.write(jsonEncode(response));
          await request.response.close();
        });
        for (final second in [false, true]) {
          final provider = ChatProvider(
            dialect: ChatDialect(
              providerId: second ? 'second' : 'first',
              api: 'chat',
              endpoint: endpoint(second ? '/second' : '/first'),
              headers: {'x-fixture-auth': second ? 'two' : 'one'},
              instructionRole: second ? 'developer' : 'system',
              maxTokensField: second ? 'max_completion_tokens' : 'max_tokens',
            ),
            defaultOptions: const ChatOptions(seed: Setting.set(3)),
          );
          addTearDown(provider.close);
          final model = provider.languageModel('unlisted:model');
          final before = requests.length;
          final program = model.generate(
            GenerationRequest(instructions: 'important', messages: [UserMessage.text('hello')]),
          );
          expect(requests.length, before);
          final exit = await runtime.run(program);
          expect((exit as Succeeded<GenerationResult, AiError>).value.text, 'hello');
          expect(requests.length, before + 1);
          expect(
            (requests.last['messages']! as List).first['role'],
            second ? 'developer' : 'system',
          );
          expect(requests.last[second ? 'max_completion_tokens' : 'max_tokens'], 4096);
          final raw = await runtime.run(
            model.native(
              NativeChatRequest(
                model: 'native:model',
                messages: [
                  {'role': 'user', 'content': 'native'},
                ],
                n: 2,
                temperature: NativeField.present(null),
              ),
            ),
          );
          final native = (raw as Succeeded<NativeResponse<ChatResponse>, AiError>).value;
          expect(requests.length, before + 2);
          expect(
            requests.last.containsKey(second ? 'max_completion_tokens' : 'max_tokens'),
            isFalse,
          );
          expect(requests.last.containsKey('temperature'), isTrue);
          expect(requests.last['temperature'], isNull);
          expect(model.codec.normalize(native), isA<Failure<GenerationResult, AiError>>());
          expect(
            (model.codec.normalize(
              native,
              choiceIndex: 1,
            ) as Success<GenerationResult, AiError>).value.text,
            'second',
          );
          expect(native.metadata.requestId, 'request-id');
        }
      },
    );

    test('should normalize streamed and unary tool results equivalently with late identity and metadata', () async {
      final annotations = [
        {
          'type': 'url_citation',
          'url_citation': {'url': 'https://example.test', 'start_index': 0, 'end_index': 5},
        },
      ];
      final message = <String, Object?>{
        'role': 'assistant',
        'content': 'hello',
        'tool_calls': [
          {
            'type': 'function',
            'function': {'arguments': '{"q":"x"}', 'name': 'lookup'},
            'id': 'call-1',
          },
        ],
        'annotations': annotations,
        'signature': 'late-signature',
      };
      final native = <String, Object?>{
        'id': 'r',
        'model': 'm',
        'object': 'chat.completion',
        'choices': [
          {
            'index': 0,
            'vendor': {'future': true},
            'finish_reason': 'tool_calls',
            'message': message,
          },
        ],
        'usage': {'prompt_tokens': 3, 'completion_tokens': 4, 'total_tokens': 7},
      };
      server.listen((request) async {
        final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map<String, Object?>;
        if (body['stream'] == true) {
          final frames = <Object?>[
            {
              'id': 'r',
              'model': 'm',
              'object': 'chat.completion.chunk',
              'choices': [
                {
                  'index': 0,
                  'vendor': {'future': true},
                  'delta': {
                    'role': 'assistant',
                    'content': 'hel',
                    'tool_calls': [
                      {
                        'index': 0,
                        'type': 'function',
                        'function': {'arguments': '{"q":'},
                      },
                    ],
                  },
                },
              ],
            },
            {
              'choices': [
                {
                  'index': 0,
                  'delta': {
                    'content': 'lo',
                    'tool_calls': [
                      {
                        'index': 0,
                        'id': 'call-1',
                        'function': {'name': 'lookup', 'arguments': '"x"}'},
                      },
                    ],
                  },
                },
              ],
            },
            {
              'choices': [
                {
                  'index': 0,
                  'delta': {'annotations': annotations, 'signature': 'late-signature'},
                  'finish_reason': 'tool_calls',
                },
              ],
            },
            {
              'type': 'future.event',
              'native': {'retained': true},
            },
            {'choices': <Object?>[], 'usage': native['usage']},
          ];
          for (final frame in frames) {
            request.response.write('data: ${jsonEncode(frame)}\n\n');
          }
          request.response.write('data: [DONE]\n\n');
        } else {
          request.response.write(jsonEncode(native));
        }
        await request.response.close();
      });
      final provider = ChatProvider(
        dialect: ChatDialect(providerId: 'p', api: 'chat', endpoint: endpoint('/chat')),
      );
      addTearDown(provider.close);
      final model = provider.languageModel('m');
      final request = GenerationRequest(messages: [UserMessage.text('hello')]);
      final ordinary = (await runtime.run(
        model.generate(request),
      ) as Succeeded<GenerationResult, AiError>).value;
      final streamed = await runtime.run(model.stream(request).runCollect());
      expect(streamed, isA<Succeeded<List<GenerationEvent>, AiError>>());
      final events = (streamed as Succeeded<List<GenerationEvent>, AiError>).value;
      final completed = events.whereType<GenerationFinished>().single.result;
      expect(completed.message.text, ordinary.message.text);
      expect(completed.native.data, ordinary.native.data);
      expect(completed.usage!.totalTokens, ordinary.usage!.totalTokens);
      expect(completed.native.unknownEvents.length, 1);
      final toolStart = events.whereType<PartStarted>().singleWhere(
        (part) => part.kind == GenerationPartKind.toolCall,
      );
      expect(toolStart.callId, isNull);
      final toolFinish = events.whereType<PartFinished>().singleWhere(
        (part) => part.part is ToolCallPart,
      );
      expect(toolFinish.id, toolStart.id);
      expect((toolFinish.part as ToolCallPart).callId, 'call-1');
      expect(completed.message.replay!.items.single, message);
    });

    test(
      'should enforce endpoint EOF policy, preserve trailing usage and reject missing terminals',
      () async {
        server.listen((request) async {
          final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map;
          final finish = body['model'] == 'finished';
          request.response.write(
            'data: ${jsonEncode({
              'model': body['model'],
              'choices': [
                {
                  'index': 0,
                  'delta': {'content': 'x'},
                  if (finish) 'finish_reason': 'stop',
                },
              ],
            })}\n\n',
          );
          request.response.write('data: {"choices":[],"usage":{"completion_tokens":2}}\n\n');
          await request.response.close();
        });
        final provider = ChatProvider(
          dialect: ChatDialect(
            providerId: 'p',
            api: 'chat',
            endpoint: endpoint('/chat'),
            terminalPolicy: ChatTerminalPolicy.finishThenEof,
          ),
        );
        addTearDown(provider.close);
        final request = GenerationRequest(messages: [UserMessage.text('x')]);
        final good = await runtime.run(
          provider.languageModel('finished').stream(request).runCollect(),
        );
        expect(
          (good as Succeeded<List<GenerationEvent>, AiError>).value
              .whereType<GenerationFinished>()
              .single
              .result
              .usage!
              .outputTokens,
          2,
        );
        final bad = await runtime.run(
          provider.languageModel('unfinished').stream(request).runCollect(),
        );
        expect(
          (bad as Failed<List<GenerationEvent>, AiError>).cause.expectedErrors.single,
          isA<ProtocolError>().having((error) => error.partialOutput, 'partial', isNotNull),
        );
      },
    );

    test('should preserve HTTP retry and request identity through dialect error mapping', () async {
      server.listen((request) async {
        request.response.statusCode = 429;
        request.response.headers.set('retry-after', '5');
        request.response.headers.set('x-request-id', 'retry-id');
        request.response.write('{"fault":{"nested":"unknown"}}');
        await request.response.close();
      });
      final provider = ChatProvider(
        dialect: ChatDialect(
          providerId: 'p',
          api: 'other',
          endpoint: endpoint('/other'),
          decodeError: (data, metadata) => const ProviderError('Mapped fault.', code: 'configured'),
        ),
      );
      addTearDown(provider.close);
      final model = provider.languageModel('m');
      final request = GenerationRequest(messages: [UserMessage.text('x')]);
      expect(() => model.stream(request, eventCapacity: 0), throwsArgumentError);
      expect(
        () => model.streamNative(
          NativeChatRequest(
            model: 'm',
            messages: [
              {'role': 'user', 'content': 'x'},
            ],
          ),
          maxEventBytes: 0,
        ),
        throwsArgumentError,
      );
      final exit = await runtime.run(model.generate(request));
      final error =
          (exit as Failed<GenerationResult, AiError>).cause.expectedErrors.single as ProviderError;
      expect(error.statusCode, 429);
      expect(error.requestId, 'retry-id');
      expect(error.retryAfter, '5');
      expect(error.code, 'configured');
      expect(error.details, {
        'fault': {'nested': 'unknown'},
      });
    });

    test('should apply configured errors and policy before any forbidden wire request', () async {
      var count = 0;
      server.listen((request) async {
        count++;
        request.response.write('{"fault":{"code":"native"}}');
        await request.response.close();
      });
      final provider = ChatProvider(
        dialect: ChatDialect(
          providerId: 'p',
          api: 'other',
          endpoint: endpoint('/other'),
          policy: const TextRequestPolicy(typedFields: {}, unsupportedFields: {'stop'}),
          decodeError: (data, metadata) => data['fault'] != null
              ? ProviderError('Dialect fault.', details: data, statusCode: metadata.statusCode)
              : null,
        ),
      );
      addTearDown(provider.close);
      final model = provider.languageModel('m');
      final blocked = await runtime.run(
        model.generate(
          GenerationRequest(
            messages: [UserMessage.text('x')],
            options: const GenerationOptions(stop: Setting.set(['end'])),
          ),
        ),
      );
      expect(
        (blocked as Failed<GenerationResult, AiError>).cause.expectedErrors.single,
        isA<UnsupportedFeatureError>(),
      );
      expect(count, 0);
      final error = await runtime.run(
        model.generate(GenerationRequest(messages: [UserMessage.text('x')])),
      );
      expect(
        (error as Failed<GenerationResult, AiError>).cause.expectedErrors.single,
        isA<ProviderError>(),
      );
      expect(count, 1);
    });
  });
}
