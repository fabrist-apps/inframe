import 'package:chronicler/chronicler.dart';
import 'package:context/context.dart';
import 'package:inlet/inlet.dart';
import 'package:inlet_request_id/inlet_request_id.dart';
import 'package:inlet_tracing/inlet_tracing.dart';
import 'package:test/test.dart';

void main() {
  setUpAll(Chronicler.initialize);

  group('httpTracing', () {
    late _Exporter exporter;
    late Chronicler chronicler;
    late Context context;

    setUp(() {
      exporter = _Exporter();
      chronicler = Chronicler(
        appId: 'app',
        release: 'test',
        source: ChroniclerSource.server,
        exporter: exporter,
      );
      context = Context().withChronicler(chronicler.recorder);
      addTearDown(chronicler.close);
    });

    test('should record method, route, status and generated request ID', () async {
      final app = Inlet(context: context)
        ..use(httpTracing)
        ..use(requestId)
        ..get('/items/:id', (context, _) => Response.text(context.requestId));
      final request = Request(method: 'GET', uri: Uri.parse('/items/private?secret=value'));
      addTearDown(request.close);
      final response = await app.handle(request);
      addTearDown(response.close);
      final id = response.headers['x-request-id'];

      expect(response.statusCode, 200);
      expect(id, isNotNull);
      expect(await response.text(), id);
      await chronicler.flush();
      final span = exporter.records.whereType<SpanRecord>().single;
      expect(span.payload.attributes, {
        'http.request.method': 'GET',
        'http.route': '/items/:id',
        'http.response.status_code': 200,
        'requestId': id,
      });
      expect(span.payload.name, 'GET /items/:id');
      expect(span.payload.spanKind, SpanKind.server);
      expect(span.payload.status, SpanStatus.success);
    });

    test('should continue the request without Chronicler', () async {
      final app = Inlet()
        ..use(httpTracing)
        ..use(requestId)
        ..get('/', (context, _) => Response.text(context.requestId));
      final request = Request(method: 'GET', uri: Uri.parse('/'));
      addTearDown(request.close);
      final response = await app.handle(request);
      addTearDown(response.close);

      expect(response.statusCode, 200);
      expect(response.headers['x-request-id'], startsWith('req_'));
      expect(await response.text(), response.headers['x-request-id']);
      await chronicler.flush();
      expect(exporter.records, isEmpty);
    });

    test('should allow request ID middleware to run without an active span', () async {
      final app = Inlet(context: context)
        ..use(requestId)
        ..get('/', (context, _) => Response.text(context.requestId));
      final request = Request(method: 'GET', uri: Uri.parse('/'));
      addTearDown(request.close);
      final response = await app.handle(request);
      addTearDown(response.close);

      expect(response.statusCode, 200);
      expect(response.headers['x-request-id'], startsWith('req_'));
      expect(await response.text(), response.headers['x-request-id']);
      expect(chronicler.diagnosticCounts[DiagnosticReason.noActiveSpan], BigInt.one);
      await chronicler.flush();
      expect(exporter.records, isEmpty);
    });

    test('should continue a valid remote parent and correlate handler logs', () async {
      final upstream = chronicler.recorder.startRootSpan('upstream');
      final headers = upstream.recorder.injectTrace({});
      final parent = TracePropagation.extract(headers)!;
      upstream.end(SpanStatus.success);
      final app = Inlet(context: context)
        ..use(httpTracing)
        ..get('/', (context, _) {
          context.logs.info('handled');
          return Response.empty();
        });
      final request = Request(
        method: 'GET',
        uri: Uri.parse('/'),
        headers: Headers.from(headers.map((key, value) => MapEntry(key, [value]))),
      );
      addTearDown(request.close);
      final response = await app.handle(request);
      addTearDown(response.close);
      await chronicler.flush();
      final span = exporter.records.whereType<SpanRecord>().singleWhere(
        (record) => record.payload.spanKind == SpanKind.server,
      );
      final log = exporter.records.whereType<LogRecord>().single;
      expect(span.envelope.traceId, parent.traceId);
      expect(span.envelope.parentSpanId, parent.parentSpanId);
      expect(log.envelope.spanId, span.envelope.spanId);
      expect(log.envelope.traceId, span.envelope.traceId);
      expect(span.payload.attributes.containsKey('requestId'), isFalse);
    });

    test('should start new traces for invalid or duplicate propagation metadata', () async {
      final upstream = chronicler.recorder.startRootSpan('upstream');
      final carrier = upstream.recorder.injectTrace({});
      final parent = TracePropagation.extract(carrier)!;
      upstream.end(SpanStatus.success);
      final valid = Headers.from(carrier.map((key, value) => MapEntry(key, [value])));
      final app = Inlet(context: context)
        ..use(httpTracing)
        ..get('/', (_, _) => Response.empty());
      for (final headers in [
        valid.set(TracePropagation.traceIdHeader, 'invalid'),
        valid.append(TracePropagation.spanIdHeader, parent.parentSpanId),
        valid.remove(TracePropagation.sampledHeader),
      ]) {
        final request = Request(method: 'GET', uri: Uri.parse('/'), headers: headers);
        addTearDown(request.close);
        final response = await app.handle(request);
        addTearDown(response.close);
        expect(response.statusCode, 204);
      }
      await chronicler.flush();
      final spans = exporter.records
          .whereType<SpanRecord>()
          .where((record) => record.payload.spanKind == SpanKind.server)
          .toList();
      expect(spans, hasLength(3));
      for (final span in spans) {
        expect(span.envelope.traceId, isNot(parent.traceId));
        expect(span.envelope.parentSpanId, isNull);
      }
    });

    test('should honor an unsampled remote parent', () async {
      final upstream = chronicler.recorder.startRootSpan('upstream');
      final carrier = upstream.recorder.injectTrace({})..[TracePropagation.sampledHeader] = '0';
      upstream.end(SpanStatus.success);
      String? sampled;
      final app = Inlet(context: context)
        ..use(httpTracing)
        ..get('/', (context, _) {
          sampled = context.tracing.inject({})[TracePropagation.sampledHeader];
          return Response.empty();
        });
      final request = Request(
        method: 'GET',
        uri: Uri.parse('/'),
        headers: Headers.from(carrier.map((key, value) => MapEntry(key, [value]))),
      );
      addTearDown(request.close);
      final response = await app.handle(request);
      addTearDown(response.close);
      expect(response.statusCode, 204);
      expect(sampled, '0');
      await chronicler.flush();
      expect(
        exporter.records.whereType<SpanRecord>().where(
          (record) => record.payload.spanKind == SpanKind.server,
        ),
        isEmpty,
      );
    });

    test('should mark returned server errors but not client errors as failed', () async {
      final app = Inlet(context: context)
        ..use(httpTracing)
        ..get('/server', (_, _) => Response.empty(status: 503))
        ..get('/client', (_, _) => Response.empty(status: 400));
      for (final path in ['/server', '/client', '/missing-private-id']) {
        final request = Request(method: 'GET', uri: Uri.parse(path));
        addTearDown(request.close);
        final response = await app.handle(request);
        addTearDown(response.close);
      }
      await chronicler.flush();
      final spans = exporter.records.whereType<SpanRecord>().toList();
      expect(spans.map((span) => span.payload.status), [
        SpanStatus.error,
        SpanStatus.success,
        SpanStatus.success,
      ]);
      expect(spans.map((span) => span.payload.attributes['http.response.status_code']), [
        503,
        400,
        404,
      ]);
      expect(spans.last.payload.name, 'GET');
      expect(spans.last.payload.attributes.containsKey('http.route'), isFalse);
    });

    test('should preserve thrown errors without inventing the recovered status', () async {
      final failure = StateError('private failure');
      Object? recovered;
      final app =
          Inlet(
              context: context,
              onReportError: (_, _) {},
              onError: (context, request, error, stackTrace) {
                recovered = error;
                return Response.empty(status: 418);
              },
            )
            ..use(httpTracing)
            ..get('/', (_, _) => throw failure);
      final request = Request(method: 'GET', uri: Uri.parse('/'));
      addTearDown(request.close);
      final response = await app.handle(request);
      addTearDown(response.close);
      expect(response.statusCode, 418);
      expect(recovered, same(failure));
      await chronicler.flush();
      final span = exporter.records.whereType<SpanRecord>().single;
      expect(span.payload.status, SpanStatus.error);
      expect(span.payload.attributes.containsKey('http.response.status_code'), isFalse);
    });

    test('should finish the handler span without consuming the response stream', () async {
      var listened = false;
      Stream<List<int>> body() async* {
        listened = true;
        yield [1, 2, 3];
      }

      final app = Inlet(context: context)
        ..use(httpTracing)
        ..get('/', (_, _) => Response.stream(body()));
      final request = Request(method: 'GET', uri: Uri.parse('/'));
      addTearDown(request.close);
      final response = await app.handle(request);
      addTearDown(response.close);
      await chronicler.flush();
      expect(exporter.records.whereType<SpanRecord>(), hasLength(1));
      expect(listened, isFalse);
      expect(await response.bytes(), [1, 2, 3]);
      expect(listened, isTrue);
    });

    test('should isolate concurrent request spans and request IDs', () async {
      final app = Inlet(context: context)
        ..use(httpTracing)
        ..use(requestId)
        ..get('/', (context, _) async {
          await Future<void>.delayed(Duration.zero);
          return Response.text(context.requestId);
        });
      final ids = await Future.wait(
        List.generate(5, (_) async {
          final request = Request(method: 'GET', uri: Uri.parse('/'));
          addTearDown(request.close);
          final response = await app.handle(request);
          addTearDown(response.close);
          return response.text();
        }),
      );
      await chronicler.flush();
      final spans = exporter.records.whereType<SpanRecord>().toList();
      expect(spans.map((span) => span.payload.attributes['requestId']), unorderedEquals(ids));
      expect(spans.map((span) => span.envelope.traceId).toSet(), hasLength(5));
    });
  });
}

final class _Exporter implements ChroniclerExporter {
  final records = <ChroniclerRecord>[];

  @override
  ExportAttempt export(ChroniclerBatch batch) {
    records.addAll(batch.records);
    return _AcceptedExport();
  }

  @override
  Future<void> close() async {}
}

final class _AcceptedExport implements ExportAttempt {
  @override
  Future<ExportResult> get result async => const ExportResult.accepted();

  @override
  void cancel() {}
}
