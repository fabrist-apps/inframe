import 'package:artificer_anthropic/src/messages/message_models.dart';
import 'package:artificer_anthropic/src/messages/tool_models.dart';
import 'package:artificer_core/artificer_core.dart' show ToolExecutionOwner;
import 'package:artificer_core/json.dart';
import 'package:test/test.dart';

void main() {
  group('AnthropicNativeTool', () {
    test('should encode hosted tools with pinned versioned discriminators', () {
      final tools = <AnthropicNativeTool>[
        AnthropicWebSearchTool(
          allowedDomains: const ['docs.example.com'],
          maxUses: 3,
          responseInclusion: AnthropicToolResponseInclusion.excluded,
        ),
        AnthropicWebFetchTool(
          blockedDomains: const ['private.example.com'],
          citationsEnabled: true,
          maxContentTokens: 4096,
          maxUses: 2,
          useCache: false,
          responseInclusion: AnthropicToolResponseInclusion.full,
        ),
        AnthropicCodeExecutionTool(
          allowedCallers: const [
            AnthropicToolCaller.direct,
            AnthropicToolCaller.codeExecution20260521,
          ],
          cacheControl: const AnthropicCacheControl(
            ttl: AnthropicCacheTtl.oneHour,
          ),
          deferLoading: true,
          strict: true,
          extensions: JsonObject({
            'future_option': {'enabled': true},
          }),
        ),
      ];

      expect(
        tools.map((tool) => tool.toJson().toDart()),
        [
          {
            'name': 'web_search',
            'type': 'web_search_20260318',
            'allowed_domains': ['docs.example.com'],
            'max_uses': 3,
            'response_inclusion': 'excluded',
          },
          {
            'name': 'web_fetch',
            'type': 'web_fetch_20260318',
            'blocked_domains': ['private.example.com'],
            'citations': {'enabled': true},
            'max_content_tokens': 4096,
            'max_uses': 2,
            'response_inclusion': 'full',
            'use_cache': false,
          },
          {
            'name': 'code_execution',
            'type': 'code_execution_20260521',
            'allowed_callers': ['direct', 'code_execution_20260521'],
            'cache_control': {'type': 'ephemeral', 'ttl': '1h'},
            'defer_loading': true,
            'strict': true,
            'future_option': {'enabled': true},
          },
        ],
      );
      expect(
        tools.map((tool) => tool.executionOwner),
        everyElement(ToolExecutionOwner.provider),
      );
    });

    test('should encode both pinned tool-search variants', () {
      expect(AnthropicToolSearchTool.bm25().toJson().toDart(), {
        'name': 'tool_search_tool_bm25',
        'type': 'tool_search_tool_bm25_20251119',
      });
      expect(AnthropicToolSearchTool.regex().toJson().toDart(), {
        'name': 'tool_search_tool_regex',
        'type': 'tool_search_tool_regex_20251119',
      });
    });

    test('should encode caller-executed native tools', () {
      final tools = <AnthropicNativeTool>[
        AnthropicComputerTool(
          displayWidthPx: 1920,
          displayHeightPx: 1080,
          displayNumber: 1,
          enableZoom: true,
        ),
        AnthropicBashTool(),
        AnthropicTextEditorTool(maxCharacters: 12000),
        AnthropicMemoryTool(
          inputExamples: [
            JsonObject({'command': 'view', 'path': '/memories'}),
          ],
        ),
      ];

      expect(
        tools.map((tool) => tool.toJson().toDart()),
        [
          {
            'name': 'computer',
            'type': 'computer_20251124',
            'display_width_px': 1920,
            'display_height_px': 1080,
            'display_number': 1,
            'enable_zoom': true,
          },
          {'name': 'bash', 'type': 'bash_20250124'},
          {
            'name': 'str_replace_based_edit_tool',
            'type': 'text_editor_20250728',
            'max_characters': 12000,
          },
          {
            'name': 'memory',
            'type': 'memory_20250818',
            'input_examples': [
              {'command': 'view', 'path': '/memories'},
            ],
          },
        ],
      );
      expect(
        tools.map((tool) => tool.executionOwner),
        everyElement(ToolExecutionOwner.caller),
      );
    });

    test('should detach iterable fields and extension JSON from mutable input', () {
      final domains = ['example.com'];
      final futureOption = <String, Object?>{'mode': 'safe'};
      final tool = AnthropicWebSearchTool(
        allowedDomains: domains,
        extensions: JsonObject({'future_option': futureOption}),
      );

      domains.add('changed.example.com');
      futureOption['mode'] = 'changed';

      expect(tool.allowedDomains, ['example.com']);
      expect(tool.toJson().toDart()['future_option'], {'mode': 'safe'});
      expect(() => tool.allowedDomains.add('blocked.example.com'), throwsUnsupportedError);
    });

    test('should reject invalid tool-specific constraints', () {
      expect(
        () => AnthropicWebSearchTool(allowedDomains: const ['https://example.com']),
        throwsArgumentError,
      );
      expect(
        () => AnthropicWebSearchTool(
          allowedDomains: const ['example.com'],
          blockedDomains: const ['blocked.example.com'],
        ),
        throwsArgumentError,
      );
      expect(() => AnthropicWebFetchTool(maxUses: 0), throwsArgumentError);
      expect(
        () => AnthropicComputerTool(displayWidthPx: 0, displayHeightPx: 1080),
        throwsArgumentError,
      );
      expect(() => AnthropicTextEditorTool(maxCharacters: -1), throwsArgumentError);
    });

    test('should reject extension fields that collide with typed fields', () {
      expect(
        () => AnthropicCodeExecutionTool(
          extensions: JsonObject({'type': 'future_code_execution'}),
        ),
        throwsArgumentError,
      );
      expect(
        () => AnthropicWebFetchTool(
          extensions: JsonObject({'max_uses': 99}),
        ),
        throwsArgumentError,
      );
    });
  });
}
