import 'package:artificer_core/artificer_core.dart';
import 'package:conflux/result.dart';
import 'package:test/test.dart';

void main() {
  group('EmbeddingBatch', () {
    test('should restore vector indices without modifying magnitudes', () {
      const batch = EmbeddingBatch(
        model: 'actual',
        data: [
          IndexedEmbedding(index: 1, embedding: [3, 4]),
          IndexedEmbedding(index: 0, embedding: [0, 2]),
        ],
      );
      final request = EmbeddingRequest(
        items: [const EmbeddingInput.text('a'), const EmbeddingInput.text('b')],
      );
      const native = NativePayload(
        providerId: 'fixture',
        api: 'embeddings',
        modelId: 'alias',
        data: {},
      );
      final result = batch.normalize(request, native) as Success<EmbeddingResult, AiError>;
      expect(result.value.vectors, [
        [0, 2],
        [3, 4],
      ]);
      expect(result.value.modelId, 'actual');
    });
  });
}
