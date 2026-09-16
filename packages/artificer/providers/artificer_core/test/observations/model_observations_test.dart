import 'dart:convert';
import 'dart:io';

import 'package:artificer_core/artificer_core.dart';
import 'package:artificer_core/protocols.dart';
import 'package:artificer_core/transport.dart';
import 'package:conflux/effect.dart';
import 'package:test/test.dart';

void main() {
  test('normalization and HTTP-200 native errors determine the single attempt outcome', () async {
    final events = <ProviderObservation>[];
    final client = ProviderHttpClient(observer: events.add);
    final runtime = Runtime();
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var requests = 0;
    server.listen((request) async {
      requests++;
      final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map;
      request.response.write(
        jsonEncode(
          body['model'] == 'service-error'
              ? {
                  'error': {'message': 'native message', 'code': 'future_code'},
                }
              : {
                  'id': 'r',
                  'model': 'm',
                  'choices': [
                    {
                      'index': 0,
                      'message': {'role': 'assistant', 'content': 5},
                      'finish_reason': 'stop',
                    },
                  ],
                },
        ),
      );
      await request.response.close();
    });
    addTearDown(() async {
      await client.close();
      await runtime.close();
      await server.close(force: true);
    });
    final dialect = ChatDialect(
      providerId: 'test',
      api: 'chat',
      endpoint: Uri.parse('http://127.0.0.1:${server.port}'),
    );
    for (final modelId in ['bad-content', 'service-error']) {
      final model = ChatLanguageModel(client: client, dialect: dialect, modelId: modelId);
      final exit = await runtime.run(
        model.generate(GenerationRequest(messages: [UserMessage.text('secret')])),
      );
      final failure = exit as Failed<GenerationResult, AiError>;
      expect(
        failure.cause.expectedErrors.single,
        modelId == 'service-error' ? isA<ProviderError>() : isA<ProtocolError>(),
      );
      expect(events.last.outcome, ProviderOutcome.failed);
      expect(events.last.modelId, modelId);
    }
    expect(requests, 2);
    expect(events.where((e) => e.kind == ProviderObservationKind.started), hasLength(2));
    expect(events.where((e) => e.kind == ProviderObservationKind.finished), hasLength(2));
  });
}
