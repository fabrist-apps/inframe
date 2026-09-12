import 'dart:io';

import 'package:artificer_core/artificer_core.dart';
import 'package:artificer_core/json.dart';
import 'package:artificer_core/transport.dart';
import 'package:conflux/conflux.dart';
import 'package:test/test.dart';

void main() {
  group('ProviderHttpClient', () {
    test('should make one request and retain native response metadata', () async {
      var requests = 0;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        requests++;
        request.response
          ..statusCode = 200
          ..headers.set('content-type', 'application/json')
          ..headers.set('x-request-id', 'request-1')
          ..write('{"id":"response-1","output":"hello"}');
        await request.response.close();
      });
      final client = ProviderHttpClient(
        baseUrl: Uri.parse('http://${server.address.address}:${server.port}/v1/'),
      );
      addTearDown(client.close);
      final model = _LoopbackModel(client, 'future-model');

      final exit = await Runtime().run(
        model.generate(
          GenerationRequest(messages: [UserMessage.text('hello')]),
        ),
      );

      expect(requests, 1);
      final response = switch (exit) {
        Succeeded(:final value) => value,
        Failed(:final cause) => throw TestFailure('Unexpected failure: $cause'),
      };
      expect(response.metadata.statusCode, 200);
      expect(response.metadata.requestId, 'request-1');
      expect(response.nativePayload.modelId, 'future-model');
      expect(response.text, 'hello');
    });

    test('should preserve provider errors without retrying', () async {
      var requests = 0;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        requests++;
        request.response
          ..statusCode = 429
          ..headers.set('content-type', 'application/json')
          ..headers.set('retry-after', '4')
          ..write('{"error":{"code":"busy","message":"Try later"}}');
        await request.response.close();
      });
      final client = ProviderHttpClient(
        baseUrl: Uri.parse('http://${server.address.address}:${server.port}/'),
      );
      addTearDown(client.close);

      final exit = await Runtime().run(
        client.sendJson(
          ProviderHttpRequest(method: 'POST', path: 'generate'),
          providerId: 'fixture',
          api: 'generate',
          modelId: 'model',
        ),
      );

      expect(requests, 1);
      final error = switch (exit) {
        Failed(cause: Expected(:final error)) => error,
        _ => throw TestFailure('Expected a provider error: $exit'),
      };
      expect(error, isA<ProviderError>());
      final providerError = error as ProviderError;
      expect(providerError.statusCode, 429);
      expect(providerError.code, 'busy');
      expect(providerError.retryAfter, const Duration(seconds: 4));
    });

    test('should stay lazy and allocate one request per concurrent run', () async {
      var requests = 0;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        requests++;
        request.response.write('{}');
        await request.response.close();
      });
      final client = ProviderHttpClient(
        baseUrl: Uri.parse('http://${server.address.address}:${server.port}/'),
      );
      addTearDown(client.close);
      final operation = client.sendJson(
        ProviderHttpRequest(method: 'POST', path: 'generate'),
        providerId: 'fixture',
        api: 'generate',
        modelId: 'model',
      );

      expect(requests, 0);
      final exits = await Future.wait([Runtime().run(operation), Runtime().run(operation)]);

      expect(requests, 2);
      expect(exits, everyElement(isA<Succeeded<NativeResponse<JsonObject>, AiError>>()));
    });

    test('should not follow redirects', () async {
      var redirectedRequests = 0;
      final target = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => target.close(force: true));
      target.listen((request) async {
        redirectedRequests++;
        await request.response.close();
      });
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        request.response
          ..statusCode = HttpStatus.temporaryRedirect
          ..headers.set(
            HttpHeaders.locationHeader,
            'http://${target.address.address}:${target.port}/redirected',
          )
          ..write('{}');
        await request.response.close();
      });
      final client = ProviderHttpClient(
        baseUrl: Uri.parse('http://${server.address.address}:${server.port}/'),
      );
      addTearDown(client.close);

      final exit = await Runtime().run(
        client.sendJson(
          ProviderHttpRequest(method: 'POST', path: 'generate'),
          providerId: 'fixture',
          api: 'generate',
          modelId: 'model',
        ),
      );

      expect(exit, isA<Failed<NativeResponse<JsonObject>, AiError>>());
      expect(redirectedRequests, 0);
    });

    test('should map malformed responses and connection failures', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final port = server.port;
      server.listen((request) async {
        request.response.write('not-json');
        await request.response.close();
      });
      final client = ProviderHttpClient(
        baseUrl: Uri.parse('http://${server.address.address}:$port/'),
      );
      addTearDown(client.close);

      final malformed = await Runtime().run(
        client.sendJson(
          ProviderHttpRequest(method: 'GET', path: 'malformed'),
          providerId: 'fixture',
          api: 'generate',
          modelId: 'model',
        ),
      );
      await server.close(force: true);
      final unavailable = await Runtime().run(
        client.sendJson(
          ProviderHttpRequest(method: 'GET', path: 'unavailable'),
          providerId: 'fixture',
          api: 'generate',
          modelId: 'model',
        ),
      );

      expect(malformed, _expectedError<ProtocolError>());
      expect(unavailable, _expectedError<TransportError>());
    });
  });
}

Matcher _expectedError<E extends AiError>() => isA<Failed<Object?, AiError>>().having(
  (failure) => failure.cause,
  'cause',
  isA<Expected<AiError>>().having((cause) => cause.error, 'error', isA<E>()),
);

final class _LoopbackModel implements LanguageModel {
  _LoopbackModel(this._client, this.modelId);

  final ProviderHttpClient _client;

  @override
  final String modelId;

  @override
  String get providerId => 'fixture';

  @override
  ModelCapabilities get capabilities => ModelCapabilities({
    ModelCapability.textGeneration: CapabilitySupport.supported,
    ModelCapability.streaming: CapabilitySupport.supported,
  });

  @override
  Effect<GenerationResult, AiError> generate(GenerationRequest request) {
    final input = (request.messages.single as UserMessage).parts.single as TextInputPart;
    return _client
        .sendJson(
          ProviderHttpRequest(
            method: 'POST',
            path: 'generate',
            body: JsonObject({
              'model': modelId,
              'messages': [
                {'role': 'user', 'content': input.text},
              ],
              'max_output_tokens': request.options.maxOutputTokens,
            }),
          ),
          providerId: providerId,
          api: 'generate',
          modelId: modelId,
        )
        .flatMap(_normalize);
  }

  Effect<GenerationResult, AiError> _normalize(NativeResponse<JsonObject> response) {
    final output = response.value.toDart()['output'];
    if (output is! String) {
      return Effect.fail(const ProtocolError('Expected string output.'));
    }
    return Effect.succeed(
      GenerationResult(
        message: AssistantMessage([TextOutputPart(output)]),
        finishReason: FinishReason.stop,
        nativePayload: response.payload,
        metadata: response.metadata,
        requestId: response.metadata.requestId,
      ),
    );
  }

  @override
  Flow<GenerationEvent, AiError> stream(GenerationRequest request) =>
      generate(request).asFlow().map(GenerationFinished.new);
}
