import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:inlet/inlet.dart';
import 'package:test/test.dart';

import 'wire_client.dart';

void main() {
  group('Inlet bodyless delivery', () {
    test('should preserve known HEAD length without subscribing', () async {
      var subscriptions = 0;
      final application = Inlet()
        ..get('/known', (_, _) => Response.bytes([1, 2, 3]))
        ..head('/explicit', (_, _) => _lazyResponse(() => subscriptions++));
      final server = await application.serve(port: 0);
      addTearDown(() => server.close(force: true));

      final fallback = await _rawRequest(server, 'HEAD', '/known');
      final explicit = await _rawRequest(server, 'HEAD', '/explicit');

      expect(fallback.statusLine, contains(' 200 '));
      expect(fallback.header('content-length'), '3');
      expect(fallback.body, isEmpty);
      expect(explicit.header('content-length'), isNull);
      expect(explicit.header('transfer-encoding'), isNull);
      expect(explicit.body, isEmpty);
      expect(subscriptions, 0);
    });

    test('should omit framing for 204 and 304 without subscribing', () async {
      var subscriptions = 0;
      Response bodyless(int status) => _lazyResponse(
        () => subscriptions++,
        status: status,
      );
      final application = Inlet()
        ..get('/204', (_, _) => bodyless(HttpStatus.noContent))
        ..get('/304', (_, _) => bodyless(HttpStatus.notModified));
      final server = await application.serve(port: 0);
      addTearDown(() => server.close(force: true));

      final noContent = await _rawRequest(server, 'GET', '/204');
      final notModified = await _rawRequest(server, 'GET', '/304');

      for (final response in [noContent, notModified]) {
        expect(response.header('content-length'), isNull);
        expect(response.header('transfer-encoding'), isNull);
        expect(response.body, isEmpty);
      }
      expect(subscriptions, 0);
    });

    test('should send zero length for 205 without subscribing', () async {
      var subscriptions = 0;
      final application = Inlet()
        ..get(
          '/reset',
          (_, _) => _lazyResponse(
            () => subscriptions++,
            status: HttpStatus.resetContent,
          ),
        );
      final server = await application.serve(port: 0);
      addTearDown(() => server.close(force: true));

      final response = await _rawRequest(server, 'GET', '/reset');

      expect(response.header('content-length'), '0');
      expect(response.header('transfer-encoding'), isNull);
      expect(response.body, isEmpty);
      expect(subscriptions, 0);
    });

    test('should preserve application headers and ordinary framing', () async {
      final headers = const Headers.empty()
          .append(HttpHeaders.setCookieHeader, 'first=1')
          .append(HttpHeaders.setCookieHeader, 'second=2')
          .set('x-application', 'inlet');
      final application = Inlet()
        ..get(
          '/buffered',
          (_, _) => Response.bytes(
            utf8.encode('abc'),
            headers: headers,
            contentType: null,
          ),
        )
        ..get(
          '/streamed',
          (_, _) => Response.stream(
            Stream.value(utf8.encode('abc')),
            contentType: null,
          ),
        );
      final server = await application.serve(port: 0);
      addTearDown(() => server.close(force: true));

      final buffered = await _rawRequest(server, 'GET', '/buffered');
      final streamed = await _rawRequest(server, 'GET', '/streamed');

      expect(buffered.header('content-length'), '3');
      expect(buffered.header('transfer-encoding'), isNull);
      expect(buffered.header('content-type'), isNull);
      expect(buffered.header('x-application'), 'inlet');
      expect(buffered.headers.where((line) => line.toLowerCase().startsWith('set-cookie:')), [
        'set-cookie: first=1',
        'set-cookie: second=2',
      ]);
      expect(buffered.body, latin1.encode('abc'));
      expect(streamed.header('content-length'), isNull);
      expect(streamed.header('transfer-encoding'), 'chunked');
      expect(streamed.header('content-type'), isNull);
      expect(latin1.decode(streamed.body), contains('abc'));
    });
  });

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
      final response = await _rawRequest(second, 'GET', '/ready');

      expect(response.statusLine, contains(' 200 '));
      expect(latin1.decode(response.body), 'ready');
      await second.close(force: true);
    });
  });
}

Response _lazyResponse(void Function() onListen, {int status = HttpStatus.ok}) {
  return Response.stream(
    Stream<List<int>>.multi((controller) {
      onListen();
      unawaited((controller..add([1, 2, 3])).close());
    }),
    status: status,
  );
}

Future<_RawResponse> _rawRequest(
  InletServer server,
  String method,
  String path,
) async {
  final socket = await Socket.connect(server.address, server.port);
  socket.write(
    '$method $path HTTP/1.1\r\n'
    'Host: ${server.address.address}:${server.port}\r\n'
    'Connection: close\r\n'
    '\r\n',
  );
  await socket.flush();
  final bytes = await socket.fold<List<int>>(<int>[], (all, chunk) => all..addAll(chunk));
  await socket.close();
  return _RawResponse.parse(bytes);
}

final class _RawResponse {
  const _RawResponse(this.statusLine, this.headers, this.body);

  factory _RawResponse.parse(List<int> wireBytes) {
    final boundary = _indexOf(wireBytes, const [13, 10, 13, 10]);
    if (boundary < 0) {
      throw const FormatException('HTTP response did not contain a header boundary.');
    }
    final lines = latin1.decode(wireBytes.sublist(0, boundary)).split('\r\n');
    return _RawResponse(
      lines.first,
      List.unmodifiable(lines.skip(1)),
      List.unmodifiable(wireBytes.sublist(boundary + 4)),
    );
  }

  final String statusLine;
  final List<String> headers;
  final List<int> body;

  String? header(String name) {
    final prefix = '${name.toLowerCase()}:';
    for (final line in headers) {
      if (line.toLowerCase().startsWith(prefix)) {
        return line.substring(line.indexOf(':') + 1).trim();
      }
    }
    return null;
  }
}

int _indexOf(List<int> bytes, List<int> pattern) {
  for (var index = 0; index <= bytes.length - pattern.length; index++) {
    var matches = true;
    for (var offset = 0; offset < pattern.length; offset++) {
      if (bytes[index + offset] != pattern[offset]) {
        matches = false;
        break;
      }
    }
    if (matches) {
      return index;
    }
  }
  return -1;
}
