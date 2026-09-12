import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:artificer_baseten/artificer_baseten.dart';
import 'package:artificer_core/artificer_core.dart';
import 'package:artificer_core/json.dart';
import 'package:conflux/conflux.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

void main() {
  test('provider close interrupts catalog and deployment work', () async {
    final started = Completer<void>();
    var requests = 0;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      requests++;
      if (requests == 3 && !started.isCompleted) started.complete();
      await request.drain<void>();
      await Future<void>.delayed(const Duration(seconds: 30));
      await request.response.close();
    });
    final origin = 'http://${server.address.address}:${server.port}';
    final provider = BasetenProvider(
      apiKey: 'secret',
      catalogBaseUrl: Uri.parse('$origin/v1'),
    );
    final deployment = provider.deployment(baseUrl: Uri.parse('$origin/deployment/v1'));
    final catalogRun = provider
        .languageModel('catalog/model')
        .generate(GenerationRequest(messages: [UserMessage.text('wait')]))
        .runFutureExit();
    final deploymentRun = deployment
        .languageModel('served-model')
        .generate(GenerationRequest(messages: [UserMessage.text('wait')]))
        .runFutureExit();
    final prediction = provider.predictionEndpoint<int, int>(
      endpoint: Uri.parse('$origin/predict?environment=test'),
      encode: JsonNumber.new,
      decode: (value) => (value as JsonNumber).value.toInt(),
    );
    final predictionRun = prediction.predictRawStream(1).runCollect().runFutureExit();
    await started.future;

    await Future.wait([provider.close(), provider.close()]);

    expect(await catalogRun, isA<Failed<GenerationResult, AiError>>());
    expect(await deploymentRun, isA<Failed<GenerationResult, AiError>>());
    expect(await predictionRun, isA<Failed<List<Object?>, AiError>>());
    expect(requests, 3);
    expect(
      await provider
          .languageModel('catalog/model')
          .generate(GenerationRequest(messages: [UserMessage.text('closed')]))
          .runFutureExit(),
      _failedWith<ClientClosedError>(),
    );
    expect(
      await prediction.predictRawStream(2).runCollect().runFutureExit(),
      _failedWith<ClientClosedError>(),
    );
  });

  test('closing provider leaves a borrowed client usable', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      await request.drain<void>();
      request.response
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({'ok': true}));
      await request.response.close();
    });
    final borrowed = http.Client();
    addTearDown(borrowed.close);
    final origin = Uri.parse('http://${server.address.address}:${server.port}');
    final provider = BasetenProvider(
      apiKey: 'secret',
      catalogBaseUrl: origin.resolve('/v1'),
      httpClient: borrowed,
    );

    await provider.close();
    final response = await borrowed.get(origin.resolve('/unrelated'));

    expect(response.statusCode, HttpStatus.ok);
    expect(
      () => provider.deployment(baseUrl: origin.resolve('/deployment')),
      throwsStateError,
    );
    expect(
      () => provider.predictionEndpoint<int, int>(
        endpoint: origin.resolve('/predict'),
        encode: JsonNumber.new,
        decode: (value) => (value as JsonNumber).value.toInt(),
      ),
      throwsStateError,
    );
  });
}

Matcher _failedWith<E extends AiError>() => isA<Failed<Object?, AiError>>().having(
  (failure) => (failure.cause as Expected<AiError>).error,
  'error',
  isA<E>(),
);
