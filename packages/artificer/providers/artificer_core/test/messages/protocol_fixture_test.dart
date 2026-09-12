import 'dart:convert';
import 'dart:io';

import 'package:artificer_core/artificer_core.dart';
import 'package:artificer_core/json.dart';
import 'package:test/test.dart';

void main() {
  group('Incompatible protocol fixtures', () {
    test('should preserve OpenAI-style malformed calls and unknown fields', () {
      final native = _fixture('openai_response.json');
      final output = native.toDart()['output']! as List<Object?>;
      final call = output[1]! as Map<String, Object?>;
      final message = AssistantMessage(
        [
          TextOutputPart('hello'),
          ApplicationToolCallPart(
            id: call['call_id']! as String,
            name: call['name']! as String,
            arguments: MalformedToolArguments(
              originalText: call['arguments']! as String,
              issue: 'Unexpected EOF',
            ),
          ),
        ],
        replay: ProviderReplay(
          providerId: 'openai-fixture',
          api: 'responses',
          modelId: 'model',
          items: [ReplayItem(data: native)],
        ),
      );

      final decoded = Message.fromJson(message.toJson()) as AssistantMessage;

      expect(
        (decoded.parts[1] as ApplicationToolCallPart).arguments,
        isA<MalformedToolArguments>(),
      );
      expect(decoded.replay?.items.single.data.toDart()['unknown_future_field'], {'keep': true});
    });

    test('should preserve Anthropic-style provider-owned pending work', () {
      final native = _fixture('anthropic_message.json');
      final content = native.toDart()['content']! as List<Object?>;
      final serverTool = content[1]! as Map<String, Object?>;
      final message = AssistantMessage([
        TextOutputPart(
          'hello',
          citations: [Citation(uri: Uri.parse('https://example.com'))],
        ),
        ProviderToolRecordPart(
          id: serverTool['id']! as String,
          name: serverTool['name']! as String,
          owner: ToolExecutionOwner.provider,
          status: ProviderToolStatus.pending,
          details: JsonObject.fromDart(serverTool['input']),
        ),
      ]);

      final decoded = Message.fromJson(message.toJson()) as AssistantMessage;

      expect(decoded.parts.whereType<ApplicationToolCallPart>(), isEmpty);
      final record = decoded.parts.whereType<ProviderToolRecordPart>().single;
      expect(record.owner, ToolExecutionOwner.provider);
      expect(record.status, ProviderToolStatus.pending);
    });
  });
}

JsonObject _fixture(String name) {
  final source = File(
    'packages/artificer/providers/artificer_core/test/fixtures/protocols/$name',
  ).readAsStringSync();
  return JsonObject.fromDart(jsonDecode(source) as Object?);
}
