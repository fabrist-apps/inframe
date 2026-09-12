import 'dart:convert';
import 'dart:io';

import 'package:artificer_core/artificer_core.dart';
import 'package:artificer_xai/artificer_xai.dart';
import 'package:conflux/conflux.dart';
import 'package:test/test.dart';

void main() {
  group('XaiResponsesResource', () {
    test('should perform only caller-requested lifecycle operations', () async {
      final requests = <_RecordedRequest>[];
      final replies = <Map<String, Object?>>[
        _response('resp_1', 'completed'),
        _response('resp_1', 'completed'),
        {'id': 'resp_1', 'object': 'response', 'deleted': true, 'future': 1},
        {
          'object': 'list',
          'data': [
            {
              'id': 'msg_1',
              'type': 'message',
              'role': 'user',
              'content': [
                {'type': 'input_text', 'text': 'hello'},
              ],
            },
          ],
          'first_id': 'msg_1',
          'last_id': 'msg_1',
          'has_more': true,
          'future_page': 'keep',
        },
        {
          'id': 'cmp_1',
          'object': 'response.compaction',
          'created_at': 123,
          'model': 'grok-future',
          'output': [
            {'id': 'opaque_1', 'type': 'compaction', 'encrypted_content': 'secret'},
          ],
          'usage': {
            'input_tokens': 40,
            'output_tokens': 1,
            'total_tokens': 41,
            'dropped_message_count': 2,
          },
          'future': 'keep',
        },
      ];
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        final text = await utf8.decoder.bind(request).join();
        requests.add(
          _RecordedRequest(
            request.method,
            request.uri.toString(),
            text.isEmpty ? null : jsonDecode(text) as Map<String, Object?>,
          ),
        );
        request.response
          ..headers.contentType = ContentType.json
          ..headers.set('x-request-id', 'req-${requests.length}')
          ..write(jsonEncode(replies[requests.length - 1]));
        await request.response.close();
      });
      final provider = _provider(server);
      addTearDown(provider.close);
      final create = XaiResponseRequest(
        model: 'grok-future',
        input: [XaiResponseInputMessage.userText('hello')],
        store: true,
        previousResponseId: 'resp_previous',
      );

      expect(
        (await provider.responses.create(create).runFuture()).value.status,
        XaiResponseStatus.completed,
      );
      expect(
        (await provider.responses.retrieve('resp_1').runFuture()).value.status,
        XaiResponseStatus.completed,
      );
      final deleted = await provider.responses.delete('resp_1').runFuture();
      expect(deleted.value.deleted, isTrue);
      expect(deleted.value.extensions.toDart()['future'], 1);
      final page = await provider.responses
          .listInputItems(
            'resp_1',
            limit: 10,
            order: XaiListOrder.ascending,
            after: 'msg before',
          )
          .runFuture();
      expect(page.value.hasMore, isTrue);
      expect(page.value.firstId, 'msg_1');
      expect(page.value.extensions.toDart()['future_page'], 'keep');
      final compact = await provider.responses
          .compact(
            XaiCompactResponseRequest(
              model: 'grok-future',
              input: [XaiResponseInputMessage.userText('hello')],
            ),
          )
          .runFuture();
      expect(compact.value.model, 'grok-future');
      expect(compact.value.output.single.type, 'compaction');
      expect(compact.value.extensions.toDart()['future'], 'keep');

      expect(requests.map((request) => '${request.method} ${request.uri}'), [
        'POST /v1/responses',
        'GET /v1/responses/resp_1',
        'DELETE /v1/responses/resp_1',
        'GET /v1/responses/resp_1/input_items?limit=10&order=asc&after=msg+before',
        'POST /v1/responses/compact',
      ]);
      expect(requests.first.body, containsPair('previous_response_id', 'resp_previous'));
      expect(requests.last.body, isNot(contains('previous_response_id')));
    });

    test('should preserve native failures and reject invented cancellation routes', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        await request.drain<void>();
        request.response
          ..headers.contentType = ContentType.json
          ..headers.set('x-request-id', 'req-failed')
          ..write(
            jsonEncode({
              ..._response('resp_failed', 'failed'),
              'error': {'code': 'stored_failed', 'message': 'Could not finish.'},
            }),
          );
        await request.response.close();
      });
      final provider = _provider(server);
      addTearDown(provider.close);

      final exit = await provider.responses.retrieve('resp_failed').runFutureExit();

      expect(
        exit,
        isA<Failed<Object?, AiError>>().having(
          (failure) => (failure.cause as Expected<AiError>).error,
          'error',
          isA<ProviderError>()
              .having((error) => error.code, 'code', 'stored_failed')
              .having((error) => error.requestId, 'request ID', 'req-failed'),
        ),
      );
    });
  });
}

Map<String, Object?> _response(String id, String status) => {
  'id': id,
  'object': 'response',
  'model': 'grok-future',
  'status': status,
  'output': <Object?>[],
  'future': {'keep': true},
};

XaiProvider _provider(HttpServer server) => XaiProvider(
  apiKey: 'secret',
  baseUrl: Uri.parse('http://${server.address.address}:${server.port}/v1/'),
);

final class _RecordedRequest {
  const _RecordedRequest(this.method, this.uri, this.body);

  final String method;
  final String uri;
  final Map<String, Object?>? body;
}
