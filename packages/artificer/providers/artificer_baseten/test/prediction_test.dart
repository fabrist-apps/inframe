import 'dart:convert';
import 'dart:io';

import 'package:artificer_baseten/artificer_baseten.dart';
import 'package:artificer_core/artificer_core.dart';
import 'package:artificer_core/json.dart';
import 'package:conflux/conflux.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  test('typed predictions use the exact URL and arbitrary JSON values', () async {
    final received = <Object?>[];
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      expect(request.uri.path, '/environments/green/predict');
      expect(request.uri.queryParameters, {'trace': 'on'});
      expect(request.headers.value(HttpHeaders.authorizationHeader), 'Api-Key secret');
      received.add(jsonDecode(await utf8.decoder.bind(request).join()));
      request.response
        ..headers.contentType = ContentType.json
        ..headers.set('x-request-id', 'predict-${received.length}')
        ..write(jsonEncode(received.last));
      await request.response.close();
    });
    final provider = BasetenProvider(apiKey: 'secret');
    addTearDown(provider.close);
    var encodes = 0;
    var decodes = 0;
    final endpoint = provider.predictionEndpoint<List<int>, int>(
      endpoint: Uri.parse(
        'http://${server.address.address}:${server.port}/environments/green/predict?trace=on',
      ),
      encode: (input) {
        encodes++;
        return JsonArray(input);
      },
      decode: (json) {
        decodes++;
        return (json as JsonArray).values.cast<JsonNumber>().fold(
          0,
          (sum, item) => sum + item.value.toInt(),
        );
      },
    );
    final operation = endpoint.predict([1, 2]);

    expect(encodes, 0);
    expect(decodes, 0);
    final [first, second] = await Future.wait([
      operation.runFuture(),
      operation.runFuture(),
    ]);

    expect(first.value, 3);
    expect(second.value, 3);
    expect(first.payload.value.toDart(), [1, 2]);
    expect(first.metadata.requestId, 'predict-1');
    expect(received, [
      [1, 2],
      [1, 2],
    ]);
    expect(encodes, 2);
    expect(decodes, 2);
  });

  test('decoder FormatException is typed and unexpected failures remain defects', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      await request.drain<void>();
      request.response
        ..headers.contentType = ContentType.json
        ..write('null');
      await request.response.close();
    });
    final provider = BasetenProvider(apiKey: 'secret');
    addTearDown(provider.close);
    final endpoint = Uri.parse('http://${server.address.address}:${server.port}/predict');

    final format = await provider
        .predictionEndpoint<int, int>(
          endpoint: endpoint,
          encode: JsonNumber.new,
          decode: (_) => throw const FormatException('expected number'),
        )
        .predict(1)
        .runFutureExit();
    final defect = await provider
        .predictionEndpoint<int, int>(
          endpoint: endpoint,
          encode: JsonNumber.new,
          decode: (_) => throw StateError('bug'),
        )
        .predict(1)
        .runFutureExit();
    final encoderDefect = await provider
        .predictionEndpoint<int, int>(
          endpoint: endpoint,
          encode: (_) => throw StateError('encoder bug'),
          decode: (_) => 1,
        )
        .predict(1)
        .runFutureExit();

    expect(
      format,
      isA<Failed<Object?, AiError>>().having(
        (failure) => (failure.cause as Expected<AiError>).error,
        'error',
        isA<ProtocolError>().having(
          (error) => error.partialOutput,
          'partialOutput',
          isA<JsonNull>(),
        ),
      ),
    );
    expect(
      defect,
      isA<Failed<Object?, AiError>>().having(
        (value) => value.cause,
        'cause',
        isA<Defect<AiError>>(),
      ),
    );
    expect(
      encoderDefect,
      isA<Failed<Object?, AiError>>().having(
        (value) => value.cause,
        'cause',
        isA<Defect<AiError>>(),
      ),
    );
  });

  test('prediction URLs with double-slash paths preserve their authority', () async {
    late Uri sentUrl;
    final transport = MockClient((request) async {
      sentUrl = request.url;
      return http.Response('[1]', HttpStatus.ok, headers: {'content-type': 'application/json'});
    });
    final provider = BasetenProvider(apiKey: 'secret', httpClient: transport);
    addTearDown(provider.close);
    final configured = Uri.parse('https://example.test//other.test/predict?trace=on');

    await provider
        .predictionEndpoint<int, int>(
          endpoint: configured,
          encode: JsonNumber.new,
          decode: (value) => (value as JsonArray).values.length,
        )
        .predict(1)
        .runFuture();

    expect(sentUrl, configured);
  });
}
