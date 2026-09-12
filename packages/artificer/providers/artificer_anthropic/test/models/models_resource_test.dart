import 'dart:convert';
import 'dart:io';

import 'package:artificer_anthropic/artificer_anthropic.dart';
import 'package:artificer_core/artificer_core.dart';
import 'package:artificer_core/transport.dart';
import 'package:conflux/conflux.dart';
import 'package:test/test.dart';

void main() {
  group('AnthropicModelsResource', () {
    test('should fetch one explicit page and retrieve an encoded model ID', () async {
      final requests = <_RecordedRequest>[];
      final replies = <Map<String, Object?>>[
        {
          'data': [
            {
              'id': 'claude-sonnet-future',
              'created_at': '2026-08-01T00:00:00Z',
              'display_name': 'Claude Sonnet Future',
              'type': 'model',
              'max_input_tokens': 300000,
              'max_tokens': 64000,
              'capabilities': _capabilities(),
              'future_model': {'kept': true},
            },
          ],
          'has_more': true,
          'first_id': 'claude-sonnet-future',
          'last_id': 'claude-sonnet-future',
          'future_page': 1,
        },
        {
          'id': 'claude/future',
          'created_at': '2026-08-01T00:00:00Z',
          'display_name': 'Claude Future',
          'type': 'model',
          'max_input_tokens': null,
          'max_tokens': null,
          'capabilities': null,
          'future_model': 'kept',
        },
      ];
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        requests.add(
          _RecordedRequest(
            method: request.method,
            uri: request.uri.toString(),
            headers: request.headers,
          ),
        );
        request.response
          ..headers.contentType = ContentType.json
          ..headers.set('x-request-id', 'req-${requests.length}')
          ..write(jsonEncode(replies[requests.length - 1]));
        await request.response.close();
      });
      final client = ProviderHttpClient(
        baseUrl: Uri.parse('http://${server.address.address}:${server.port}/v1/'),
        headers: const {
          'x-api-key': 'secret',
          'anthropic-version': '2023-06-01',
          'anthropic-beta': 'models-future',
          'anthropic-workspace-id': 'wrkspc_test',
        },
      );
      addTearDown(client.close);
      final models = AnthropicModelsResource(client);

      final pendingPage = models.list(
        limit: 7,
        beforeId: 'before cursor',
        afterId: 'after cursor',
      );
      expect(requests, isEmpty);

      final page = await pendingPage.runFuture();
      final model = page.value.data.single;
      expect(page.value.hasMore, isTrue);
      expect(page.value.firstId, 'claude-sonnet-future');
      expect(page.value.lastId, 'claude-sonnet-future');
      expect(page.value.extensions.toDart()['future_page'], 1);
      expect(model.id, 'claude-sonnet-future');
      expect(model.maxInputTokens, 300000);
      expect(model.maxTokens, 64000);
      expect(model.extensions.toDart()['future_model'], {'kept': true});
      expect(model.capabilities!.effort.xhigh, isNull);
      expect(model.capabilities!.thinking.types.adaptive.supported, isTrue);
      expect(
        model.capabilities!.extensions.toDart()['future_capability'],
        'kept',
      );
      expect(page.metadata.requestId, 'req-1');

      final retrieved = await models.retrieve('claude/future').runFuture();
      expect(retrieved.value.id, 'claude/future');
      expect(retrieved.value.capabilities, isNull);
      expect(retrieved.value.extensions.toDart()['future_model'], 'kept');
      expect(retrieved.metadata.requestId, 'req-2');

      expect(requests.map((request) => '${request.method} ${request.uri}'), [
        'GET /v1/models?limit=7&before_id=before+cursor&after_id=after+cursor',
        'GET /v1/models/claude%2Ffuture',
      ]);
      for (final request in requests) {
        expect(request.headers.value('x-api-key'), 'secret');
        expect(request.headers.value('anthropic-version'), '2023-06-01');
        expect(request.headers.value('anthropic-beta'), 'models-future');
        expect(request.headers.value('anthropic-workspace-id'), 'wrkspc_test');
      }
    });

    test('should reject malformed typed model fields through the error channel', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        await request.drain<void>();
        request.response
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode({
              'data': <Object?>[],
              'has_more': 'yes',
              'first_id': null,
              'last_id': null,
            }),
          );
        await request.response.close();
      });
      final client = ProviderHttpClient(
        baseUrl: Uri.parse('http://${server.address.address}:${server.port}/v1/'),
      );
      addTearDown(client.close);

      final exit = await AnthropicModelsResource(client).list().runFutureExit();

      final error = switch (exit) {
        Failed(cause: Expected(:final error)) => error,
        _ => throw TestFailure('Expected a protocol error: $exit'),
      };
      expect(error, isA<ProtocolError>());
    });
  });
}

Map<String, Object?> _capabilities() => {
  'batch': {'supported': true, 'future': 'batch'},
  'citations': {'supported': true},
  'code_execution': {'supported': true},
  'context_management': {
    'clear_thinking_20251015': {'supported': true},
    'clear_tool_uses_20250919': null,
    'compact_20260112': {'supported': false},
    'supported': true,
  },
  'effort': {
    'high': {'supported': true},
    'low': {'supported': true},
    'max': {'supported': false},
    'medium': {'supported': true},
    'supported': true,
    'xhigh': null,
  },
  'image_input': {'supported': true},
  'pdf_input': {'supported': true},
  'structured_outputs': {'supported': true},
  'thinking': {
    'supported': true,
    'types': {
      'adaptive': {'supported': true},
      'enabled': {'supported': true},
      'future_type': true,
    },
  },
  'future_capability': 'kept',
};

final class _RecordedRequest {
  const _RecordedRequest({
    required this.method,
    required this.uri,
    required this.headers,
  });

  final String method;
  final String uri;
  final HttpHeaders headers;
}
