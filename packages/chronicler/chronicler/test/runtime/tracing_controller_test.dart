import 'package:chronicler/chronicler.dart';
import 'package:test/test.dart';

import '../support/trace_controller.dart';

void main() {
  setUpAll(Chronicler.initialize);
  group('TraceController', () {
    test('should retain correlation when reading the start clock fails', () {
      final bed = TraceControllerTestBed(
        now: () => throw StateError('clock unavailable'),
      );

      final span = bed.start('clock failure');

      expect(span, isNotNull);
      expect(bed.controller.inject(span, const {}), {
        TracePropagation.traceIdHeader: span!.traceId,
        TracePropagation.spanIdHeader: span.spanId,
        TracePropagation.sampledHeader: '1',
      });
      bed.controller.finish(span, SpanStatus.success);
      expect(bed.records, isEmpty);
      expect(bed.diagnostics.counts[DiagnosticReason.invalidRecord], BigInt.one);
    });

    test('should end a span exactly once even when its finish clock throws', () {
      var elapsedCalls = 0;
      final failure = StateError('clock unavailable');
      final bed = TraceControllerTestBed(
        elapsed: () {
          if (++elapsedCalls == 2) throw failure;
          return Duration.zero;
        },
      );
      final span = bed.start('finish failure');

      expect(() => bed.controller.finish(span, SpanStatus.success), throwsA(same(failure)));
      bed.controller.finish(span, SpanStatus.error);

      expect(elapsedCalls, 2);
      expect(bed.records, isEmpty);
      expect(bed.controller.inject(span, const {}), isEmpty);
    });
  });
}
