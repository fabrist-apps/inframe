import 'dart:convert';
import 'dart:io';

import 'package:artificer_core/artificer_core.dart';
import 'package:artificer_core/protocols.dart';
import 'package:artificer_core/transport.dart';
import 'package:conflux/effect.dart';
import 'package:conflux/result.dart';
import 'package:test/test.dart';

void main() {
  group('CompatibleEmbeddingModel', () {
    test(
      'should normalize the same native attempt and reject preflight without splitting',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final runtime = Runtime();
        final client = ProviderHttpClient();
        addTearDown(() async {
          await client.close();
          await runtime.close();
          await server.close(force: true);
        });
        final bodies = <Map<String, Object?>>[];
        server.listen((request) async {
          bodies.add(jsonDecode(await utf8.decoder.bind(request).join()) as Map<String, Object?>);
          request.response.write(
            jsonEncode({
              'model': 'actual',
              'data': [
                {
                  'index': 1,
                  'embedding': [3, 4],
                },
                {
                  'index': 0,
                  'embedding': [1, 2],
                },
              ],
              'unknown': {'keep': true},
              'usage': {'prompt_tokens': 3},
            }),
          );
          await request.response.close();
        });
        final model = CompatibleEmbeddingModel(
          providerId: 'fixture',
          modelId: 'unfamiliar',
          client: client,
          endpoint: Uri.parse('http://127.0.0.1:${server.port}/'),
          maxBatchSize: 2,
          defaults: const EmbeddingOptions(user: Setting.set('default')),
        );
        final request = EmbeddingRequest(
          items: [const EmbeddingInput.text('a'), const EmbeddingInput.text('b')],
          dimensions: 2,
        );
        final operation = model.rawEmbed(
          request,
          options: const EmbeddingOptions(user: Setting.clear()),
        );
        expect(bodies, isEmpty);
        final response = (await runtime.run(
          operation,
        ) as Succeeded<NativeResponse<EmbeddingBatch>, AiError>).value;
        expect(response.value.model, 'actual');
        final normalized = response.value.normalize(
          request,
          response.raw,
          metadata: response.metadata,
        ) as Success<EmbeddingResult, AiError>;
        expect(normalized.value.vectors, [
          [1, 2],
          [3, 4],
        ]);
        expect(normalized.value.usage?.inputTokens, 3);
        expect(normalized.value.usage?.outputTokens, isNull);
        expect((normalized.value.native.data! as Map)['unknown'], {'keep': true});
        expect(bodies, [
          {
            'model': 'unfamiliar',
            'input': ['a', 'b'],
            'encoding_format': 'float',
            'dimensions': 2,
          },
        ]);
        final tooLarge = EmbeddingRequest(
          items: [...request.items, const EmbeddingInput.text('c')],
        );
        expect(await runtime.run(model.embed(tooLarge)), isA<Failed<EmbeddingResult, AiError>>());
        expect(
          await runtime.run(
            model.embed(
              request,
              options: const EmbeddingOptions(extraBody: Setting.set({'model': 'collision'})),
            ),
          ),
          isA<Failed<EmbeddingResult, AiError>>(),
        );
        expect(bodies.length, 1);
      },
    );
    test('should retain malformed result shapes as typed protocol failures', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final runtime = Runtime();
      final client = ProviderHttpClient();
      addTearDown(() async {
        await client.close();
        await runtime.close();
        await server.close(force: true);
      });
      server.listen((request) async {
        request.response.write('{"data":"malformed"}');
        await request.response.close();
      });
      final model = CompatibleEmbeddingModel(
        providerId: 'fixture',
        modelId: 'any',
        client: client,
        endpoint: Uri.parse('http://127.0.0.1:${server.port}/'),
      );
      final exit = await runtime.run(
        model.embed(EmbeddingRequest(items: [const EmbeddingInput.text('a')])),
      );
      expect(
        (exit as Failed<EmbeddingResult, AiError>).cause,
        isA<Expected<AiError>>().having((c) => c.error, 'error', isA<ProtocolError>()),
      );
    });
  });
  group('EmbeddingBatch', () {
    test('should reject missing duplicate invalid and mismatched vectors', () {
      final request = EmbeddingRequest(
        items: [const EmbeddingInput.text('a'), const EmbeddingInput.text('b')],
        dimensions: 2,
      );
      const native = NativePayload(
        providerId: 'fixture',
        api: 'embeddings',
        modelId: 'model',
        data: {},
      );
      for (final values in <List<IndexedEmbedding>>[
        [],
        [
          const IndexedEmbedding(index: 0, embedding: [1, 2]),
        ],
        [
          const IndexedEmbedding(index: 0, embedding: [1, 2]),
          const IndexedEmbedding(index: 0, embedding: [3, 4]),
        ],
        [
          const IndexedEmbedding(index: 0, embedding: [1, 2]),
          const IndexedEmbedding(index: 2, embedding: [3, 4]),
        ],
        [
          const IndexedEmbedding(index: 0, embedding: [1, 2]),
          const IndexedEmbedding(index: 1, embedding: []),
        ],
        [
          const IndexedEmbedding(index: 0, embedding: [1, 2]),
          const IndexedEmbedding(index: 1, embedding: [double.nan, 4]),
        ],
        [
          const IndexedEmbedding(index: 0, embedding: [1, 2]),
          const IndexedEmbedding(index: 1, embedding: [3]),
        ],
        [
          const IndexedEmbedding(index: 0, embedding: [1]),
          const IndexedEmbedding(index: 1, embedding: [3]),
        ],
      ]) {
        expect(
          EmbeddingBatch(model: 'model', data: values).normalize(request, native),
          isA<Failure<EmbeddingResult, AiError>>(),
        );
      }
    });
  });
}
