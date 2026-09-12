import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:artificer_core/artificer_core.dart';
import 'package:artificer_core/transport.dart';
import 'package:conflux/conflux.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

void main() {
  test('multipart opens a fresh source and preserves fields and file metadata', () async {
    var opens = 0;
    final bodies = <List<int>>[];
    final contentTypes = <String>[];
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      contentTypes.add(request.headers.contentType.toString());
      bodies.add(await request.fold(<int>[], (result, chunk) => result..addAll(chunk)));
      request.response
        ..headers.contentType = ContentType.json
        ..write('{"id":"file_1"}');
      await request.response.close();
    });
    final client = ProviderHttpClient(
      baseUrl: Uri.parse('http://${server.address.address}:${server.port}/'),
    );
    addTearDown(client.close);
    final source = UploadSource.stream(
      () {
        opens++;
        return Stream.value([0, 1, 2, 255]);
      },
      length: 4,
      filename: 'data.bin',
      mimeType: 'application/octet-stream',
    );
    final operation = client.sendMultipart(
      ProviderMultipartRequest(path: 'files', fields: {'purpose': 'assistants'}),
      source,
      providerId: 'fixture',
      api: 'files',
    );

    await operation.runFuture();
    await operation.runFuture();

    expect(opens, 2);
    expect(contentTypes, everyElement(startsWith('multipart/form-data; boundary=')));
    for (var index = 0; index < bodies.length; index++) {
      final body = bodies[index];
      final text = latin1.decode(body);
      expect(text, contains('name="purpose"\r\n\r\nassistants'));
      expect(text, contains('name="file"; filename="data.bin"'));
      expect(text, contains('Content-Type: application/octet-stream'));
      expect(body, containsAllInOrder([0, 1, 2, 255]));
    }
  });

  test('byte responses stream with limits and release on early consumption', () async {
    var cancellations = 0;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      request.response.headers.contentType = ContentType.binary;
      try {
        request.response.add([1, 2]);
        await request.response.flush();
        await Future<void>.delayed(const Duration(milliseconds: 20));
        request.response.add(List.filled(20, 3));
        await request.response.close();
      } on Object {
        cancellations++;
      }
    });
    final client = ProviderHttpClient(
      baseUrl: Uri.parse('http://${server.address.address}:${server.port}/'),
    );
    addTearDown(client.close);

    final first = await client
        .sendBytes(ProviderHttpRequest(method: 'GET', path: 'content'))
        .take(1)
        .runCollect()
        .runFuture();
    final limited = await client
        .sendBytes(
          ProviderHttpRequest(method: 'GET', path: 'content'),
          maxResponseBytes: 4,
        )
        .runCollect()
        .runFutureExit();

    expect(first.expand((chunk) => chunk), [1, 2]);
    expect(limited, _failedWith<ResponseLimitError>());
    expect(cancellations, greaterThanOrEqualTo(0));
  });

  test('byte cancellation before headers aborts acquisition', () async {
    final transport = _ByteHoldingClient(holdHeaders: true);
    final client = ProviderHttpClient(
      baseUrl: Uri.parse('https://example.test/'),
      client: transport,
    );
    addTearDown(client.close);
    final runtime = Runtime();
    addTearDown(runtime.close);
    final fiber = runtime.fork(
      client.sendBytes(ProviderHttpRequest(method: 'GET', path: 'content')).runCollect(),
    );
    await transport.sent.future;

    final exit = await fiber.interrupt('caller').timeout(const Duration(seconds: 2));

    expect((exit as Failed<Object?, AiError>).cause.containsInterruption, isTrue);
    expect(transport.abortSeen, isTrue);
  });

  test('early byte consumption cancels the response subscription', () async {
    final transport = _ByteHoldingClient();
    final client = ProviderHttpClient(
      baseUrl: Uri.parse('https://example.test/'),
      client: transport,
    );
    addTearDown(client.close);
    final operation = client
        .sendBytes(ProviderHttpRequest(method: 'GET', path: 'content'))
        .take(1)
        .runCollect();
    final future = operation.runFuture();
    await transport.listening.future;
    transport.body.add([1, 2]);

    expect(await future, [
      [1, 2],
    ]);
    expect(transport.bodyCancelled, isTrue);
  });

  test('byte response failures stay in the typed error channel', () async {
    final malformed = ProviderHttpClient(
      baseUrl: Uri.parse('https://example.test/'),
      client: _StaticByteClient(statusCode: 502, body: utf8.encode('<html>bad gateway</html>')),
    );
    addTearDown(malformed.close);
    final interrupted = ProviderHttpClient(
      baseUrl: Uri.parse('https://example.test/'),
      client: _FailingByteClient(),
    );
    addTearDown(interrupted.close);

    final malformedExit = await malformed
        .sendBytes(ProviderHttpRequest(method: 'GET', path: 'content'))
        .runCollect()
        .runFutureExit();
    final interruptedExit = await interrupted
        .sendBytes(ProviderHttpRequest(method: 'GET', path: 'content'))
        .runCollect()
        .runFutureExit();

    expect(malformedExit, _failedWith<ProtocolError>());
    expect(interruptedExit, _failedWith<TransportError>());
  });
}

Matcher _failedWith<E extends AiError>() => isA<Failed<Object?, AiError>>().having(
  (failure) => (failure.cause as Expected<AiError>).error,
  'error',
  isA<E>(),
);

final class _ByteHoldingClient extends http.BaseClient {
  _ByteHoldingClient({this.holdHeaders = false});

  final bool holdHeaders;
  final sent = Completer<void>();
  final listening = Completer<void>();
  late final StreamController<List<int>> body = StreamController<List<int>>(
    onListen: listening.complete,
    onCancel: () => bodyCancelled = true,
  );
  bool abortSeen = false;
  bool bodyCancelled = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (!sent.isCompleted) sent.complete();
    final response = Completer<http.StreamedResponse>();
    if (!holdHeaders) response.complete(http.StreamedResponse(body.stream, 200));
    if (request case http.Abortable(:final abortTrigger?)) {
      unawaited(
        abortTrigger.whenComplete(() {
          abortSeen = true;
          if (!response.isCompleted) {
            response.completeError(http.RequestAbortedException(request.url));
          }
        }),
      );
    }
    return response.future;
  }
}

final class _StaticByteClient extends http.BaseClient {
  _StaticByteClient({required this.statusCode, required this.body});

  final int statusCode;
  final List<int> body;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      http.StreamedResponse(Stream.value(body), statusCode);
}

final class _FailingByteClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async => http.StreamedResponse(
    Stream<List<int>>.error(const SocketException('connection reset')),
    502,
  );
}
