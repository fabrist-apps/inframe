import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:inlet/inlet.dart';
import 'package:test/test.dart';

import 'wire_client.dart';

void main() {
  group('Inlet HTTP streaming', () {
    test('should deliver response chunks before the source completes', () async {
      final source = StreamController<List<int>>();
      final application = Inlet()..get('/stream', (_, _) => Response.stream(source.stream));
      final server = await application.serve(port: 0);
      addTearDown(() => server.close(force: true));
      final client = HttpClient();
      addTearDown(() => client.close(force: true));

      final request = await client.get(server.address.address, server.port, '/stream');
      final responseFuture = request.close();
      source.add(utf8.encode('first'));
      final response = await responseFuture;
      final firstChunk = Completer<List<int>>();
      final received = <int>[];
      final done = Completer<void>();
      response.listen(
        (chunk) {
          received.addAll(chunk);
          if (!firstChunk.isCompleted) {
            firstChunk.complete(List.of(chunk));
          }
        },
        onError: done.completeError,
        onDone: done.complete,
      );
      expect(
        utf8.decode(await firstChunk.future.timeout(const Duration(seconds: 2))),
        'first',
      );
      expect(source.isClosed, isFalse);
      source.add(utf8.encode('second'));
      await source.close();
      await done.future;
      expect(utf8.decode(received), 'firstsecond');
    });

    test('should lazily stream a request after the handler returns', () async {
      var handlerReturned = false;
      final application = Inlet()
        ..post('/echo', (_, request) {
          handlerReturned = true;
          return Response.stream(request.body);
        });
      final server = await application.serve(port: 0);
      addTearDown(() => server.close(force: true));
      final wire = await WireClient.connect(server);
      addTearDown(wire.close);

      wire.send(
        'POST /echo HTTP/1.1\r\n'
        'Host: ${server.address.address}:${server.port}\r\n'
        'Content-Length: 6\r\n'
        'Connection: close\r\n'
        '\r\n'
        'abc',
      );

      await wire.waitFor((value) => value.contains('abc'));
      expect(handlerReturned, isTrue);
      expect(wire.text, contains('HTTP/1.1 200'));
      wire.send('def');
      await wire.waitFor((value) => value.contains('def'));
    });

    test('should send an early response without draining an untouched upload', () async {
      var handlerCalls = 0;
      final application = Inlet()
        ..post('/early', (_, _) {
          handlerCalls++;
          return Response.text('accepted');
        });
      final server = await application.serve(port: 0);
      addTearDown(() => server.close(force: true));
      final wire = await WireClient.connect(server);
      addTearDown(wire.close);

      wire.send(
        'POST /early HTTP/1.1\r\n'
        'Host: ${server.address.address}:${server.port}\r\n'
        'Content-Length: 1000000\r\n'
        '\r\n',
      );

      await wire.waitFor((value) => value.contains('accepted'));
      expect(wire.text, contains('HTTP/1.1 200'));
      expect(wire.text.toLowerCase(), contains('connection: close'));
      expect(handlerCalls, 1);
    });

    test('should send 413 before an oversized upload finishes', () async {
      final application = Inlet()
        ..post('/limited', (_, request) async {
          await request.bytes(maxBytes: 4);
          return Response.empty();
        });
      final server = await application.serve(port: 0);
      addTearDown(() => server.close(force: true));
      final wire = await WireClient.connect(server);
      addTearDown(wire.close);

      wire.send(
        'POST /limited HTTP/1.1\r\n'
        'Host: ${server.address.address}:${server.port}\r\n'
        'Content-Length: 1000000\r\n'
        '\r\n'
        '12345',
      );

      await wire.waitFor((value) => value.contains('HTTP/1.1 413'));
      expect(wire.text.toLowerCase(), contains('connection: close'));
    });

    test('should propagate request consumer pause and resume', () async {
      final firstChunk = Completer<void>();
      final bodyDone = Completer<void>();
      final chunks = <String>[];
      StreamSubscription<List<int>>? bodySubscription;
      final application = Inlet()
        ..post('/controlled', (_, request) async {
          bodySubscription = request.body.listen(
            (chunk) {
              chunks.add(utf8.decode(chunk));
              if (!firstChunk.isCompleted) {
                bodySubscription!.pause();
                firstChunk.complete();
              }
            },
            onError: bodyDone.completeError,
            onDone: bodyDone.complete,
          );
          await bodyDone.future;
          return Response.text(chunks.join());
        });
      final server = await application.serve(port: 0);
      addTearDown(() => server.close(force: true));
      addTearDown(() => bodySubscription?.cancel() ?? Future<void>.value());
      final wire = await WireClient.connect(server);
      addTearDown(wire.close);

      wire.send(
        'POST /controlled HTTP/1.1\r\n'
        'Host: ${server.address.address}:${server.port}\r\n'
        'Content-Length: 2\r\n'
        'Connection: close\r\n'
        '\r\n'
        'a',
      );
      await firstChunk.future.timeout(const Duration(seconds: 2));
      wire.send('b');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(chunks, ['a']);

      bodySubscription!.resume();
      await wire.waitFor((value) => value.contains('ab'));
      expect(chunks, ['a', 'b']);
    });

    test('should cancel a response producer after client disconnect', () async {
      final cancelled = Completer<void>();
      late StreamController<List<int>> source;
      Timer? producer;
      source = StreamController<List<int>>(
        onListen: () {
          producer = Timer.periodic(const Duration(milliseconds: 1), (_) {
            source.add(List<int>.filled(64 * 1024, 1));
          });
        },
        onCancel: () {
          producer?.cancel();
          cancelled.complete();
        },
      );
      final application = Inlet(
        onReportError: (_, _) {},
      )..get('/stream', (_, _) => Response.stream(source.stream));
      final server = await application.serve(port: 0);
      addTearDown(() => server.close(force: true));
      final socket = await Socket.connect(server.address, server.port);

      socket.write(
        'GET /stream HTTP/1.1\r\n'
        'Host: ${server.address.address}:${server.port}\r\n'
        '\r\n',
      );
      await socket.flush();
      await socket.first.timeout(const Duration(seconds: 2));
      socket.destroy();

      await cancelled.future.timeout(const Duration(seconds: 2));
    });

    test('should report a post-commit source failure once without recovery', () async {
      final reports = <Object>[];
      var hookCalls = 0;
      final cancelled = Completer<void>();
      late StreamController<List<int>> source;
      source = StreamController<List<int>>(
        onListen: () {
          source
            ..add(utf8.encode('started'))
            ..addError(StateError('source failed'));
        },
        onCancel: cancelled.complete,
      );
      final application = Inlet(
        onError: (_, _, _, _) {
          hookCalls++;
          return Response.text('replacement');
        },
        onReportError: (error, _) => reports.add(error),
      )..get('/stream', (_, _) => Response.stream(source.stream));
      final server = await application.serve(port: 0);
      addTearDown(() => server.close(force: true));
      final client = HttpClient();
      addTearDown(() => client.close(force: true));

      final request = await client.get(server.address.address, server.port, '/stream');
      final response = await request.close();
      await expectLater(response.drain<void>(), throwsA(anything));
      await Future<void>.delayed(Duration.zero);
      await cancelled.future.timeout(const Duration(seconds: 2));

      expect(reports, hasLength(1));
      expect(reports.single.toString(), 'Bad state: source failed');
      expect(hookCalls, 0);
    });
  });
}
