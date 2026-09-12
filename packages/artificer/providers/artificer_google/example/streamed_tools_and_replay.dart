import 'dart:io';

import 'package:artificer_core/artificer_core.dart';
import 'package:artificer_core/json.dart';
import 'package:artificer_google/artificer_google.dart';
import 'package:conflux/conflux.dart';

Future<void> main() async {
  final apiKey = Platform.environment['GEMINI_API_KEY'];
  if (apiKey == null || apiKey.isEmpty) {
    stderr.writeln('Set GEMINI_API_KEY before running this example.');
    return;
  }

  final provider = GoogleProvider(apiKey: apiKey);
  try {
    final model = provider.languageModel('gemini-2.5-flash');
    final weather = FunctionTool(
      name: 'lookup_weather',
      description: 'Looks up the current weather for one city.',
      inputSchema: JsonObject({
        'type': 'object',
        'properties': {
          'city': {'type': 'string'},
        },
        'required': ['city'],
      }),
    );
    final firstRequest = GenerationRequest(
      messages: [UserMessage.text('What is the weather in Chennai?')],
      tools: [weather],
      toolChoice: FunctionToolChoice('lookup_weather'),
    );

    final firstEvents = await model.stream(firstRequest).runCollect().runFuture();
    for (final delta in firstEvents.whereType<TextPartDelta>()) {
      stdout.write(delta.text);
    }
    final first = firstEvents.whereType<GenerationFinished>().single.result;
    final call = first.message.parts.whereType<ApplicationToolCallPart>().single;
    stdout.writeln('\nTool call ${call.name}: ${call.arguments.toJson().encode()}');

    // Serialization retains the assembled signed Google content needed for
    // exact same-model replay. The caller still owns tool execution.
    final replayed = Message.fromJson(first.message.toJson()) as AssistantMessage;
    final resumedRequest = GenerationRequest(
      messages: [
        ...firstRequest.messages,
        replayed,
        ToolMessage([
          JsonToolResult(
            callId: call.id,
            value: JsonValue.fromDart({'temperatureCelsius': 31, 'condition': 'sunny'}),
          ),
        ]),
      ],
      tools: [weather],
    );
    final resumedEvents = await model.stream(resumedRequest).runCollect().runFuture();
    final result = resumedEvents.whereType<GenerationFinished>().single.result;
    stdout
      ..writeln(result.text)
      ..writeln('Total tokens: ${result.usage?.totalTokens ?? 'unknown'}');
  } finally {
    await provider.close();
  }
}
