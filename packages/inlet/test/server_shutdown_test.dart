import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:inlet/inlet.dart';
import 'package:test/test.dart';

import 'support/wire_client.dart';

void main() {
  group('Inlet server shutdown', () {
    test('should return one close future without waiting for handlers', () async {
      final handlerStarted = Completer<void>();
      final releaseHandler = Completer<void>();
      final application = Inlet()
        ..get('/wait', (_, _) async {
          handlerStarted.complete();
          await releaseHandler.future;
          return Response.text('done');
        });
      final server = await application.serve(port: 0);
      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      final request = await client.get(server.address.address, server.port, '/wait');
      final responseFuture = request.close();
      await handlerStarted.future;

      final firstClose = server.close();
      final secondClose = server.close();
      expect(secondClose, same(firstClose));
      await firstClose.timeout(const Duration(seconds: 2));
      expect(releaseHandler.isCompleted, isFalse);

      releaseHandler.complete();
      final response = await responseFuture;
      expect(await utf8.decodeStream(response), 'done');
    });

    test('should escalate a completed normal close to force active connections', () async {
      final cancelled = Completer<void>();
      late StreamController<List<int>> source;
      source = StreamController<List<int>>(
        onListen: () => source.add(utf8.encode('started')),
        onCancel: cancelled.complete,
      );
      final application = Inlet(
        onReportError: (_, _) {},
      )..get('/stream', (_, _) => Response.stream(source.stream));
      final server = await application.serve(port: 0);
      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      final request = await client.get(server.address.address, server.port, '/stream');
      final response = await request.close();
      final firstChunk = Completer<void>();
      response.listen(
        (_) => firstChunk.complete(),
        onError: (_, _) {},
      );
      await firstChunk.future;

      final normalClose = server.close();
      await normalClose.timeout(const Duration(seconds: 2));
      expect(cancelled.isCompleted, isFalse);
      expect(server.close(force: true), same(normalClose));

      await cancelled.future.timeout(const Duration(seconds: 2));
    });

    test('should return 503 for requests observed after closing begins', () async {
      final release = Completer<void>();
      final firstStarted = Completer<void>();
      var handlerCalls = 0;
      final application = Inlet()
        ..get('/work', (_, _) async {
          handlerCalls++;
          if (!firstStarted.isCompleted) {
            firstStarted.complete();
          }
          await release.future;
          return Response.text('first');
        });
      final server = await application.serve(port: 0);
      final wire = await WireClient.connect(server);
      addTearDown(wire.close);

      wire.send(
        'GET /work HTTP/1.1\r\n'
        'Host: ${server.address.address}:${server.port}\r\n'
        '\r\n'
        'GET /work HTTP/1.1\r\n'
        'Host: ${server.address.address}:${server.port}\r\n'
        'Connection: close\r\n'
        '\r\n',
      );
      await firstStarted.future;
      final close = server.close();
      release.complete();

      await wire.waitFor(
        (text) => RegExp(r'HTTP/1\.1 503').allMatches(text).length == 1,
      );
      expect(handlerCalls, 1);
      await close;
    });

    test('should close multiple listeners independently', () async {
      final application = Inlet()..get('/ready', (_, _) => Response.text('ready'));
      final first = await application.serve(port: 0);
      final second = await application.serve(port: 0);

      await first.close(force: true);
      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      final request = await client.get(second.address.address, second.port, '/ready');
      final response = await request.close();

      expect(response.statusCode, HttpStatus.ok);
      expect(await utf8.decodeStream(response), 'ready');
      await second.close(force: true);
    });
  });
}
