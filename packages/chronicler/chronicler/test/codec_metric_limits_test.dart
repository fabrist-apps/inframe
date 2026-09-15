import 'package:chronicler/chronicler.dart';
import 'package:test/test.dart';

import 'support/records.dart';

void main() {
  group('ChroniclerCodec metric limits', () {
    for (final instrument in MetricInstrument.values) {
      test('should accept the large count for ${instrument.name}', () {
        const maximum = 9007199254740992;
        final envelope = testEnvelope();
        final histogram = instrument == MetricInstrument.histogram;
        final gauge = instrument == MetricInstrument.gauge;
        final record = MetricRecord(
          envelope: envelope,
          payload: MetricPayload(
            name: 'observations',
            instrument: instrument,
            unit: '1',
            intervalStart: envelope.timestamp,
            intervalEnd: envelope.timestamp,
            durationMicros: 0,
            observationCount: maximum,
            temporality: gauge ? null : MetricTemporality.delta,
            sum: gauge ? null : 4,
            value: gauge ? 7 : null,
            observedAt: gauge ? envelope.timestamp : null,
            boundaries: histogram ? [10] : null,
            bucketCounts: histogram ? [maximum, 0] : null,
            count: histogram ? maximum : null,
            min: histogram ? 0 : null,
            max: histogram ? 4 : null,
          ),
        );
        const codec = ChroniclerCodec();
        expect(() => codec.encodeRecord(record), returnsNormally);
        expect(
          () => codec.encodeRecord(
            record.copyWith(payload: record.payload.copyWith(observationCount: -1)),
          ),
          throwsA(isA<ChroniclerEncodingException>()),
        );
      });
    }
  });
}
