import 'dart:convert';

import 'package:artificer_core/artificer_core.dart';
import 'package:artificer_core/json.dart';
import 'package:artificer_core/protocols.dart';
import 'package:artificer_core/transport.dart';
import 'package:conflux/conflux.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

void main() {
  for (final dialect in [_Dialect.openAi, _Dialect.anthropic]) {
    test('${dialect.name} stream matches its nonstream message and replay', () async {
      final client = ProviderHttpClient(
        baseUrl: Uri.parse('https://example.test/'),
        client: _FixtureClient(_fixtureBody(dialect)),
      );
      addTearDown(client.close);

      final events = await client
          .sendSse<GenerationEvent>(
            ProviderHttpRequest(method: 'POST', path: 'generate'),
            createProtocol: () => _FixtureGenerationProtocol(dialect),
          )
          .runCollect()
          .runFuture();
      final finished = events.whereType<GenerationFinished>().single;

      expect(finished.result.toJson().toDart(), _nonstreamResult(dialect).toJson().toDart());
      expect(events.whereType<GenerationFinished>(), hasLength(1));
      expect(events.whereType<TextPartDelta>().map((event) => event.text), ['Hello ', 'world']);
      expect(events.whereType<UsageUpdated>().map((event) => event.usage.totalTokens), [3, 5]);
      expect(events.whereType<ProviderEvent>().single.name, 'future.record');
    });
  }

  test('Google-style candidate finish becomes success only after normal EOF', () async {
    final client = ProviderHttpClient(
      baseUrl: Uri.parse('https://example.test/'),
      client: _FixtureClient(_fixtureBody(_Dialect.google)),
    );
    addTearDown(client.close);

    final events = await client
        .sendSse<GenerationEvent>(
          ProviderHttpRequest(method: 'POST', path: 'generate'),
          createProtocol: () => _FixtureGenerationProtocol(_Dialect.google),
        )
        .runCollect()
        .runFuture();

    expect(events.last, isA<GenerationFinished>());
    expect(events.whereType<GenerationFinished>(), hasLength(1));
  });

  test('service errors under HTTP 200 retain the partial message', () async {
    final body = _sse([
      {'type': 'start', 'id': 'response-1'},
      {'type': 'part_start', 'index': 0, 'kind': 'text'},
      {'type': 'delta', 'index': 0, 'text': 'partial'},
      {
        'type': 'error',
        'code': 'overloaded',
        'message': 'try later',
      },
    ]);
    final client = ProviderHttpClient(
      baseUrl: Uri.parse('https://example.test/'),
      client: _FixtureClient(body),
    );
    addTearDown(client.close);

    final exit = await client
        .sendSse<GenerationEvent>(
          ProviderHttpRequest(method: 'POST', path: 'generate'),
          createProtocol: () => _FixtureGenerationProtocol(_Dialect.openAi),
        )
        .runCollect()
        .runFutureExit();

    final error =
        (exit as Failed<List<GenerationEvent>, AiError>).cause.expectedErrors.single
            as ProviderError;
    expect((error.partialOutput! as AssistantMessage).text, 'partial');
  });

  test('malformed streamed JSON fails with a protocol error and no final event', () async {
    final client = ProviderHttpClient(
      baseUrl: Uri.parse('https://example.test/'),
      client: _FixtureClient(utf8.encode('data: {\n\n')),
    );
    addTearDown(client.close);

    final exit = await client
        .sendSse<GenerationEvent>(
          ProviderHttpRequest(method: 'POST', path: 'generate'),
          createProtocol: () => _FixtureGenerationProtocol(_Dialect.openAi),
        )
        .runCollect()
        .runFutureExit();

    expect(
      (exit as Failed<List<GenerationEvent>, AiError>).cause.expectedErrors,
      contains(isA<ProtocolError>()),
    );
  });
}

enum _Dialect { openAi, anthropic, google }

final class _FixtureGenerationProtocol implements SseProtocol<GenerationEvent> {
  _FixtureGenerationProtocol(this.dialect)
    : assembler = GenerationStreamAssembler(
        providerId: dialect.name,
        api: dialect == _Dialect.google ? 'generateContent' : 'messages',
        modelId: 'model-1',
      );

  final _Dialect dialect;
  final GenerationStreamAssembler assembler;
  final Map<int, StringBuffer> _text = {};
  final List<ReplayItem> _replay = [];
  late final ResponseMetadata _metadata;
  var _started = false;
  var _terminal = false;
  var _candidateFinished = false;

  @override
  bool get isTerminal => _terminal && dialect != _Dialect.google;

  @override
  Object? get partialOutput => assembler.partialMessage;

  @override
  Iterable<GenerationEvent> start(ResponseMetadata metadata) {
    _metadata = metadata;
    return const [];
  }

  @override
  Iterable<GenerationEvent> decode(SseEvent event) {
    if (event.data == '[DONE]') {
      _terminal = true;
      return const [];
    }
    final json = JsonObject.parse(event.data);
    final value = json.toDart();
    return switch (value['type']) {
      'start' => _start(value),
      'part_start' => _startPart(value),
      'delta' => _delta(value),
      'part_finish' => _finishPart(value),
      'usage' => [
        assembler.updateUsage(
          Usage(
            inputTokens: value['input']! as int,
            outputTokens: value['output']! as int,
            totalTokens: value['total']! as int,
          ),
        ),
      ],
      'future.record' => _unknown(json),
      'error' => throw ProviderError(
        value['message']! as String,
        code: value['code']! as String,
        details: json,
        partialOutput: assembler.partialMessage,
      ),
      'finish' => _finishRecord(value),
      _ => [assembler.providerEvent(value['type']! as String, json)],
    };
  }

  Iterable<GenerationEvent> _start(Map<String, Object?> value) {
    _started = true;
    return [assembler.start(_metadata, responseId: value['id']! as String)];
  }

  Iterable<GenerationEvent> _startPart(Map<String, Object?> value) {
    final index = value['index']! as int;
    _text[index] = StringBuffer();
    return [assembler.startPart(index: index, kind: GenerationPartKind.text)];
  }

  Iterable<GenerationEvent> _delta(Map<String, Object?> value) {
    final index = value['index']! as int;
    final text = value['text']! as String;
    _text[index]!.write(text);
    return [assembler.appendText(index, text)];
  }

  Iterable<GenerationEvent> _finishPart(Map<String, Object?> value) {
    final index = value['index']! as int;
    return [
      assembler.finishPart(
        index,
        TextOutputPart(
          _text[index].toString(),
          citations: [Citation(uri: Uri.parse(value['citation']! as String))],
        ),
      ),
    ];
  }

  Iterable<GenerationEvent> _unknown(JsonObject data) {
    _replay.add(ReplayItem(phase: 'unknown-event', data: data));
    return [assembler.providerEvent('future.record', data)];
  }

  Iterable<GenerationEvent> _finishRecord(Map<String, Object?> value) {
    _candidateFinished = true;
    if (dialect == _Dialect.anthropic) _terminal = true;
    return const [];
  }

  @override
  Iterable<GenerationEvent> finish() {
    final recognized = switch (dialect) {
      _Dialect.openAi => _terminal,
      _Dialect.anthropic => _terminal,
      _Dialect.google => _candidateFinished,
    };
    if (!_started || !recognized) {
      throw ProtocolError(
        'The stream ended before recognized terminal semantics.',
        partialOutput: assembler.partialMessage,
      );
    }
    return [
      assembler.finish(
        finishReason: FinishReason.stop,
        nativeFinishReason: 'stop',
        nativeResponse: JsonObject({
          'id': 'response-1',
          'text': 'Hello world',
          'finish': 'stop',
        }),
        replay: _replay,
      ),
    ];
  }
}

GenerationResult _nonstreamResult(_Dialect dialect) => GenerationResult(
  message: AssistantMessage(
    [
      TextOutputPart(
        'Hello world',
        citations: [Citation(uri: Uri.parse('https://example.test/source'))],
      ),
    ],
    replay: ProviderReplay(
      providerId: dialect.name,
      api: dialect == _Dialect.google ? 'generateContent' : 'messages',
      modelId: 'model-1',
      items: [
        ReplayItem(
          phase: 'unknown-event',
          data: JsonObject({'type': 'future.record', 'value': 7}),
        ),
      ],
    ),
  ),
  finishReason: FinishReason.stop,
  nativeFinishReason: 'stop',
  usage: const Usage(inputTokens: 2, outputTokens: 3, totalTokens: 5),
  responseId: 'response-1',
  requestId: 'request-1',
  nativePayload: NativePayload(
    providerId: dialect.name,
    api: dialect == _Dialect.google ? 'generateContent' : 'messages',
    modelId: 'model-1',
    json: JsonObject({'id': 'response-1', 'text': 'Hello world', 'finish': 'stop'}),
  ),
  metadata: ResponseMetadata(
    statusCode: 200,
    requestId: 'request-1',
    headers: {'x-request-id': 'request-1'},
  ),
);

List<int> _fixtureBody(_Dialect dialect) {
  final records = <Object>[
    {'type': 'start', 'id': 'response-1'},
    {'type': 'part_start', 'index': 0, 'kind': 'text'},
    {'type': 'delta', 'index': 0, 'text': 'Hello '},
    {'type': 'usage', 'input': 2, 'output': 1, 'total': 3},
    {'type': 'delta', 'index': 0, 'text': 'world'},
    {
      'type': 'part_finish',
      'index': 0,
      'citation': 'https://example.test/source',
    },
    {'type': 'future.record', 'value': 7},
    {'type': 'usage', 'input': 2, 'output': 3, 'total': 5},
    {'type': 'finish', 'reason': 'stop'},
  ];
  final body = _sse(records);
  return dialect == _Dialect.openAi ? [...body, ...utf8.encode('data: [DONE]\n\n')] : body;
}

List<int> _sse(Iterable<Object> records) => utf8.encode(
  records.map((record) => 'data: ${jsonEncode(record)}\n\n').join(),
);

final class _FixtureClient extends http.BaseClient {
  _FixtureClient(this.body);

  final List<int> body;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async => http.StreamedResponse(
    Stream.value(body),
    200,
    headers: {'x-request-id': 'request-1'},
  );
}
