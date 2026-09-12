import 'dart:convert';
import 'dart:io';

import 'package:artificer_core/artificer_core.dart';
import 'package:artificer_core/json.dart';
import 'package:artificer_openai/artificer_openai.dart';
import 'package:conflux/conflux.dart';
import 'package:test/test.dart';

void main() {
  test('native lifecycle and model discovery issue only explicit requests', () async {
    final requests = <_RecordedRequest>[];
    final replies = <Map<String, Object?>>[
      _response('resp_1', 'queued'),
      _response('resp_1', 'in_progress'),
      _response('resp_1', 'cancelled'),
      _response('resp_2', 'queued'),
      _response('resp_2', 'in_progress'),
      {'id': 'resp_2', 'object': 'response.deleted', 'deleted': true, 'future': 1},
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
      {'object': 'response.input_tokens', 'input_tokens': 41, 'future': true},
      {
        'id': 'cmp_1',
        'object': 'response.compaction',
        'created_at': 123,
        'output': [
          {'id': 'opaque_1', 'type': 'compaction', 'encrypted_content': 'secret'},
        ],
        'usage': {'input_tokens': 40, 'output_tokens': 1, 'total_tokens': 41},
        'future': 'keep',
      },
      {
        'object': 'list',
        'data': [
          {
            'id': 'gpt-future',
            'object': 'model',
            'created': 123,
            'owned_by': 'openai',
            'shutdown_date': null,
            'future': {'keep': true},
          },
        ],
        'future_page': 2,
      },
      {
        'id': 'gpt-future',
        'object': 'model',
        'created': 123,
        'owned_by': 'openai',
        'shutdown_date': null,
        'future': {'keep': true},
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
    final provider = OpenAIProvider(
      apiKey: 'secret',
      baseUrl: Uri.parse('http://${server.address.address}:${server.port}/v1/'),
    );
    addTearDown(provider.close);

    final create = OpenAIResponseRequest(
      model: 'gpt-future',
      input: [OpenAIResponseInputMessage.userText('hello')],
      background: true,
      store: true,
      previousResponseId: 'resp_previous',
    );
    expect(
      (await provider.responses.create(create).runFuture()).value.status,
      OpenAIResponseStatus.queued,
    );
    expect(
      (await provider.responses.retrieve('resp_1').runFuture()).value.status,
      OpenAIResponseStatus.inProgress,
    );
    expect(
      (await provider.responses.cancel('resp_1').runFuture()).value.status,
      OpenAIResponseStatus.cancelled,
    );
    expect((await provider.responses.create(create).runFuture()).value.id, 'resp_2');
    expect(
      (await provider.responses.retrieve('resp_2').runFuture()).value.status,
      OpenAIResponseStatus.inProgress,
    );
    final deleted = await provider.responses.delete('resp_2').runFuture();
    expect(deleted.value.deleted, isTrue);
    expect(deleted.value.extensions.toDart()['future'], 1);
    expect(deleted.metadata.requestId, 'req-6');
    final page = await provider.responses
        .listInputItems(
          'resp_1',
          limit: 10,
          order: OpenAIListOrder.ascending,
          after: 'msg before',
          include: [OpenAIResponseInclude.reasoningEncryptedContent],
        )
        .runFuture();
    expect(page.value.hasMore, isTrue);
    expect(page.value.firstId, 'msg_1');
    expect(page.value.extensions.toDart()['future_page'], 'keep');
    final tokens = await provider.responses
        .countInputTokens(
          OpenAIResponseInputTokensRequest(
            model: 'gpt-future',
            input: [OpenAIResponseInputMessage.userText('hello')],
            previousResponseId: null,
          ),
        )
        .runFuture();
    expect(tokens.value.inputTokens, 41);
    final compact = await provider.responses
        .compact(
          OpenAICompactResponseRequest(
            model: 'gpt-future',
            input: [OpenAIResponseInputMessage.userText('hello')],
          ),
        )
        .runFuture();
    expect(compact.value.output.single.type, 'compaction');
    expect(compact.value.extensions.toDart()['future'], 'keep');
    final models = await provider.models.list().runFuture();
    expect(models.value.data.single.id, 'gpt-future');
    expect(models.value.extensions.toDart()['future_page'], 2);
    final model = await provider.models.retrieve('gpt/future').runFuture();
    expect(model.value.extensions.toDart()['future'], {'keep': true});

    expect(requests.map((request) => '${request.method} ${request.uri}'), [
      'POST /v1/responses',
      'GET /v1/responses/resp_1',
      'POST /v1/responses/resp_1/cancel',
      'POST /v1/responses',
      'GET /v1/responses/resp_2',
      'DELETE /v1/responses/resp_2',
      'GET /v1/responses/resp_1/input_items?limit=10&order=asc&after=msg+before&include=reasoning.encrypted_content',
      'POST /v1/responses/input_tokens',
      'POST /v1/responses/compact',
      'GET /v1/models',
      'GET /v1/models/gpt%2Ffuture',
    ]);
    expect(requests.first.body, containsPair('previous_response_id', 'resp_previous'));
    expect(requests[7].body, containsPair('previous_response_id', null));
    expect(
      OpenAIResponseRequest(
        model: 'gpt-future',
        input: [OpenAIResponseInputMessage.userText('hello')],
      ).toJson().toDart(),
      isNot(contains('previous_response_id')),
    );
    expect(
      OpenAIResponseRequest(
        model: 'gpt-future',
        input: [OpenAIResponseInputMessage.userText('hello')],
        previousResponseId: null,
      ).toJson().toDart(),
      containsPair('previous_response_id', null),
    );
    expect(
      () => OpenAIResponseInputTokensRequest(
        model: 'gpt-future',
        input: [OpenAIResponseInputMessage.userText('hello')],
        extraBody: JsonObject({'model': 'collision'}),
      ),
      throwsArgumentError,
    );
  });

  test('a failed lifecycle response uses the typed error channel', () async {
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
            'error': {'code': 'background_failed', 'message': 'Could not finish.'},
          }),
        );
      await request.response.close();
    });
    final provider = OpenAIProvider(
      apiKey: 'secret',
      baseUrl: Uri.parse('http://${server.address.address}:${server.port}/v1/'),
    );
    addTearDown(provider.close);

    final exit = await provider.responses.retrieve('resp_failed').runFutureExit();

    expect(
      exit,
      isA<Failed<Object?, AiError>>().having(
        (failure) => (failure.cause as Expected<AiError>).error,
        'error',
        isA<ProviderError>()
            .having((error) => error.code, 'code', 'background_failed')
            .having((error) => error.requestId, 'request ID', 'req-failed'),
      ),
    );
  });
}

Map<String, Object?> _response(String id, String status) => {
  'id': id,
  'object': 'response',
  'model': 'gpt-future',
  'status': status,
  'output': <Object?>[],
  'future': {'keep': true},
};

final class _RecordedRequest {
  const _RecordedRequest(this.method, this.uri, this.body);

  final String method;
  final String uri;
  final Map<String, Object?>? body;
}
