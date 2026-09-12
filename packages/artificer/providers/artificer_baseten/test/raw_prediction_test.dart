import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:artificer_baseten/artificer_baseten.dart';
import 'package:artificer_core/artificer_core.dart';
import 'package:artificer_core/json.dart';
import 'package:conflux/conflux.dart';
import 'package:test/test.dart';

void main() {
  test('raw streams preserve exact bytes and do not invoke the decoder', () async {
    final fixture = Uint8List.fromList([
      0,
      255,
      ...utf8.encode('data: {"chat":true}\n\n{"jsonl":true}\n'),
    ]);
    final bodies = <Object?>[];
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      expect(request.method, 'POST');
      expect(request.uri.path, '/models/custom/predict');
      expect(request.uri.queryParameters, {'environment': 'green'});
      expect(request.headers.value(HttpHeaders.authorizationHeader), 'Api-Key secret');
      bodies.add(jsonDecode(await utf8.decoder.bind(request).join()));
      request.response
        ..headers.contentType = ContentType.binary
        ..add(fixture.sublist(0, 2));
      await request.response.flush();
      request.response.add(fixture.sublist(2));
      await request.response.close();
    });
    final provider = BasetenProvider(apiKey: 'secret');
    addTearDown(provider.close);
    var encodes = 0;
    var decodes = 0;
    final endpoint = provider.predictionEndpoint<String, Never>(
      endpoint: Uri.parse(
        'http://${server.address.address}:${server.port}/models/custom/predict?environment=green',
      ),
      encode: (input) {
        encodes++;
        return JsonObject({'prompt': input, 'stream': true});
      },
      decode: (_) {
        decodes++;
        throw StateError('raw streaming must not decode JSON');
      },
      decodedChunkCapacity: 1,
      maxResponseBytes: fixture.length,
    );
    final flow = endpoint.predictRawStream('hello');

    expect(encodes, 0);
    final results = await Future.wait([
      flow.runCollect().runFuture(),
      flow.runCollect().runFuture(),
    ]);

    for (final chunks in results) {
      expect(chunks, everyElement(isA<Uint8List>()));
      expect(Uint8List.fromList(chunks.expand((chunk) => chunk).toList()), fixture);
    }
    expect(bodies, [
      {'prompt': 'hello', 'stream': true},
      {'prompt': 'hello', 'stream': true},
    ]);
    expect(encodes, 2);
    expect(decodes, 0);
  });

  test('raw streams keep limits and callback defects explicit', () async {
    var requests = 0;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      requests++;
      await request.drain<void>();
      if (request.uri.path == '/limited') {
        request.response.add([1, 2, 3, 4, 5]);
      } else {
        request.response
          ..statusCode = HttpStatus.tooManyRequests
          ..headers.contentType = ContentType.json
          ..write('{"error":{"message":"busy","code":"rate_limit"}}');
      }
      await request.response.close();
    });
    final origin = 'http://${server.address.address}:${server.port}';
    final provider = BasetenProvider(apiKey: 'secret');
    addTearDown(provider.close);
    final limited = provider.predictionEndpoint<int, int>(
      endpoint: Uri.parse('$origin/limited'),
      encode: JsonNumber.new,
      decode: (_) => 0,
      maxResponseBytes: 4,
    );
    final service = provider.predictionEndpoint<int, int>(
      endpoint: Uri.parse('$origin/service'),
      encode: JsonNumber.new,
      decode: (_) => 0,
    );
    final defective = provider.predictionEndpoint<int, int>(
      endpoint: Uri.parse('$origin/unused'),
      encode: (_) => throw StateError('encoder bug'),
      decode: (_) => 0,
    );

    final limitedExit = await limited.predictRawStream(1).runCollect().runFutureExit();
    final serviceExit = await service.predictRawStream(1).runCollect().runFutureExit();
    final defectExit = await defective.predictRawStream(1).runCollect().runFutureExit();

    expect(limitedExit, _failedWith<ResponseLimitError>());
    expect(serviceExit, _failedWith<ProviderError>());
    expect(
      defectExit,
      isA<Failed<Object?, AiError>>().having(
        (failure) => failure.cause,
        'cause',
        isA<Defect<AiError>>(),
      ),
    );
    expect(requests, 2);
  });
}

Matcher _failedWith<E extends AiError>() => isA<Failed<Object?, AiError>>().having(
  (failure) => (failure.cause as Expected<AiError>).error,
  'error',
  isA<E>(),
);
