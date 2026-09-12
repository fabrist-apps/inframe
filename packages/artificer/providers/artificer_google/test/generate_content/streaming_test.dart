import 'dart:convert';
import 'dart:io';

import 'package:artificer_core/artificer_core.dart';
import 'package:artificer_google/artificer_google.dart';
import 'package:conflux/conflux.dart';
import 'package:test/test.dart';

void main() {
  group('GoogleGenerateContentResource', () {
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
