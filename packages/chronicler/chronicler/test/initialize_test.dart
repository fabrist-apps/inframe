import 'package:chronicler/chronicler.dart';
import 'package:conflux/option.dart';
import 'package:dart_mappable/dart_mappable.dart';
import 'package:test/test.dart';

void main() {
  test('initialization enables container decoding and is repeatable', () {
    Chronicler.initialize();
    Chronicler.initialize();

    expect(
      MapperContainer.globals.fromValue<Option<int>>(42),
      isA<Some<int>>().having((option) => option.value, 'value', 42),
    );

    final record = MapperContainer.globals.fromMap<ChroniclerRecord>({
      'kind': 'log',
      'envelope': {
        'eventId': 'evt_000000000000000000000000',
        'appId': 'app',
        'release': '1',
        'source': 'server',
        'timestamp': '2026-09-12T10:20:30.123456Z',
      },
      'payload': {'severity': 'info', 'message': 'hello'},
    });
    expect(record, isA<LogRecord>());
    expect((record as LogRecord).payload.message, 'hello');
    expect(record.envelope.source, ChroniclerSource.server);
    expect(RecordEnvelope.fromJson(record.envelope.toJson()), record.envelope);
    expect(LogRecord.fromJson(record.toJson()), record);
    expect(
      MapperContainer.globals.fromValue<MetricInstrument>('counter'),
      MetricInstrument.counter,
    );
    expect(MapperContainer.globals.fromValue<SpanStatus>('success'), SpanStatus.success);
  });
}
