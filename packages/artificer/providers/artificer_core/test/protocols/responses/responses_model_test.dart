import 'dart:convert';
import 'dart:io';

import 'package:artificer_core/artificer_core.dart';
import 'package:artificer_core/protocols.dart';
import 'package:artificer_core/transport.dart';
import 'package:conflux/effect.dart';
import 'package:conflux/result.dart';
import 'package:test/test.dart';

import 'responses_fixtures.dart';

void main() {
  group('CompatibleResponsesModel', () {
    test('should finish no-content incomplete output without fabricated usage', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final client = ProviderHttpClient();
      final runtime = Runtime();
      addTearDown(() async {
        await client.close();
        await runtime.close();
        await server.close(force: true);
      });
      server.listen((request) async {
        await request.drain<void>();
        request.response.headers.contentType = ContentType('text', 'event-stream');
        request.response.write(
          'data: ${jsonEncode({
            'type': 'response.incomplete',
            'response': {
              'id': 'blocked',
              'model': 'm',
              'status': 'incomplete',
              'incomplete_details': {'reason': 'content_filter'},
              'output': <Object?>[],
            },
          })}\n\n',
        );
        await request.response.close();
      });
      final model = CompatibleResponsesModel(
        modelId: 'm',
        client: client,
        codec: ResponsesCodec(
          ResponsesDialect(
            providerId: 'p',
            route: (_) => Uri.parse('http://127.0.0.1:${server.port}/'),
            authentication: () => {},
          ),
        ),
      );
      final exit = await runtime.run(
        model.stream(GenerationRequest(messages: [UserMessage.text('x')])).runCollect(),
      );
      final result = (exit as Succeeded<List<GenerationEvent>, AiError>).value
          .whereType<GenerationFinished>()
          .single
          .result;
      expect(result.text, isEmpty);
      expect(result.finishReason, FinishReason.contentFilter);
      expect(result.usage, isNull);
    });

    for (final alternate in [false, true]) {
      test(
        'should use one native path with ${alternate ? 'alternate' : 'standard'} route auth instruction and event hooks',
        () async {
          final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
          final runtime = Runtime();
          final client = ProviderHttpClient();
          addTearDown(() async {
            await client.close();
            await runtime.close();
            await server.close(force: true);
          });
          final bodies = <Map<String, Object?>>[];
          final routes = <String>[];
          final headers = <String?>[];
          server.listen((request) async {
            routes.add(request.uri.path);
            headers.add(request.headers.value(alternate ? 'x-key' : 'authorization'));
            final body =
                jsonDecode(await utf8.decoder.bind(request).join()) as Map<String, Object?>;
            bodies.add(body);
            if (body['model'] == 'bad') {
              request.response.statusCode = 429;
              request.response.headers.set('retry-after', '7');
              request.response.headers.set('x-request-id', 'http-error');
              request.response.write(
                jsonEncode(
                  alternate
                      ? {
                          'fault': {'message': 'limited', 'code': 'limit'},
                        }
                      : {
                          'error': {'message': 'limited', 'code': 'limit'},
                        },
                ),
              );
            } else if (body['stream'] == true) {
              request.response.headers.contentType = ContentType('text', 'event-stream');
              void event(Map<String, Object?> value) =>
                  request.response.write('data: ${jsonEncode(value)}\n\n');
              event({
                'type': 'response.created',
                'response': {'id': 'r1'},
              });
              event({
                'type': 'response.output_item.added',
                'output_index': 2,
                'item': {'type': 'function_call', 'id': 'item', 'call_id': '', 'name': ''},
              });
              event({
                'type': alternate ? 'alt.text' : 'response.output_text.delta',
                'output_index': 0,
                'content_index': 0,
                'delta': 'hel',
              });
              event({
                'type': 'response.function_call_arguments.delta',
                'output_index': 2,
                'delta': '{"x":',
              });
              event({
                'type': 'response.reasoning_summary_text.delta',
                'output_index': 1,
                'summary_index': 0,
                'delta': 'summary',
              });
              event({
                'type': alternate ? 'alt.text' : 'response.output_text.delta',
                'output_index': 0,
                'content_index': 0,
                'delta': 'lo',
              });
              event({
                'type': 'response.function_call_arguments.delta',
                'output_index': 2,
                'delta': '1}',
              });
              event({
                'type': 'future.event',
                'unknown': {'nested': true},
              });
              event({
                'type': alternate ? 'alt.done' : 'response.completed',
                'response': responseFixture(),
              });
            } else {
              request.response.write(jsonEncode(responseFixture()));
            }
            await request.response.close();
          });
          final codec = ResponsesCodec(
            ResponsesDialect(
              providerId: alternate ? 'second' : 'first',
              api: alternate ? 'custom-responses' : 'responses',
              route: (model) => Uri.parse(
                'http://127.0.0.1:${server.port}/${alternate ? 'alternate/$model' : 'responses'}',
              ),
              authentication: () =>
                  alternate ? {'x-key': 'test-key'} : {'authorization': 'Bearer test-key'},
              instructionRole: alternate ? 'developer' : null,
              hostedToolTypes: {'web_search'},
              eventAliases: alternate
                  ? {'alt.text': 'response.output_text.delta', 'alt.done': 'response.completed'}
                  : {},
              nativeError: alternate
                  ? (data, metadata) => data['fault'] is Map
                        ? ProviderError(
                            (data['fault']! as Map)['message'] as String,
                            code: (data['fault']! as Map)['code'] as String,
                            details: data,
                            statusCode: metadata?.statusCode,
                            requestId: metadata?.requestId,
                          )
                        : null
                  : null,
            ),
          );
          final model = CompatibleResponsesModel(modelId: 'm', client: client, codec: codec);
          final request = GenerationRequest(
            messages: [UserMessage.text('hello')],
            instructions: 'rules',
          );
          final effect = model.generate(request);
          expect(bodies, isEmpty);
          final result = (await runtime.run(effect) as Succeeded<GenerationResult, AiError>).value;
          expect(result.text, 'hello');
          expect(bodies, hasLength(1));
          final raw = (await runtime.run(
            model.rawGenerate(request),
          ) as Succeeded<NativeResponse<ResponsesResponse>, AiError>).value;
          final normalized = (codec.normalize(
            raw.value,
            raw.raw,
            metadata: raw.metadata,
          ) as Success<GenerationResult, AiError>).value;
          expect(normalized.message.toMap(), result.message.toMap());
          expect(bodies, hasLength(2));
          const native = ResponsesRequest(
            model: 'm',
            input: [
              {'role': 'user', 'content': 'native'},
            ],
            extraBody: {'neutral_future': true},
          );
          expect(
            await runtime.run(model.create(native)),
            isA<Succeeded<NativeResponse<ResponsesResponse>, AiError>>(),
          );
          expect(bodies.last['neutral_future'], true);
          for (var iteration = 0; iteration < 2; iteration++) {
            final exit = await runtime.run(model.stream(request).runCollect());
            expect(exit, isA<Succeeded<List<GenerationEvent>, AiError>>());
            final events = (exit as Succeeded<List<GenerationEvent>, AiError>).value;
            final streamed = events.whereType<GenerationFinished>().single.result;
            expect(streamed.message.toMap(), result.message.toMap());
            expect(streamed.native.data, result.native.data);
            expect(streamed.native.unknownEvents.single['event'], 'future.event');
            expect(events.whereType<PartStarted>().map((e) => e.id).toSet(), {
              '0:0',
              '1:0',
              '2:0',
              '3:0',
            });
            expect(
              events
                  .whereType<PartDelta>()
                  .where((e) => e.delta is TextDelta)
                  .map((e) => (e.delta as TextDelta).text),
              ['hel', 'lo'],
            );
          }
          expect(bodies, hasLength(5));
          expect(headers.toSet(), {if (alternate) 'test-key' else 'Bearer test-key'});
          expect(routes.toSet(), {if (alternate) '/alternate/m' else '/responses'});
          expect(bodies.first['store'], false);
          if (alternate) {
            expect(bodies.first.containsKey('instructions'), false);
            expect((bodies.first['input']! as List).first, {
              'role': 'developer',
              'content': [
                {'type': 'input_text', 'text': 'rules'},
              ],
            });
          } else {
            expect(bodies.first['instructions'], 'rules');
          }
          final bad = CompatibleResponsesModel(modelId: 'bad', client: client, codec: codec);
          final failure = await runtime.run(bad.generate(request));
          expect(failure, isA<Failed<GenerationResult, AiError>>());
          final cause = (failure as Failed<GenerationResult, AiError>).cause as Expected<AiError>;
          final error = cause.error as ProviderError;
          expect(error.code, 'limit');
          expect(error.statusCode, 429);
          expect(error.retryAfter, '7');
          final before = bodies.length;
          expect(
            await runtime.run(
              model.generate(
                GenerationRequest(
                  messages: [UserMessage.text('x')],
                  options: const GenerationOptions(stop: Setting.set(['x'])),
                ),
              ),
            ),
            isA<Failed<GenerationResult, AiError>>(),
          );
          expect(bodies.length, before);
        },
      );
    }

    test('should fail truncation native errors malformed frames and byte limits without final output', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final runtime = Runtime();
      final client = ProviderHttpClient();
      addTearDown(() async {
        await client.close();
        await runtime.close();
        await server.close(force: true);
      });
      server.listen((request) async {
        await request.drain<void>();
        request.response.headers.contentType = ContentType('text', 'event-stream');
        request.response.write(
          'data: {"type":"response.output_text.delta","output_index":0,"delta":"partial"}\n\n',
        );
        switch (request.uri.path) {
          case '/error':
            request.response.write('data: {"type":"error","error":{"message":"failed"}}\n\n');
          case '/malformed':
            request.response.write('data: {broken\n\n');
          case '/limit':
            request.response.write(
              'data: ${jsonEncode({'type': 'response.output_text.delta', 'output_index': 0, 'delta': List.filled(1000, 'x').join()})}\n\n',
            );
        }
        await request.response.close();
      });
      for (final path in ['truncated', 'error', 'malformed', 'limit']) {
        final codec = ResponsesCodec(
          ResponsesDialect(
            providerId: 'p',
            route: (_) => Uri.parse('http://127.0.0.1:${server.port}/$path'),
            authentication: () => {},
          ),
        );
        final model = CompatibleResponsesModel(
          modelId: 'm',
          client: client,
          codec: codec,
          maxResponseBytes: 512,
        );
        final received = <GenerationEvent>[];
        final exit = await runtime.run(
          model
              .stream(GenerationRequest(messages: [UserMessage.text('x')]))
              .runForEach(
                (event, _) => Effect.sync((_) {
                  received.add(event);
                }),
              ),
        );
        expect(exit, isA<Failed<void, AiError>>());
        expect(received.whereType<GenerationFinished>(), isEmpty);
        final error = ((exit as Failed<void, AiError>).cause as Expected<AiError>).error;
        final partial = switch (error) {
          ProtocolError(:final partialOutput) => partialOutput,
          ProviderError(:final partialOutput) => partialOutput,
          ResponseLimitError(:final partialOutput) => partialOutput,
          _ => null,
        };
        expect(partial.toString(), contains('partial'));
      }
    });
  });
}
