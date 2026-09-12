import 'dart:typed_data';

import 'package:artificer_core/artificer_core.dart';
import 'package:artificer_core/json.dart';
import 'package:test/test.dart';

void main() {
  group('Message serialization', () {
    test('should round-trip media, calls, opaque output, and replay', () {
      final bytes = Uint8List.fromList([1, 2, 3]);
      final replay = ProviderReplay(
        providerId: 'provider',
        api: 'responses',
        modelId: 'model',
        items: [
          ReplayItem(id: 'item-1', phase: 'analysis', data: JsonObject({'signature': 'opaque'})),
        ],
      );
      final messages = <Message>[
        UserMessage([
          TextInputPart('hello'),
          MediaInputPart(
            kind: MediaKind.image,
            mimeType: 'image/png',
            source: BytesMediaSource(bytes),
          ),
          MediaInputPart(
            kind: MediaKind.document,
            mimeType: 'application/pdf',
            source: UrlMediaSource(Uri.parse('https://example.com/file.pdf')),
          ),
        ]),
        AssistantMessage(
          [
            TextOutputPart(
              'answer',
              citations: [
                Citation(uri: Uri.parse('https://example.com/source'), title: 'Source'),
              ],
            ),
            ApplicationToolCallPart(
              id: 'call-1',
              name: 'lookup',
              arguments: JsonToolArguments(JsonObject({'id': 1}), originalText: '{"id":1}'),
            ),
            ProviderToolRecordPart(
              id: 'server-1',
              name: 'web_search',
              owner: ToolExecutionOwner.provider,
              status: ProviderToolStatus.pending,
              details: JsonObject({'state': 'queued'}),
            ),
            OpaqueOutputPart(
              providerId: 'provider',
              api: 'responses',
              kind: 'new_kind',
              data: JsonObject({'x': 1}),
            ),
          ],
          replay: replay,
        ),
        ToolMessage([
          JsonToolResult(callId: 'call-1', value: JsonObject({'found': true})),
        ]),
      ];

      final encoded = messages.map((message) => message.toJson()).toList();
      bytes[0] = 9;
      final decoded = encoded.map(Message.fromJson).toList();

      final user = decoded[0] as UserMessage;
      final media = user.parts[1] as MediaInputPart;
      expect((media.source as BytesMediaSource).bytes, [1, 2, 3]);
      final assistant = decoded[1] as AssistantMessage;
      expect(assistant.text, 'answer');
      expect(assistant.replay?.items.single.phase, 'analysis');
      expect(assistant.parts[1], isA<ApplicationToolCallPart>());
      expect(assistant.parts[2], isA<ProviderToolRecordPart>());
      expect(assistant.parts[3], isA<OpaqueOutputPart>());
    });

    test('should preserve every tool argument variant distinctly', () {
      final arguments = <ToolArguments>[
        JsonToolArguments(JsonObject({'x': 1}), originalText: '{"x":1}'),
        TextToolArguments('free form'),
        NativeToolArguments(
          providerId: 'provider',
          api: 'responses',
          action: JsonObject({'type': 'click'}),
        ),
        MalformedToolArguments(originalText: '{', issue: 'Unexpected EOF'),
      ];

      final decoded = arguments.map((value) => ToolArguments.fromJson(value.toJson())).toList();

      expect(decoded[0], isA<JsonToolArguments>());
      expect(decoded[1], isA<TextToolArguments>());
      expect(decoded[2], isA<NativeToolArguments>());
      expect(decoded[3], isA<MalformedToolArguments>());
      expect((decoded[3] as MalformedToolArguments).originalText, '{');
    });

    test('should round-trip JSON, content, native, and application-error results', () {
      final results = <ToolResult>[
        JsonToolResult(callId: 'json', value: JsonValue.fromDart(true)),
        TextToolResult(callId: 'content', content: [TextInputPart('done')]),
        NativeToolResult(
          callId: 'native',
          providerId: 'provider',
          api: 'responses',
          value: JsonObject({'status': 'ok'}),
        ),
        ApplicationErrorToolResult(callId: 'failed', message: 'Rejected by application'),
      ];

      final decoded = results.map((result) => ToolResult.fromJson(result.toJson())).toList();

      expect(decoded[0], isA<JsonToolResult>());
      expect((decoded[0] as JsonToolResult).value.toDart(), true);
      expect(decoded[1], isA<TextToolResult>());
      expect(decoded[2], isA<NativeToolResult>());
      expect(decoded[3], isA<ApplicationErrorToolResult>());
    });

    test('should reject unknown schema versions', () {
      expect(
        () => Message.fromJson(JsonObject({'schemaVersion': 2, 'type': 'user', 'parts': []})),
        throwsFormatException,
      );
    });
  });

  group('GenerationRequest validation', () {
    test('should preserve tool identity and reject broken histories', () {
      final call = ApplicationToolCallPart(
        id: 'call-1',
        name: 'lookup',
        arguments: TextToolArguments('query'),
      );
      final valid = GenerationRequest(
        messages: [
          UserMessage.text('hello'),
          AssistantMessage([call]),
          ToolMessage([
            TextToolResult(callId: 'call-1', content: [TextInputPart('done')]),
          ]),
        ],
      );
      expect(valid.messages, hasLength(3));

      expect(
        () => GenerationRequest(
          messages: [
            UserMessage.text('hello'),
            ToolMessage([
              TextToolResult(callId: 'missing', content: [TextInputPart('done')]),
            ]),
          ],
        ),
        throwsArgumentError,
      );
      expect(
        () => GenerationRequest(
          messages: [
            AssistantMessage([
              ApplicationToolCallPart(
                id: 'native',
                name: 'click',
                arguments: NativeToolArguments(
                  providerId: 'provider-a',
                  api: 'responses',
                  action: JsonObject({'type': 'click'}),
                ),
              ),
            ]),
            ToolMessage([
              NativeToolResult(
                callId: 'native',
                providerId: 'provider-b',
                api: 'responses',
                value: JsonObject({}),
              ),
            ]),
          ],
        ),
        throwsArgumentError,
      );
      expect(
        () => GenerationRequest(
          messages: [UserMessage.text('hello')],
          tools: [
            FunctionTool(name: 'lookup', inputSchema: JsonObject({})),
            FunctionTool(name: 'lookup', inputSchema: JsonObject({})),
          ],
        ),
        throwsArgumentError,
      );
    });

    test('should validate replay targets explicitly', () {
      final request = GenerationRequest(
        messages: [
          AssistantMessage(
            const [],
            replay: ProviderReplay(
              providerId: 'provider',
              api: 'responses',
              modelId: 'model',
              items: const [],
            ),
          ),
        ],
      );

      expect(
        request.validateReplayTarget(providerId: 'provider', api: 'responses', modelId: 'model'),
        isNull,
      );
      expect(
        request.validateReplayTarget(providerId: 'other', api: 'responses', modelId: 'model'),
        isA<InvalidRequestError>(),
      );
    });
  });
}
