import 'dart:convert';
import 'dart:io';

import 'package:artificer_core/artificer_core.dart';
import 'package:artificer_core/protocols.dart';
import 'package:artificer_core/transport.dart';
import 'package:conflux/effect.dart';
import 'package:conflux/flow.dart';
import 'package:conflux/result.dart';
import 'package:test/test.dart';

void main() {
  group('Generation transport', () {
    test(
      'should produce the same text result for fresh stream runs and reject premature EOF',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final runtime = Runtime();
        final client = ProviderHttpClient();
        addTearDown(() async {
          await client.close();
          await runtime.close();
          await server.close(force: true);
        });
        var requests = 0;
        server.listen((request) async {
          requests++;
          request.response.headers.contentType = ContentType('text', 'event-stream');
          request.response.write('data: {"text":"hel"}\n\ndata: {"text":"lo"}\n\n');
          if (request.uri.path != '/truncated') request.response.write('event: done\ndata: {}\n\n');
          await request.response.close();
        });
        Flow<GenerationEvent, AiError> run(String path) => Flow.defer((_) {
          final assembler = GenerationAssembler();
          var terminal = false;
          final transport = client.withSse<GenerationEvent>(
            url: Uri.parse('http://127.0.0.1:${server.port}$path'),
            consume: (metadata, events) {
              final starts =
                  Flow.fromIterable<GenerationEvent>([
                        const GenerationStarted(),
                        const PartStarted(id: 'text', index: 0, kind: GenerationPartKind.text),
                      ])
                      .widenError<AiError>()
                      .mapEffect((event, _) => Effect.fromResult(assembler.add(event)));
              return starts.concat(
                events.mapEffect((frame, _) {
                  if (frame.event == 'done') {
                    terminal = true;
                    final part = assembler.assembledPart('text');
                    return Effect.fromResult(
                      part.flatMap((value) => assembler.add(PartFinished(id: 'text', part: value))),
                    );
                  }
                  final data = jsonDecode(frame.data) as Map<String, Object?>;
                  return Effect.fromResult(
                    assembler.add(
                      PartDelta(
                        id: 'text',
                        delta: TextDelta(text: data['text']! as String),
                      ),
                    ),
                  );
                }),
              );
            },
          );
          return transport.concat(
            Effect.defer<GenerationEvent, AiError>(
              (_) => Effect.fromResult(
                assembler.complete(
                  terminal: terminal,
                  native: const NativePayload(
                    providerId: 'fixture',
                    api: 'stream',
                    modelId: 'model',
                    data: {'reply': 'hello'},
                  ),
                  finishReason: FinishReason.stop,
                ),
              ),
            ).asFlow(),
          );
        });
        final stream = run('/complete');
        expect(requests, 0);
        for (var attempt = 0; attempt < 2; attempt++) {
          final exit = await runtime.run(stream.runCollect());
          final events = (exit as Succeeded<List<GenerationEvent>, AiError>).value;
          expect(events.whereType<GenerationFinished>().single.result.text, 'hello');
          expect(events.whereType<PartDelta>().map((e) => (e.delta as TextDelta).text), [
            'hel',
            'lo',
          ]);
        }
        final received = <GenerationEvent>[];
        final exit = await runtime.run(
          run('/truncated').runForEach(
            (event, _) => Effect.sync((_) {
              received.add(event);
            }),
          ),
        );
        expect(exit, isA<Failed<void, AiError>>());
        expect(received.whereType<GenerationFinished>(), isEmpty);
        expect(requests, 3);
      },
    );
  });
}
