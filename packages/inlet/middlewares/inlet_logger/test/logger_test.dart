import 'dart:io';

import 'package:chronicler/chronicler.dart';
import 'package:context/context.dart';
import 'package:inlet/inlet.dart';
import 'package:inlet_logger/inlet_logger.dart';
import 'package:inlet_request_id/inlet_request_id.dart';
import 'package:inlet_tracing/inlet_tracing.dart';
import 'package:test/test.dart';

void main() {
  setUpAll(Chronicler.initialize);
  group('logger', () {
    late _Exporter exporter;
    late Chronicler chronicler;
    late Context context;
    late List<String> output;
    late _Terminal terminal;

    Future<Response> dispatch(Inlet app, Request request) =>
        IOOverrides.runZoned(() => app.handle(request), stdout: () => terminal);
    setUp(() {
      exporter = _Exporter();
      chronicler = Chronicler(
        appId: 'app',
        release: 'test',
        source: ChroniclerSource.server,
        exporter: exporter,
      );
      addTearDown(chronicler.close);
      context = Context().withChronicler(chronicler.recorder);
      output = [];
      terminal = _Terminal(output);
    });

    test('should log one completion with request ID, route, status and duration', () async {
      final app = Inlet(context: context)
        ..use(logger())
        ..use(httpTracing)
        ..use(requestId)
        ..get('/items/:id', (_, _) => Response.text('ok'));
      final request = Request(method: 'GET', uri: Uri.parse('/items/private?token=secret'));
      addTearDown(request.close);
      final response = await dispatch(app, request);
      addTearDown(response.close);
      await chronicler.flush();
      final log = exporter.records.whereType<LogRecord>().single;
      expect(log.payload.message, 'HTTP request completed');
      expect(log.payload.attributes, {
        'http.request.method': 'GET',
        'http.route': '/items/:id',
        'http.response.status_code': 200,
        'requestId': response.headers['x-request-id'],
        'durationMicros': isA<int>().having((value) => value, 'duration', greaterThanOrEqualTo(0)),
      });
      final span = exporter.records.whereType<SpanRecord>().single;
      expect(log.envelope.traceId, span.envelope.traceId);
      expect(log.envelope.spanId, span.envelope.spanId);
      expect(await response.text(), 'ok');
      expect(output, hasLength(1));
      expect(output.single, contains('HTTP 200 GET /items/:id'));
      expect(output.single, contains('requestId: ${response.headers['x-request-id']}'));
      expect(output.single, isNot(contains('private')));
      expect(output.single, isNot(contains('token=secret')));
      expect(output.single, contains(RegExp(r'\d{4}-\d{2}-\d{2}T.*Z')));
    });

    test('should log recovered error status and continue without consuming the response', () async {
      var listened = false;
      Stream<List<int>> body() async* {
        listened = true;
        yield [1, 2];
      }

      final app =
          Inlet(
              context: context,
              onReportError: (_, _) {},
              onError: (_, _, _, _) => Response.stream(body(), status: 422),
            )
            ..use(logger())
            ..get('/', (_, _) => throw StateError('private failure'));
      final request = Request(method: 'GET', uri: Uri.parse('/'));
      addTearDown(request.close);
      final response = await dispatch(app, request);
      addTearDown(response.close);
      expect(listened, isFalse);
      await chronicler.flush();
      final log = exporter.records.whereType<LogRecord>().single;
      expect(log.payload.attributes['http.response.status_code'], 422);
      expect(log.payload.attributes.containsKey('requestId'), isFalse);
      expect(await response.bytes(), [1, 2]);
      expect(listened, isTrue);
    });

    test('should log short circuits and unmatched responses', () async {
      final app = Inlet(context: context)
        ..use(logger())
        ..use(
          (context, request, next) =>
              request.uri.path == '/blocked' ? Response.empty(status: 403) : next(context, request),
        );
      for (final path in ['/blocked', '/private-missing']) {
        final request = Request(method: 'GET', uri: Uri.parse(path));
        addTearDown(request.close);
        final response = await dispatch(app, request);
        addTearDown(response.close);
      }
      await chronicler.flush();
      final logs = exporter.records.whereType<LogRecord>().toList();
      expect(logs, hasLength(2));
      expect(logs.map((log) => log.payload.attributes['http.response.status_code']), [403, 404]);
      expect(logs.every((log) => !log.payload.attributes.containsKey('http.route')), isTrue);
    });

    test('should print to the terminal without a bound recorder', () async {
      final app = Inlet()
        ..use(logger())
        ..get('/', (_, _) => Response.text('ok'));
      final request = Request(method: 'GET', uri: Uri.parse('/'));
      addTearDown(request.close);
      final response = await dispatch(app, request);
      addTearDown(response.close);
      expect(await response.text(), 'ok');
      expect(output, hasLength(1));
      expect(output.single, contains('HTTP 200 GET /'));
      expect(output.single, contains(RegExp(r' · \d+(?:\.\d{2})? (?:µs|ms|s)\n')));
      expect(output.single, isNot(contains('\x1b[')));
      await chronicler.flush();
      expect(exporter.records, isEmpty);
    });

    test('should retain request isolation across concurrent completions', () async {
      final app = Inlet(context: context)
        ..use(logger())
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
          final response = await dispatch(app, request);
          addTearDown(response.close);
          return response.text();
        }),
      );
      await chronicler.flush();
      final logs = exporter.records.whereType<LogRecord>().toList();
      expect(logs.map((log) => log.payload.attributes['requestId']), unorderedEquals(ids));
      expect(logs.map((log) => log.envelope.traceId).toSet(), hasLength(5));
    });

    test('should record access logs even when traces are not sampled', () async {
      final unsampled = Chronicler(
        appId: 'app',
        release: 'test',
        source: ChroniclerSource.server,
        exporter: exporter,
        options: const ChroniclerOptions(sampling: SamplingOptions(traces: 0)),
      );
      addTearDown(unsampled.close);
      final app = Inlet(context: Context().withChronicler(unsampled.recorder))
        ..use(logger())
        ..use(httpTracing)
        ..use(requestId)
        ..get('/', (_, _) => Response.empty());
      final request = Request(method: 'GET', uri: Uri.parse('/'));
      addTearDown(request.close);
      final response = await dispatch(app, request);
      addTearDown(response.close);
      await unsampled.flush();
      expect(exporter.records.whereType<SpanRecord>(), isEmpty);
      final log = exporter.records.whereType<LogRecord>().single;
      expect(log.payload.attributes['requestId'], response.headers['x-request-id']);
      expect(log.envelope.traceId, isNotNull);
    });

    test('should disable console output without disabling Chronicler', () async {
      for (final console in [false, true]) {
        output.clear();
        exporter.records.clear();
        final app = Inlet(context: context)
          ..use(logger(console: console))
          ..get('/', (_, _) => Response.empty());
        final request = Request(method: 'GET', uri: Uri.parse('/'));
        addTearDown(request.close);
        final response = await dispatch(app, request);
        addTearDown(response.close);
        await chronicler.flush();
        expect(output, hasLength(console ? 1 : 0));
        expect(exporter.records, hasLength(1));
        if (output.isNotEmpty) expect(output.single, isNot(contains('\x1b[')));
      }
    });

    test('should color supported terminals unless NO_COLOR is set', () async {
      terminal.supportsAnsiEscapes = true;
      final app = Inlet()..use(logger());
      for (final status in [200, 302, 404, 503]) {
        app.get('/$status', (_, _) => Response.empty(status: status));
      }
      for (final status in [200, 302, 404, 503]) {
        final request = Request(method: 'GET', uri: Uri.parse('/$status'));
        addTearDown(request.close);
        final response = await dispatch(app, request);
        addTearDown(response.close);
      }
      if (Platform.environment.containsKey('NO_COLOR')) {
        expect(output.every((line) => !line.contains('\x1b[')), isTrue);
        return;
      }
      expect(output[0], startsWith('\x1b[32m'));
      expect(output[1], startsWith('\x1b[36m'));
      expect(output[2], startsWith('\x1b[33m'));
      expect(output[3], startsWith('\x1b[31m'));
      expect(output.every((line) => line.endsWith('\x1b[0m')), isTrue);
    });

    test('should preserve the response and Chronicler log when terminal output fails', () async {
      final failure = StateError('terminal failed');
      final reports = <Object>[];
      terminal.failure = failure;
      final app = Inlet(context: context, onReportError: (error, _) => reports.add(error))
        ..use(logger())
        ..get('/', (_, _) => Response.text('ok'));
      final request = Request(method: 'GET', uri: Uri.parse('/'));
      addTearDown(request.close);
      final response = await dispatch(app, request);
      addTearDown(response.close);
      expect(await response.text(), 'ok');
      expect(reports, [same(failure)]);
      await chronicler.flush();
      expect(exporter.records.whereType<LogRecord>(), hasLength(1));
    });

    test('should escape terminal controls in route metadata', () async {
      final app = Inlet()
        ..use(logger())
        ..get('/items/\x1b[31m', (_, _) => Response.empty());
      final request = Request(method: 'GET', uri: Uri.parse('/items/%1B%5B31m'));
      addTearDown(request.close);
      final response = await dispatch(app, request);
      addTearDown(response.close);
      expect(response.statusCode, 204);
      expect(output.single, contains(r'\u001b[31m'));
      expect(output.single, isNot(contains('\x1b')));
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

final class _Terminal implements Stdout {
  _Terminal(this.lines);
  final List<String> lines;
  Object? failure;

  @override
  bool supportsAnsiEscapes = false;

  @override
  void writeln([Object? object = '']) {
    if (failure case final error?) throw error;
    lines.add('$object');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _AcceptedExport implements ExportAttempt {
  @override
  Future<ExportResult> get result async => const ExportResult.accepted();
  @override
  void cancel() {}
}
