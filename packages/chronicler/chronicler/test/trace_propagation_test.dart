import 'package:chronicler/chronicler.dart';
import 'package:test/test.dart';

const traceId = '0af7651916cd43dd8448eb211c80319c';
const parentId = 'b7ad6b7169203331';

void main() {
  group('TracePropagation parsing', () {
    test('should extract valid version zero and ordered tracestate', () {
      final parent = TracePropagation.extract({
        'TraceParent': '00-$traceId-$parentId-01',
        'TraceState': 'rojo=00f067aa0ba902b7,congo=t61rcWkgMzE',
      });

      expect(parent, isNotNull);
      expect(parent!.traceId, traceId);
      expect(parent.parentSpanId, parentId);
      expect(parent.sampled, isTrue);
      expect(parent.tracestate, ['rojo=00f067aa0ba902b7', 'congo=t61rcWkgMzE']);
    });

    test('should reject malformed parents and retain parents with invalid state', () {
      final invalid = [
        '00-$traceId-$parentId-01-extra',
        'ff-$traceId-$parentId-01',
        '00-${'0' * 32}-$parentId-01',
        '00-$traceId-${'0' * 16}-01',
        '00-${traceId.toUpperCase()}-$parentId-01',
        '00-$traceId-$parentId-01,00-$traceId-$parentId-01',
      ];
      for (final value in invalid) {
        expect(TracePropagation.extract({'traceparent': value}), isNull, reason: value);
      }

      final parent = TracePropagation.extract({
        'traceparent': '01-$traceId-$parentId-03-vendor',
        'tracestate': 'duplicate=one,duplicate=two',
      });
      expect(parent, isNotNull);
      expect(parent!.sampled, isTrue);
      expect(parent.tracestate, isEmpty);
      expect(
        TracePropagation.extract({
          'traceparent': '01-$traceId-$parentId-01-opaque--extension',
        })?.traceId,
        traceId,
      );
      expect(
        TracePropagation.extract({
          'TraceParent': '00-$traceId-$parentId-01',
          'traceparent': '00-$traceId-$parentId-01',
        }),
        isNull,
      );
      const future = '01-$traceId-$parentId-01-vendor';
      expect(TracePropagation.extract({'traceparent': '$future,$future'}), isNull);
    });

    test('should ignore empty tracestate list members', () {
      final parent = TracePropagation.extract({
        'traceparent': '00-$traceId-$parentId-01',
        'tracestate': 'rojo=abc, ,congo=xyz',
      });

      expect(parent!.tracestate, ['rojo=abc', 'congo=xyz']);
    });

    test('should remove oversized state entries before trimming from the end', () {
      final parent = TracePropagation.extract({
        'traceparent': '00-$traceId-$parentId-01',
        'tracestate': [
          'large=${'x' * 200}',
          for (var index = 0; index < 15; index++) 'v$index=${'y' * 20}',
        ].join(','),
      });

      expect(parent, isNotNull);
      expect(parent!.tracestate, isNot(contains(startsWith('large='))));
      expect(parent.tracestate, contains('v14=${'y' * 20}'));
    });
  });
}
