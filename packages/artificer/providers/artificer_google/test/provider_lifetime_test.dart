import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:artificer_core/artificer_core.dart';
import 'package:artificer_google/artificer_google.dart';
import 'package:conflux/conflux.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

void main() {
  group('GoogleProvider', () {
    test('should keep operations lazy with fresh concurrent attempts', () async {
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
      final operation = provider
          .languageModel('future-model')
          .generate(GenerationRequest(messages: [UserMessage.text('hello')]));

      expect(requests, 0);
      final results = await Future.wait([
        operation.runFuture(),
        operation.runFuture(),
        operation.runFuture(),
      ]);

      expect(requests, 3);
      expect(results.map((result) => result.text), everyElement('Hello.'));
    });

    test('should cancel before headers and during body consumption', () async {
      final beforeHeaders = Completer<void>();
      final bodyStarted = Completer<void>();
      var requests = 0;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        requests++;
        await request.drain<void>();
        if (requests == 1) {
          beforeHeaders.complete();
          return;
        }
        request.response.write('{"candidates":[');
        await request.response.flush();
        bodyStarted.complete();
      });
      final provider = _provider(server);
      final runtime = Runtime();
      addTearDown(runtime.close);
      addTearDown(provider.close);
      final effect = provider
          .languageModel('model')
          .generate(GenerationRequest(messages: [UserMessage.text('hello')]));

      final acquiring = runtime.fork(effect);
      await beforeHeaders.future;
      final beforeExit = await acquiring
          .interrupt('before headers')
          .timeout(
            const Duration(seconds: 2),
          );
      final consuming = runtime.fork(effect);
      await bodyStarted.future;
      final bodyExit = await consuming
          .interrupt('during body')
          .timeout(
            const Duration(seconds: 2),
          );

      expect((beforeExit as Failed<Object?, AiError>).cause.containsInterruption, isTrue);
      expect((bodyExit as Failed<Object?, AiError>).cause.containsInterruption, isTrue);
      expect(requests, 2);
    });

    test('should release an early Flow and remain usable', () async {
      var streams = 0;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        await request.drain<void>();
        if (request.uri.path.endsWith(':streamGenerateContent')) {
          streams++;
          request.response
            ..bufferOutput = false
            ..headers.contentType = ContentType('text', 'event-stream')
            ..write('data: ${jsonEncode(_streamChunk)}\n\n');
          await request.response.flush();
          return;
        }
        _json(request, _response);
        await request.response.close();
      });
      final provider = _provider(server);
      addTearDown(provider.close);
      final model = provider.languageModel('model');

      final first = await model
          .stream(GenerationRequest(messages: [UserMessage.text('hello')]))
          .runFirst()
          .runFuture()
          .timeout(const Duration(seconds: 2));
      final generated = await model
          .generate(GenerationRequest(messages: [UserMessage.text('next')]))
          .runFuture()
          .timeout(const Duration(seconds: 2));

      expect(first, isA<Some<GenerationEvent>>());
      expect(generated.text, 'Hello.');
      expect(streams, 1);
    });

    test('should close idempotently while preserving borrowed sibling users', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        if (request.uri.path == '/unrelated') {
          request.response.write('ok');
        } else {
          await request.drain<void>();
          _json(request, _response);
        }
        await request.response.close();
      });
      final borrowed = http.Client();
      addTearDown(borrowed.close);
      final root = Uri.parse('http://${server.address.address}:${server.port}');
      final first = GoogleProvider(apiKey: 'one', baseUrl: root, httpClient: borrowed);
      final sibling = GoogleProvider(apiKey: 'two', baseUrl: root, httpClient: borrowed);
      addTearDown(sibling.close);

      final firstClose = first.close();
      final secondClose = first.close();
      expect(identical(firstClose, secondClose), isTrue);
      await Future.wait([firstClose, secondClose]);
      final closed = await first
          .languageModel('model')
          .generate(GenerationRequest(messages: [UserMessage.text('hello')]))
          .runFutureExit();
      final siblingResult = await sibling
          .languageModel('model')
          .generate(GenerationRequest(messages: [UserMessage.text('hello')]))
          .runFuture();
      final unrelated = await borrowed.get(root.resolve('/unrelated'));

      expect(closed, _failedWith<ClientClosedError>());
      expect(siblingResult.text, 'Hello.');
      expect(unrelated.body, 'ok');
    });

    test('should not follow redirects or retry a generation attempt', () async {
      var requests = 0;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        requests++;
        await request.drain<void>();
        request.response
          ..statusCode = HttpStatus.temporaryRedirect
          ..headers.set(HttpHeaders.locationHeader, '/redirected')
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode({
              'error': {'code': 307, 'message': 'redirect'},
            }),
          );
        await request.response.close();
      });
      final provider = _provider(server);
      addTearDown(provider.close);

      final exit = await provider
          .languageModel('model')
          .generate(GenerationRequest(messages: [UserMessage.text('hello')]))
          .runFutureExit();

      expect(exit, _failedWith<ProviderError>());
      expect(requests, 1);
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

void _json(HttpRequest request, Map<String, Object?> body) {
  request.response
    ..headers.contentType = ContentType.json
    ..write(jsonEncode(body));
}

const _streamChunk = <String, Object?>{
  'candidates': [
    {
      'content': {
        'role': 'model',
        'parts': [
          {'text': 'Hello'},
        ],
      },
    },
  ],
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
    },
  ],
};
