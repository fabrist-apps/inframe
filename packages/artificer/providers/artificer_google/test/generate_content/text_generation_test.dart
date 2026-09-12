import 'dart:convert';
import 'dart:io';

import 'package:artificer_core/artificer_core.dart';
import 'package:artificer_core/json.dart';
import 'package:artificer_google/artificer_google.dart';
import 'package:conflux/conflux.dart';
import 'package:test/test.dart';

void main() {
  group('GoogleLanguageModel', () {
    test('should generate text through concrete and erased public models', () async {
      final bodies = <Map<String, Object?>>[];
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        expect(request.uri.path, '/v1beta/models/future-model:generateContent');
        expect(request.headers.value('x-goog-api-key'), 'secret');
        bodies.add(jsonDecode(await utf8.decoder.bind(request).join())! as Map<String, Object?>);
        _json(request, _response, requestId: 'request-1');
        await request.response.close();
      });
      final provider = _provider(server);
      addTearDown(provider.close);
      final concrete = provider.languageModel('future-model');
      final LanguageModel erased = concrete;
      final request = GenerationRequest(
        instructions: 'Be direct.',
        messages: [
          UserMessage.text('Hello'),
          AssistantMessage([TextOutputPart('Hi')]),
          UserMessage.text('Continue'),
        ],
      );

      final first = await concrete.generate(request).runFuture();
      final second = await erased.generate(request).runFuture();

      expect(first.text, 'Hello.');
      expect(second.text, 'Hello.');
      expect(first.responseId, 'response-1');
      expect(first.requestId, 'request-1');
      expect(first.usage?.totalTokens, 6);
      expect(first.nativePayload.json.toDart()['futureField'], {'keep': true});
      expect(bodies, hasLength(2));
      expect(bodies.first, {
        'contents': [
          {
            'role': 'user',
            'parts': [
              {'text': 'Hello'},
            ],
          },
          {
            'role': 'model',
            'parts': [
              {'text': 'Hi'},
            ],
          },
          {
            'role': 'user',
            'parts': [
              {'text': 'Continue'},
            ],
          },
        ],
        'systemInstruction': {
          'parts': [
            {'text': 'Be direct.'},
          ],
        },
        'generationConfig': {'candidateCount': 1, 'maxOutputTokens': 4096},
      });
    });

    test('should share one offline mapper with native generation', () async {
      var requests = 0;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        requests++;
        await request.drain<void>();
        _json(request, _response);
        await request.response.close();
      });
      final provider = _provider(server);
      addTearDown(provider.close);
      final native = await provider.models
          .generateContent(
            GoogleGenerateContentRequest(
              model: 'models/future-model',
              contents: [
                GoogleContent(role: 'user', parts: [GooglePart.text('Hello')]),
              ],
            ),
          )
          .runFuture();

      final normalized = provider.models.normalizeGenerateContent(native);

      expect(normalized.text, 'Hello.');
      expect(native.value.candidates.single.extensions.toDart()['futureCandidate'], isTrue);
      expect(native.value.candidates.single.content!.parts.single.extensions.toDart(), isEmpty);
      expect(requests, 1);
    });

    test('should require an explicit index for multiple native candidates', () {
      final response = NativeResponse(
        value: GoogleGenerateContentResponse.fromJson(
          JsonObject({
            'candidates': [
              _candidate('one'),
              _candidate('two'),
            ],
          }),
        ),
        payload: NativePayload(
          providerId: 'google',
          api: 'generateContent',
          modelId: 'model',
          json: JsonObject({}),
        ),
        metadata: ResponseMetadata(statusCode: 200),
      );
      final provider = GoogleProvider(apiKey: 'secret');
      addTearDown(provider.close);

      expect(
        () => provider.generateContent.normalize(response),
        throwsA(isA<InvalidRequestError>()),
      );
      expect(provider.generateContent.normalize(response, candidateIndex: 1).text, 'two');
    });

    test('should inherit, replace, and clear typed model options', () async {
      final bodies = <Map<String, Object?>>[];
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        bodies.add(jsonDecode(await utf8.decoder.bind(request).join())! as Map<String, Object?>);
        _json(request, _response);
        await request.response.close();
      });
      final provider = _provider(server);
      addTearDown(provider.close);
      final model = provider.languageModel(
        'future-model',
        options: GoogleModelOptions(
          thinkingConfig: Setting.set(GoogleThinkingConfig(thinkingBudget: 64)),
          safetySettings: Setting.set([
            GoogleSafetySetting(category: 'HARM_CATEGORY_HATE_SPEECH', threshold: 'BLOCK_LOW'),
          ]),
          cachedContent: const Setting.set('cachedContents/cache-1'),
        ),
      );
      final request = GenerationRequest(messages: [UserMessage.text('Hello')]);

      await model.generate(request).runFuture();
      await model
          .generate(
            request,
            options: GoogleModelOptions(
              thinkingConfig: const Setting.clear(),
              safetySettings: Setting.set([
                GoogleSafetySetting(category: 'HARM_CATEGORY_DANGEROUS_CONTENT', threshold: 'OFF'),
              ]),
              cachedContent: const Setting.clear(),
            ),
          )
          .runFuture();

      expect((bodies.first['generationConfig']! as Map)['thinkingConfig'], {
        'thinkingBudget': 64,
      });
      expect(bodies.first['cachedContent'], 'cachedContents/cache-1');
      expect((bodies.last['generationConfig']! as Map).containsKey('thinkingConfig'), isFalse);
      expect(bodies.last.containsKey('cachedContent'), isFalse);
      expect(bodies.last['safetySettings'], [
        {'category': 'HARM_CATEGORY_DANGEROUS_CONTENT', 'threshold': 'OFF'},
      ]);
    });

    test('should reject unsupported or colliding configuration before I/O', () async {
      var requests = 0;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) {
        requests++;
      });
      final provider = _provider(server);
      addTearDown(provider.close);
      final request = GenerationRequest(messages: [UserMessage.text('Hello')]);
      final collision = provider.languageModel(
        'model',
        options: GoogleModelOptions(extraBody: JsonObject({'contents': []})),
      );

      final collided = await collision.generate(request).runFutureExit();
      final structured = await provider
          .languageModel('model')
          .generate(
            GenerationRequest(
              messages: [UserMessage.text('Hello')],
              output: const JsonObjectOutputFormat(),
            ),
          )
          .runFutureExit();

      expect(collided, _failedWith<InvalidRequestError>());
      expect(structured, _failedWith<UnsupportedFeatureError>());
      expect(requests, 0);
    });

    test('should reject prefixed IDs and keep unfamiliar capabilities unknown', () {
      final provider = GoogleProvider(apiKey: 'secret');
      addTearDown(provider.close);

      expect(() => provider.languageModel(''), throwsArgumentError);
      expect(() => provider.languageModel('models/gemini'), throwsArgumentError);
      final model = provider.languageModel('unlisted-future-model');
      expect(model.modelId, 'unlisted-future-model');
      expect(model.capabilities[ModelCapability.textGeneration], CapabilitySupport.supported);
      expect(model.capabilities[ModelCapability.imageInput], CapabilitySupport.unknown);
    });
  });
}

Matcher _failedWith<E extends AiError>() => isA<Failed<Object?, AiError>>().having(
  (failure) => failure.cause,
  'cause',
  isA<Expected<AiError>>().having((expected) => expected.error, 'error', isA<E>()),
);

GoogleProvider _provider(HttpServer server) => GoogleProvider(
  apiKey: 'secret',
  baseUrl: Uri.parse('http://${server.address.address}:${server.port}'),
);

void _json(HttpRequest request, Map<String, Object?> body, {String? requestId}) {
  request.response
    ..headers.contentType = ContentType.json
    ..headers.set('x-request-id', requestId ?? 'request')
    ..write(jsonEncode(body));
}

Map<String, Object?> _candidate(String text) => {
  'content': {
    'role': 'model',
    'parts': [
      {'text': text},
    ],
  },
  'finishReason': 'STOP',
};

const _response = <String, Object?>{
  'candidates': [
    {
      'content': {
        'role': 'model',
        'parts': [
          {'text': 'Hello.'},
        ],
      },
      'finishReason': 'STOP',
      'index': 0,
      'futureCandidate': true,
    },
  ],
  'usageMetadata': {
    'promptTokenCount': 4,
    'candidatesTokenCount': 2,
    'totalTokenCount': 6,
    'thoughtsTokenCount': 1,
  },
  'modelVersion': 'future-model-001',
  'responseId': 'response-1',
  'futureField': {'keep': true},
};
