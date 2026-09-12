import 'dart:convert';
import 'dart:io';

import 'package:artificer_anthropic/artificer_anthropic.dart';
import 'package:artificer_core/json.dart';
import 'package:conflux/conflux.dart';
import 'package:test/test.dart';

void main() {
  test('countTokens is lazy, explicit, typed, and uses shared headers', () async {
    var requestCount = 0;
    final bodies = <Map<String, Object?>>[];
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      requestCount++;
      expect(request.method, 'POST');
      expect(request.uri.path, '/v1/messages/count_tokens');
      expect(request.headers.value('x-api-key'), 'secret');
      expect(request.headers.value('anthropic-version'), '2023-06-01');
      expect(request.headers.value('anthropic-beta'), 'token-counting-2024-11-01');
      expect(request.headers.value('anthropic-user-profile-id'), 'profile-1');
      bodies.add(jsonDecode(await utf8.decoder.bind(request).join())! as Map<String, Object?>);
      request.response
        ..headers.contentType = ContentType.json
        ..headers.set('request-id', 'count-$requestCount')
        ..write(jsonEncode({'input_tokens': 17, 'future': true}));
      await request.response.close();
    });
    final provider = AnthropicProvider(
      apiKey: 'secret',
      baseUrl: Uri.parse('http://${server.address.address}:${server.port}/v1'),
      betaFeatures: const [AnthropicBeta('token-counting-2024-11-01')],
      userProfileId: 'profile-1',
    );
    addTearDown(provider.close);
    final request = AnthropicMessageTokensRequest(
      model: 'future-model',
      messages: [AnthropicInputMessage.userText('Hello')],
      thinking: const AnthropicAdaptiveThinking(),
      tools: [
        AnthropicClientTool(
          name: 'weather',
          inputSchema: JsonObject({'type': 'object'}),
        ),
      ],
    );
    final operation = provider.messages.countTokens(request);

    expect(requestCount, 0);
    final first = await operation.runFuture();
    final second = await operation.runFuture();

    expect(requestCount, 2);
    expect(first.value.inputTokens, 17);
    expect(first.value.extensions.toDart()['future'], isTrue);
    expect(first.metadata.requestId, 'count-1');
    expect(second.metadata.requestId, 'count-2');
    expect(bodies, everyElement(request.toJson().toDart()));
    expect(first.payload.api, 'messages.count_tokens');
    expect(first.payload.modelId, 'future-model');
  });
}
