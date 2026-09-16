import 'dart:convert';
import 'dart:typed_data';

import 'package:chronicler/chronicler.dart';
import 'package:chrono_id/chrono_id.dart';
import 'package:conflux/moment.dart';
import 'package:conflux/result.dart';
import 'package:test/test.dart';

import 'support/moments.dart';

void main() {
  setUpAll(Chronicler.initialize);
  group('ChroniclerCodec version one', () {
    test('should round-trip every record variant and metric form', () {
      final records = _records();
      const codec = ChroniclerCodec();

      final decoded = codec.decodeBatch(codec.encodeBatch(ChroniclerBatch(records)));

      expect(decoded, isA<Decoded<ChroniclerBatch>>());
      final roundTrip = (decoded as Decoded<ChroniclerBatch>).value.records;
      expect(roundTrip, hasLength(records.length));
      expect(roundTrip.map((record) => record.runtimeType), [
        LogRecord,
        ProductEventRecord,
        IdentityLinkRecord,
        UserPropertiesSetRecord,
        UserPropertiesUnsetRecord,
        SpanRecord,
        ErrorRecord,
        MetricRecord,
        MetricRecord,
        MetricRecord,
        MetricRecord,
      ]);
      expect(roundTrip.whereType<MetricRecord>(), hasLength(4));
    });

    test('should tolerate additive optional fields on version one', () {
      const codec = ChroniclerCodec();
      final encoded = codec.encodeRecord(_records().first);
      final map = jsonDecode(utf8.decode(encoded)) as Map<String, Object?>;
      map['futureOptional'] = {'nested': true};
      (map['payload']! as Map<String, Object?>)['futureOptional'] = 1;

      final result = codec.decodeRecord(Uint8List.fromList(utf8.encode(jsonEncode(map))));

      expect(result, isA<Decoded<ChroniclerRecord>>());
    });

    test('should return each payload-free decoding failure category', () {
      const codec = ChroniclerCodec();
      final validMap = jsonDecode(
        utf8.decode(codec.encodeRecord(_records().first)),
      ) as Map<String, Object?>;

      expect(
        codec.decodeRecord(Uint8List.fromList([0xff])),
        isA<DecodeFailure<ChroniclerRecord>>().having(
          (failure) => failure.reason,
          'reason',
          DecodeFailureReason.invalidUtf8,
        ),
      );
      expect(
        codec.decodeRecord(Uint8List.fromList(utf8.encode('{'))),
        _failure(DecodeFailureReason.invalidJson),
      );
      expect(
        codec.decodeRecord(_mutate(validMap, 'schemaVersion', 2)),
        _failure(DecodeFailureReason.unsupportedVersion),
      );
      expect(
        codec.decodeRecord(_mutate(validMap, 'kind', 'future_kind')),
        _failure(DecodeFailureReason.invalidField),
      );
      expect(
        codec.decodeRecord(_mutate(validMap, 'payload', const {})),
        _failure(DecodeFailureReason.invalidField),
      );
      expect(
        const ChroniclerCodec(maxRecordBytes: 4).decodeRecord(
          codec.encodeRecord(_records().first),
        ),
        _failure(DecodeFailureReason.limitExceeded),
      );
    });

    test('should reject the complete batch when one member is malformed', () {
      const codec = ChroniclerCodec();
      final batch = jsonDecode(
        utf8.decode(codec.encodeBatch(ChroniclerBatch(_records().take(2)))),
      ) as Map<String, Object?>;
      final members = batch['records']! as List<Object?>;
      (members.last! as Map<String, Object?>).remove('payload');

      final result = codec.decodeBatch(
        Uint8List.fromList(utf8.encode(jsonEncode(batch))),
      );

      expect(result, isA<DecodeFailure<ChroniclerBatch>>());
    });

    test('should reject an empty decoded batch', () {
      const codec = ChroniclerCodec();
      final encoded = Uint8List.fromList(
        utf8.encode('{"records":[],"schemaVersion":1}'),
      );

      expect(
        codec.decodeBatch(encoded),
        isA<DecodeFailure<ChroniclerBatch>>().having(
          (failure) => failure.reason,
          'reason',
          DecodeFailureReason.invalidField,
        ),
      );
    });

    test('should reject invalid explicitly constructed models', () {
      const codec = ChroniclerCodec();
      final valid = _records().first as LogRecord;
      final invalid = LogRecord(
        envelope: valid.envelope.copyWith(eventId: 'not-an-event-id'),
        payload: valid.payload,
      );

      expect(() => codec.encodeRecord(invalid), throwsA(isA<ChroniclerEncodingException>()));
    });

    test('should apply record byte limits while encoding', () {
      final records = _records();
      final unset = records.whereType<UserPropertiesUnsetRecord>().single;
      final oversizedKeys = List.generate(100, (index) => '$index${'x' * 1024}');
      expect(
        () => const ChroniclerCodec().encodeRecord(
          unset.copyWith(payload: unset.payload.copyWith(keys: oversizedKeys)),
        ),
        throwsA(isA<ChroniclerEncodingException>()),
      );
      final unsetMap = jsonDecode(
        utf8.decode(const ChroniclerCodec().encodeRecord(unset)),
      ) as Map<String, Object?>;
      (unsetMap['payload']! as Map<String, Object?>)['keys'] = oversizedKeys;
      expect(
        const ChroniclerCodec().decodeRecord(
          Uint8List.fromList(utf8.encode(jsonEncode(unsetMap))),
        ),
        _failure(DecodeFailureReason.limitExceeded),
      );
    });

    test('should deeply snapshot model collections', () {
      final nested = <String, Object?>{
        'items': <Object?>[
          {'value': 1},
        ],
      };
      final payload = ProductEventPayload(name: 'event', properties: nested);
      (nested['items']! as List<Object?>).clear();

      expect(payload.properties['items'], hasLength(1));
      expect(
        () => (payload.properties['items']! as List<Object?>).clear(),
        throwsUnsupportedError,
      );
    });
  });
}

Matcher _failure(DecodeFailureReason reason) => isA<DecodeFailure<ChroniclerRecord>>().having(
  (failure) => failure.reason,
  'reason',
  reason,
);

Uint8List _mutate(Map<String, Object?> source, String key, Object? value) {
  final copy = jsonDecode(jsonEncode(source)) as Map<String, Object?>;
  copy[key] = value;
  return Uint8List.fromList(utf8.encode(jsonEncode(copy)));
}

List<ChroniclerRecord> _records() {
  final now = utcMoment(2026, 9, 12, 10, 20, 30, 123, 456);
  RecordEnvelope envelope({
    String? traceId,
    String? spanId,
    String? parentSpanId,
    Moment? timestamp,
  }) => RecordEnvelope(
    eventId: ChronoID.generate(prefix: 'evt'),
    appId: 'app-external',
    release: '1.0.0',
    source: ChroniclerSource.server,
    timestamp: timestamp ?? now,
    buildId: 'build-1',
    userId: traceId == null ? 'external-user' : null,
    anonymousId: traceId == null ? 'external-anonymous' : null,
    sessionId: traceId == null ? 'external-session' : null,
    traceId: traceId,
    spanId: spanId,
    parentSpanId: parentSpanId,
  );

  final metricEnvelope = RecordEnvelope(
    eventId: ChronoID.generate(prefix: 'evt'),
    appId: 'app-external',
    release: '1.0.0',
    source: ChroniclerSource.server,
    timestamp: now,
  );
  MetricRecord metric(MetricPayload payload) => MetricRecord(
    envelope: metricEnvelope.copyWith(eventId: ChronoID.generate(prefix: 'evt')),
    payload: payload,
  );
  MetricPayload metricPayload({
    required MetricInstrument instrument,
    MetricTemporality? temporality,
    double? sum,
    List<double>? boundaries,
    List<int>? bucketCounts,
    int? count,
    double? min,
    double? max,
    double? value,
    Moment? observedAt,
  }) => MetricPayload(
    name: 'request.duration',
    instrument: instrument,
    unit: 'ms',
    attributes: const {'region': 'ap-south-1'},
    intervalStart: now
        .subtractDuration(const Duration(seconds: 10))
        .getOrThrowWith((error) => StateError('$error')),
    intervalEnd: now,
    durationMicros: 10000000,
    observationCount: count ?? 1,
    temporality: temporality,
    sum: sum,
    boundaries: boundaries,
    bucketCounts: bucketCounts,
    count: count,
    min: min,
    max: max,
    value: value,
    observedAt: observedAt,
  );

  return [
    LogRecord(
      envelope: envelope(),
      payload: LogPayload(
        severity: LogSeverity.error,
        message: 'failed',
        attributes: const {'attempt': 1},
        error: const ErrorDetails(type: 'StateError', message: 'failed', stackTrace: 'stack'),
      ),
    ),
    ProductEventRecord(
      envelope: envelope(),
      payload: ProductEventPayload(name: 'purchase', properties: const {'amount': 10}),
    ),
    IdentityLinkRecord(
      envelope: envelope(),
      payload: const IdentityLinkPayload(
        anonymousId: 'external-anonymous',
        userId: 'external-user',
      ),
    ),
    UserPropertiesSetRecord(
      envelope: envelope(),
      payload: UserPropertiesSetPayload(
        userId: 'external-user',
        properties: const {'plan': 'pro'},
      ),
    ),
    UserPropertiesUnsetRecord(
      envelope: envelope(),
      payload: UserPropertiesUnsetPayload(userId: 'external-user', keys: const ['plan']),
    ),
    SpanRecord(
      envelope: envelope(
        traceId: 'trc_0123456789ABCDEFGHIJKLMN',
        spanId: 'spn_0123456789ABCDEFGHIJKLMN',
        parentSpanId: 'spn_ABCDEFGHIJKLMNOPQRSTUVWX',
      ),
      payload: SpanPayload(
        name: 'request',
        spanKind: SpanKind.server,
        status: SpanStatus.success,
        durationMicros: 1200,
      ),
    ),
    ErrorRecord(
      envelope: envelope(),
      payload: ErrorPayload(
        error: const ErrorDetails(type: 'StateError', message: 'failed'),
        handled: true,
        causes: const [ErrorDetails(type: 'Exception', message: 'cause')],
      ),
    ),
    metric(
      metricPayload(
        instrument: MetricInstrument.counter,
        temporality: MetricTemporality.delta,
        sum: 3,
      ),
    ),
    metric(
      metricPayload(
        instrument: MetricInstrument.upDownCounter,
        temporality: MetricTemporality.delta,
        sum: -1,
      ),
    ),
    metric(
      metricPayload(
        instrument: MetricInstrument.histogram,
        temporality: MetricTemporality.delta,
        sum: 12,
        boundaries: const [10, 50],
        bucketCounts: const [0, 1, 0],
        count: 1,
        min: 12,
        max: 12,
      ),
    ),
    metric(
      metricPayload(
        instrument: MetricInstrument.gauge,
        value: 42,
        observedAt: now,
      ),
    ),
  ];
}
