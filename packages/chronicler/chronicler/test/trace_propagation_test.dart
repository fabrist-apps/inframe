import 'package:chronicler/chronicler.dart';
import 'package:test/test.dart';

const traceId = 'trc_0123456789ABCDEFGHIJKLMN';
const parentId = 'spn_0123456789ABCDEFGHIJKLMN';

void main() {
  group('TracePropagation', () {
    const headers = {
      'chronicler-trace-id': traceId,
      'chronicler-span-id': parentId,
      'chronicler-sampled': '1',
    };

    test('should extract Chrono IDs from case-insensitive headers', () {
      final parent = TracePropagation.extract({
        'Chronicler-Trace-Id': traceId,
        'Chronicler-Span-Id': parentId,
        'Chronicler-Sampled': '1',
      });

      expect(parent, isNotNull);
      expect(parent!.traceId, traceId);
      expect(parent.parentSpanId, parentId);
      expect(parent.sampled, isTrue);
      expect(TracePropagation.extract({...headers, 'chronicler-sampled': '0'})!.sampled, isFalse);
    });

    test('should reject incomplete, ambiguous, or invalid correlation', () {
      for (final key in headers.keys) {
        expect(TracePropagation.extract({...headers}..remove(key)), isNull);
        expect(TracePropagation.extract({...headers, key.toUpperCase(): headers[key]!}), isNull);
        expect(
          TracePropagation.extract({...headers, key: '${headers[key]},${headers[key]}'}),
          isNull,
        );
      }
      expect(TracePropagation.extract({...headers, 'chronicler-trace-id': parentId}), isNull);
      expect(TracePropagation.extract({...headers, 'chronicler-span-id': traceId}), isNull);
      expect(TracePropagation.extract({...headers, 'chronicler-sampled': 'yes'}), isNull);
    });
  });
}
