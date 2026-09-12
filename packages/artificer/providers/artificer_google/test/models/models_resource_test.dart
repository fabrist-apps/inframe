import 'dart:convert';
import 'dart:io';

import 'package:artificer_google/artificer_google.dart';
import 'package:conflux/conflux.dart';
import 'package:test/test.dart';

void main() {
  group('GoogleModelsResource', () {
    test('should list only one explicit page and retrieve authoritative names', () async {
      final requests = <String>[];
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        requests.add('${request.method} ${request.uri}');
        if (request.uri.queryParameters.containsKey('pageSize')) {
          _json(request, {
            'models': [_model],
            'nextPageToken': 'next page',
            'futurePage': true,
          });
        } else {
          _json(request, _model);
        }
        await request.response.close();
      });
      final provider = GoogleProvider(
        apiKey: 'secret',
        baseUrl: Uri.parse('http://${server.address.address}:${server.port}'),
      );
      addTearDown(provider.close);

      final page = await provider.models.list(pageSize: 1, pageToken: 'current page').runFuture();
      final model = await provider.models.retrieve('models/future-model').runFuture();

      expect(page.value.models.single.name, 'models/future-model');
      expect(page.value.nextPageToken, 'next page');
      expect(page.value.extensions.toDart()['futurePage'], isTrue);
      expect(model.value.supportedGenerationMethods, ['generateContent']);
      expect(model.value.extensions.toDart()['futureModel'], {'keep': true});
      expect(requests, [
        'GET /v1beta/models?pageSize=1&pageToken=current+page',
        'GET /v1beta/models/future-model',
      ]);
    });
  });
}

void _json(HttpRequest request, Map<String, Object?> body) {
  request.response
    ..headers.contentType = ContentType.json
    ..write(jsonEncode(body));
}

const _model = <String, Object?>{
  'name': 'models/future-model',
  'baseModelId': 'future-model',
  'version': '001',
  'displayName': 'Future Model',
  'description': 'Fixture model.',
  'inputTokenLimit': 100,
  'outputTokenLimit': 20,
  'supportedGenerationMethods': ['generateContent'],
  'thinking': true,
  'temperature': 0.7,
  'maxTemperature': 2.0,
  'topP': 0.95,
  'topK': 40,
  'futureModel': {'keep': true},
};
