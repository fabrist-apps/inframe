import 'package:chronicler/chronicler.dart';
import 'package:chrono_id/chrono_id.dart';

RecordEnvelope testEnvelope({DateTime? timestamp}) => RecordEnvelope(
  eventId: ChronoID.generate(prefix: 'evt'),
  appId: 'app',
  release: 'release',
  source: ChroniclerSource.server,
  timestamp: timestamp ?? DateTime.now().toUtc(),
);

LogRecord testLogRecord(String message) => LogRecord(
  envelope: testEnvelope(),
  payload: LogPayload(severity: LogSeverity.info, message: message),
);

MetricRecord testMetricRecord() {
  final now = DateTime.now().toUtc();
  return MetricRecord(
    envelope: testEnvelope(timestamp: now),
    payload: MetricPayload(
      name: 'count',
      instrument: MetricInstrument.counter,
      unit: '1',
      intervalStart: now,
      intervalEnd: now,
      durationMicros: 0,
      observationCount: 1,
      temporality: MetricTemporality.delta,
      sum: 1,
    ),
  );
}
