import 'dart:typed_data';

import 'package:artificer_core/artificer_core.dart';
import 'package:artificer_core/json.dart';
import 'package:test/test.dart';

void main() {
  group('EmbeddingRequest', () {
    test('should keep multimodal parts within one item and items as a batch', () {
      final bytes = Uint8List.fromList([1, 2]);
      final request = EmbeddingRequest(
        items: [
          EmbeddingInput([
            TextInputPart('caption'),
            MediaInputPart(
              kind: MediaKind.image,
              mimeType: 'image/png',
              source: BytesMediaSource(bytes),
            ),
          ]),
          EmbeddingInput.text('separate'),
        ],
        dimensions: 3,
      );
      bytes[0] = 9;

      expect(request.items, hasLength(2));
      expect(request.items.first.parts, hasLength(2));
      final media = request.items.first.parts[1] as MediaInputPart;
      expect((media.source as BytesMediaSource).bytes, [1, 2]);
      expect(request.dimensions, 3);
    });

    test('should reject empty inputs and invalid dimensions', () {
      expect(() => EmbeddingInput(const []), throwsArgumentError);
      expect(() => EmbeddingRequest(items: const []), throwsArgumentError);
      expect(
        () => EmbeddingRequest(items: [EmbeddingInput.text('x')], dimensions: 0),
        throwsArgumentError,
      );
    });
  });

  group('EmbeddingResult', () {
    test('should restore provider index order and preserve native data', () {
      final result = EmbeddingResult.fromIndexed(
        embeddings: [
          IndexedEmbedding(index: 1, vector: [4, 5, 6]),
          IndexedEmbedding(index: 0, vector: [1, 2, 3]),
        ],
        inputCount: 2,
        requestedDimensions: 3,
        modelId: 'actual-model',
        usage: const Usage(inputTokens: 4),
        nativePayload: NativePayload(
          providerId: 'fixture',
          api: 'embeddings',
          modelId: 'actual-model',
          json: JsonObject({'data': 'native'}),
        ),
        metadata: ResponseMetadata(statusCode: 200),
      );

      expect(result.vectors, [
        [1, 2, 3],
        [4, 5, 6],
      ]);
      expect(result.modelId, 'actual-model');
      expect(result.usage?.inputTokens, 4);
      expect(result.nativePayload.json.toDart()['data'], 'native');

      final decoded = EmbeddingResult.fromJson(result.toJson());
      expect(decoded.vectors, result.vectors);
    });

    test('should reject missing, duplicate, inconsistent, and nonfinite vectors', () {
      expect(
        () => _result([
          IndexedEmbedding(index: 0, vector: [1, 2]),
        ], inputCount: 2),
        throwsFormatException,
      );
      expect(
        () => _result([
          IndexedEmbedding(index: 0, vector: [1, 2]),
          IndexedEmbedding(index: 0, vector: [3, 4]),
        ], inputCount: 2),
        throwsFormatException,
      );
      expect(
        () => _result([
          IndexedEmbedding(index: 0, vector: [1, 2]),
          IndexedEmbedding(index: 1, vector: [3]),
        ], inputCount: 2),
        throwsFormatException,
      );
      expect(
        () => _result([
          IndexedEmbedding(index: 0, vector: [double.nan]),
        ]),
        throwsFormatException,
      );
      expect(
        () => _result([
          IndexedEmbedding(index: 0, vector: [1, 2]),
        ], dimensions: 3),
        throwsFormatException,
      );
    });
  });
}

EmbeddingResult _result(
  List<IndexedEmbedding> embeddings, {
  int inputCount = 1,
  int? dimensions,
}) => EmbeddingResult.fromIndexed(
  embeddings: embeddings,
  inputCount: inputCount,
  requestedDimensions: dimensions,
  modelId: 'model',
  nativePayload: NativePayload(
    providerId: 'fixture',
    api: 'embeddings',
    modelId: 'model',
    json: JsonObject({}),
  ),
  metadata: ResponseMetadata(statusCode: 200),
);
