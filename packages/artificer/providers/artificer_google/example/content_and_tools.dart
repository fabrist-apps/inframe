import 'dart:io';

import 'package:artificer_core/artificer_core.dart';
import 'package:artificer_core/json.dart';
import 'package:artificer_google/artificer_google.dart';
import 'package:conflux/conflux.dart';

Future<void> main() async {
  final provider = GoogleProvider(apiKey: 'caller-supplied-key');
  try {
    final model = provider.languageModel('caller-supplied-model');
    final lookup = FunctionTool(
      name: 'lookup_weather',
      description: 'Looks up weather for one city.',
      inputSchema: JsonObject({
        'type': 'object',
        'properties': {
          'city': {'type': 'string'},
        },
        'required': ['city'],
      }),
    );
    final request = GenerationRequest(
      messages: [
        UserMessage([
          TextInputPart('Read the image and look up the city weather.'),
          MediaInputPart(
            kind: MediaKind.image,
            mimeType: 'image/png',
            source: BytesMediaSource(const [137, 80, 78, 71]),
          ),
        ]),
      ],
      tools: [lookup],
      output: JsonSchemaOutputFormat(
        name: 'weather',
        schema: JsonObject({
          'type': 'object',
          'properties': {
            'summary': {'type': 'string'},
          },
          'required': ['summary'],
        }),
      ),
    );

    if (const bool.fromEnvironment('RUN_GOOGLE_EXAMPLE')) {
      final first = await model.generate(request).runFuture();
      final call = first.message.parts.whereType<ApplicationToolCallPart>().single;
      final resumed = GenerationRequest(
        messages: [
          ...request.messages,
          // The returned message carries signed Google replay metadata.
          Message.fromJson(first.message.toJson()) as AssistantMessage,
          ToolMessage([
            JsonToolResult(
              callId: call.id,
              value: JsonValue.fromDart({'temperatureCelsius': 24}),
            ),
          ]),
        ],
        tools: [lookup],
        output: request.output,
      );
      final result = await model.generate(resumed).runFuture();
      stdout.writeln(result.text);
    }
  } finally {
    await provider.close();
  }
}
