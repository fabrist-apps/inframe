import 'package:chronicler/chronicler.dart';
import 'package:chrono_id/chrono_id.dart';
import 'package:conflux/moment.dart';
import 'package:conflux/result.dart';

RecordEnvelope testEnvelope({Moment? timestamp}) => RecordEnvelope(
  eventId: ChronoID.generate(prefix: 'evt'),
  appId: 'app',
  release: 'release',
  source: ChroniclerSource.server,
  timestamp:
      timestamp ??
      Moment.fromDateTime(DateTime.now()).getOrThrowWith((error) => StateError('$error')),
);

LogRecord testLogRecord(String message) => LogRecord(
  envelope: testEnvelope(),
  payload: LogPayload(severity: LogSeverity.info, message: message),
);

MetricRecord testMetricRecord() {
  final now = Moment.fromDateTime(DateTime.now()).getOrThrowWith((error) => StateError('$error'));
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
