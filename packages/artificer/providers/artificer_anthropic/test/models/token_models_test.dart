import 'package:artificer_anthropic/artificer_anthropic.dart';
import 'package:artificer_core/json.dart';
import 'package:test/test.dart';

void main() {
  group('AnthropicMessageTokensRequest', () {
    test('should encode the count endpoint body without create-only fields', () {
      final messages = [AnthropicInputMessage.userText('Hello')];
      final tools = <AnthropicToolDefinition>[
        AnthropicClientTool(
          name: 'weather',
          description: 'Read weather',
          inputSchema: JsonObject({'type': 'object'}),
        ),
      ];
      final request = AnthropicMessageTokensRequest(
        model: 'claude-sonnet-future',
        messages: messages,
        cacheControl: const AnthropicCacheControl(ttl: AnthropicCacheTtl.oneHour),
        outputConfig: AnthropicOutputConfig(
          effort: AnthropicEffort.high,
          schema: JsonObject({}),
        ),
        system: [AnthropicTextBlock('Be concise.')],
        thinking: AnthropicEnabledThinking(budgetTokens: 1024),
        toolChoice: AnthropicNamedToolChoice('weather'),
        tools: tools,
        extraBody: JsonObject({'context_management': <Object?>[]}),
      );
      messages.clear();
      tools.clear();

      final body = request.toJson().toDart();

      expect(body['model'], 'claude-sonnet-future');
      expect(body['messages'], [
        {
          'role': 'user',
          'content': [
            {'type': 'text', 'text': 'Hello'},
          ],
        },
      ]);
      expect(body['cache_control'], {'type': 'ephemeral', 'ttl': '1h'});
      expect(body['system'], [
        {'type': 'text', 'text': 'Be concise.'},
      ]);
      expect(body['tools'], hasLength(1));
      expect(body['context_management'], isEmpty);
      expect(body, isNot(contains('max_tokens')));
      expect(body, isNot(contains('stream')));
      expect(body, isNot(contains('user_profile_id')));
      expect(body, isNot(contains('workspace_id')));
    });

    test('should reject an empty conversation and typed field collisions', () {
      expect(
        () => AnthropicMessageTokensRequest(
          model: 'claude-sonnet-future',
          messages: const [],
        ),
        throwsArgumentError,
      );
      expect(
        () => AnthropicMessageTokensRequest(
          model: 'claude-sonnet-future',
          messages: [AnthropicInputMessage.userText('Hello')],
          extraBody: JsonObject({'model': 'collision'}),
        ),
        throwsArgumentError,
      );
    });
  });

  group('AnthropicMessageTokensCount', () {
    test('should decode input tokens and retain unknown fields', () {
      final count = AnthropicMessageTokensCount.fromJson(
        JsonObject({
          'input_tokens': 42,
          'future': {'kept': true},
        }),
      );

      expect(count.inputTokens, 42);
      expect(count.extensions.toDart()['future'], {'kept': true});
      expect(count.raw.toDart()['input_tokens'], 42);
    });

    test('should reject missing or negative input tokens', () {
      expect(
        () => AnthropicMessageTokensCount.fromJson(JsonObject({})),
        throwsFormatException,
      );
      expect(
        () => AnthropicMessageTokensCount.fromJson(
          JsonObject({'input_tokens': -1}),
        ),
        throwsFormatException,
      );
    });
  });
}
