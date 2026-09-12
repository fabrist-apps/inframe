import 'package:artificer_core/artificer_core.dart';
import 'package:artificer_core/json.dart';
import 'package:artificer_core/transport.dart';
import 'package:artificer_google/artificer_google.dart';
import 'package:test/test.dart';

void main() {
  group('Google embedding models', () {
    test('should encode the pinned native request and retain unknown response fields', () {
      final request = GoogleEmbedContentRequest(
        model: 'models/gemini-embedding-001',
        content: GoogleContent(parts: [GooglePart.text('A diagram')]),
        config: GoogleEmbedContentConfig(
          taskType: GoogleEmbeddingTaskType.retrievalDocument,
          title: 'Deployment diagram',
          outputDimensionality: 768,
          autoTruncate: false,
        ),
        extraBody: JsonObject({'futureRequest': true}),
      );
      final response = GoogleEmbedContentResponse.fromJson(
        JsonObject({
          'embedding': {
            'values': [1, 2],
            'shape': [1, 2],
            'futureEmbedding': 'kept',
          },
          'usageMetadata': {
            'promptTokenCount': 4,
            'promptTokenDetails': [
              {'modality': 'TEXT', 'tokenCount': 4},
            ],
            'futureUsage': true,
          },
          'futureResponse': {'keep': true},
        }),
      );

      expect(request.toJson().toDart(), {
        'futureRequest': true,
        'content': {
          'parts': [
            {'text': 'A diagram'},
          ],
        },
        'embedContentConfig': {
          'taskType': 'RETRIEVAL_DOCUMENT',
          'title': 'Deployment diagram',
          'outputDimensionality': 768,
          'autoTruncate': false,
        },
      });
      expect(response.embedding.values, [1, 2]);
      expect(response.embedding.shape, [1, 2]);
      expect(response.embedding.extensions.toDart()['futureEmbedding'], 'kept');
      expect(response.usageMetadata!.promptTokenCount, 4);
      expect(response.usageMetadata!.promptTokenDetails.single.toDart(), {
        'modality': 'TEXT',
        'tokenCount': 4,
      });
      expect(response.extensions.toDart()['futureResponse'], {'keep': true});
    });

    test('should round-trip batch requests and unfamiliar config fields', () {
      final decoded = GoogleBatchEmbedContentsRequest.fromJson(
        model: 'models/future-model',
        json: JsonObject({
          'requests': [
            {
              'model': 'models/future-model',
              'content': {
                'parts': [
                  {'text': 'future'},
                ],
              },
              'embedContentConfig': {
                'taskType': 'FUTURE_TASK',
                'title': 'Future title',
                'futureConfig': 1,
              },
              'futureRequest': true,
            },
          ],
          'futureBatch': true,
        }),
      );

      expect(decoded.toJson().toDart(), {
        'futureBatch': true,
        'requests': [
          {
            'model': 'models/future-model',
            'futureRequest': true,
            'content': {
              'parts': [
                {'text': 'future'},
              ],
            },
            'embedContentConfig': {
              'taskType': 'FUTURE_TASK',
              'futureConfig': 1,
              'title': 'Future title',
            },
          },
        ],
      });
    });

    test('should validate native model names, task titles, dimensions, and batches', () {
      final content = GoogleContent(parts: [GooglePart.text('text')]);

      expect(
        () => GoogleEmbedContentRequest(model: 'gemini', content: content),
        throwsArgumentError,
      );
      expect(
        () => GoogleEmbedContentConfig(
          taskType: GoogleEmbeddingTaskType.retrievalQuery,
          title: 'Only documents have titles',
        ),
        throwsArgumentError,
      );
      expect(
        () => GoogleEmbedContentConfig(outputDimensionality: 0),
        throwsArgumentError,
      );
      final first = GoogleEmbedContentRequest(model: 'models/gemini', content: content);
      final second = GoogleEmbedContentRequest(model: 'models/other', content: content);
      expect(
        () => GoogleBatchEmbedContentsRequest(model: 'models/gemini', requests: [first, second]),
        throwsArgumentError,
      );
    });

    test('should merge and clear immutable embedding settings', () {
      final defaults = GoogleEmbeddingOptions(
        taskType: const Setting.set(GoogleEmbeddingTaskType.retrievalDocument),
        title: const Setting.set('Default title'),
        dimensions: const Setting.set(1536),
        extraBody: JsonObject({'one': 1, 'replace': 'model'}),
      );
      final call = GoogleEmbeddingOptions(
        taskType: const Setting.clear(),
        title: const Setting.clear(),
        dimensions: const Setting.set(768),
        extraBody: JsonObject({'two': 2, 'replace': 'call'}),
      );

      expect(defaults.resolveTaskType(call), isNull);
      expect(defaults.resolveTitle(call), isNull);
      expect(defaults.resolveDimensions(call), 768);
      expect(defaults.resolveExtraBody(call).toDart(), {
        'one': 1,
        'two': 2,
        'replace': 'call',
      });
    });

    test('should expose honest capabilities for known and unfamiliar models', () {
      final client = ProviderHttpClient(baseUrl: Uri.parse('http://127.0.0.1:1'));
      addTearDown(client.close);
      final resource = GoogleEmbeddingsResource(client);

      final multimodal = GoogleEmbeddingModel(
        resource,
        'gemini-embedding-2',
        GoogleEmbeddingOptions(),
      );
      final textOnly = GoogleEmbeddingModel(
        resource,
        'gemini-embedding-001',
        GoogleEmbeddingOptions(),
      );
      final unfamiliar = GoogleEmbeddingModel(
        resource,
        'future-embedding-model',
        GoogleEmbeddingOptions(),
      );
      final retired = [
        GoogleEmbeddingModel(resource, 'text-embedding-004', GoogleEmbeddingOptions()),
        GoogleEmbeddingModel(resource, 'embedding-001', GoogleEmbeddingOptions()),
      ];

      expect(multimodal.capabilities[EmbeddingCapability.image], CapabilitySupport.supported);
      expect(textOnly.capabilities[EmbeddingCapability.text], CapabilitySupport.supported);
      expect(textOnly.capabilities[EmbeddingCapability.image], CapabilitySupport.unsupported);
      expect(unfamiliar.capabilities[EmbeddingCapability.text], CapabilitySupport.unknown);
      expect(unfamiliar.capabilities[EmbeddingCapability.batching], CapabilitySupport.unknown);
      for (final model in retired) {
        expect(model.capabilities[EmbeddingCapability.text], CapabilitySupport.unknown);
        expect(model.capabilities[EmbeddingCapability.dimensions], CapabilitySupport.unknown);
      }
    });

    test('should expose the public factory for bare IDs without discovery', () {
      final provider = GoogleProvider(apiKey: 'secret');
      addTearDown(provider.close);

      expect(() => provider.embeddingModel(''), throwsArgumentError);
      expect(() => provider.embeddingModel('models/gemini-embedding-2'), throwsArgumentError);
      final EmbeddingModel model = provider.embeddingModel('future-embedding-model');

      expect(model.modelId, 'future-embedding-model');
      expect(model.capabilities[EmbeddingCapability.image], CapabilitySupport.unknown);
    });
  });
}
