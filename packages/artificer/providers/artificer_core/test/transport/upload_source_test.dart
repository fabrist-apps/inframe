import 'dart:async';
import 'dart:io';

import 'package:artificer_core/artificer_core.dart';
import 'package:artificer_core/transport.dart';
import 'package:conflux/conflux.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

void main() {
  group('UploadSource', () {
    test('should copy byte input and open stream factories lazily per execution', () async {
      final bytes = [1, 2, 3];
      final byteSource = UploadSource.bytes(
        bytes,
        filename: 'image.png',
        mimeType: 'image/png',
      );
      bytes[0] = 9;
      expect(await byteSource.openRead().expand((chunk) => chunk).toList(), [1, 2, 3]);

      var opens = 0;
      final streamSource = UploadSource.stream(
        () {
          opens++;
          return Stream.value([4, 5]);
        },
        length: 2,
        filename: 'data.bin',
        mimeType: 'application/octet-stream',
      );
      expect(opens, 0);
      await streamSource.openRead().drain<void>();
      await streamSource.openRead().drain<void>();
      expect(opens, 2);
    });

    test('should upload exact bytes and metadata once per execution', () async {
      final received = <List<int>>[];
      final filenames = <String?>[];
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        received.add(await request.fold(<int>[], (bytes, chunk) => bytes..addAll(chunk)));
        filenames.add(request.headers.value('content-disposition'));
        request.response.write('{"id":"file-1"}');
        await request.response.close();
      });
      final client = ProviderHttpClient(
        baseUrl: Uri.parse('http://${server.address.address}:${server.port}/'),
      );
      addTearDown(client.close);
      final source = UploadSource.bytes(
        [1, 2, 3],
        filename: 'image.png',
        mimeType: 'image/png',
      );
      final operation = client.sendUpload(
        ProviderUploadRequest(path: 'files'),
        source,
        providerId: 'fixture',
        api: 'files',
      );

      await operation.runFuture();
      await operation.runFuture();

      expect(received, [
        [1, 2, 3],
        [1, 2, 3],
      ]);
      expect(filenames, everyElement(contains('image.png')));
    });

    test('should cancel the opened source and retain allocated remote ID', () async {
      final sourceListening = Completer<void>();
      var sourceCancelled = false;
      final sourceController = StreamController<List<int>>(
        onListen: sourceListening.complete,
        onCancel: () => sourceCancelled = true,
      );
      final transport = _UploadHoldingClient();
      final client = ProviderHttpClient(
        baseUrl: Uri.parse('https://example.test/'),
        client: transport,
      );
      final runtime = Runtime();
      addTearDown(runtime.close);
      addTearDown(client.close);
      final fiber = runtime.fork(
        client.sendUpload(
          ProviderUploadRequest(path: 'files', remoteResourceId: 'upload-1'),
          UploadSource.stream(
            () => sourceController.stream,
            length: 4,
            filename: 'data.bin',
            mimeType: 'application/octet-stream',
          ),
          providerId: 'fixture',
          api: 'files',
        ),
      );
      await sourceListening.future;

      final exit = await fiber.interrupt('caller').timeout(const Duration(seconds: 2));
      expect(transport.abortSeen, isTrue);
      expect(sourceCancelled, isTrue);

      expect((exit as Failed<Object?, AiError>).cause.containsInterruption, isTrue);
      expect(sourceCancelled, isTrue);
    });

    test('should cancel an active upload before provider close completes', () async {
      final sourceListening = Completer<void>();
      var sourceCancelled = false;
      final sourceController = StreamController<List<int>>(
        onListen: sourceListening.complete,
        onCancel: () => sourceCancelled = true,
      );
      final transport = _UploadHoldingClient();
      final client = ProviderHttpClient(
        baseUrl: Uri.parse('https://example.test/'),
        client: transport,
      );
      final runtime = Runtime();
      addTearDown(runtime.close);
      final fiber = runtime.fork(
        client.sendUpload(
          ProviderUploadRequest(path: 'files'),
          UploadSource.stream(
            () => sourceController.stream,
            length: 4,
            filename: 'data.bin',
            mimeType: 'application/octet-stream',
          ),
          providerId: 'fixture',
          api: 'files',
        ),
      );
      await sourceListening.future;

      await client.close().timeout(const Duration(seconds: 2));
      final exit = await fiber.join();

      expect((exit as Failed<Object?, AiError>).cause.containsInterruption, isTrue);
      expect(transport.abortSeen, isTrue);
      expect(sourceCancelled, isTrue);
    });

    test('should reject a declared length mismatch', () async {
      final transport = _UploadHoldingClient();
      final client = ProviderHttpClient(
        baseUrl: Uri.parse('https://example.test/'),
        client: transport,
      );
      addTearDown(client.close);

      final exit = await client
          .sendUpload(
            ProviderUploadRequest(path: 'files', remoteResourceId: 'upload-1'),
            UploadSource.stream(
              () => Stream.value([1]),
              length: 2,
              filename: 'data.bin',
              mimeType: 'application/octet-stream',
            ),
            providerId: 'fixture',
            api: 'files',
          )
          .runFutureExit();

      expect(exit, _expectedError<InvalidRequestError>());
      final error = ((exit as Failed<Object?, AiError>).cause as Expected<AiError>).error;
      expect((error as InvalidRequestError).remoteResourceId, 'upload-1');
    });

    test('should reject upload metadata that could alter MIME headers', () {
      expect(
        () => UploadSource.bytes(
          [1],
          filename: 'data.bin',
          mimeType: 'application/octet-stream\r\nx-injected: true',
        ),
        throwsArgumentError,
      );
      expect(
        () => UploadSource.bytes(
          [256],
          filename: 'data.bin',
          mimeType: 'application/octet-stream',
        ),
        throwsArgumentError,
      );
    });

    test('should cancel a stream after its first invalid byte error', () async {
      var sourceCancelled = false;
      final source = StreamController<List<int>>(
        sync: true,
        onCancel: () => sourceCancelled = true,
      );
      final errors = <Object>[];
      final done = Completer<void>();
      UploadSource.stream(
        () => source.stream,
        length: 2,
        filename: 'data.bin',
        mimeType: 'application/octet-stream',
      ).openRead().listen(
        (_) {},
        onError: errors.add,
        onDone: done.complete,
      );

      source.add([256]);
      await done.future;
      source.add([257]);
      await Future<void>.delayed(Duration.zero);

      expect(errors, [isA<UploadInvalidByte>()]);
      expect(sourceCancelled, isTrue);
    });
  });
}

Matcher _expectedError<E extends AiError>() => isA<Failed<Object?, AiError>>().having(
  (failure) => failure.cause,
  'cause',
  isA<Expected<AiError>>().having((cause) => cause.error, 'error', isA<E>()),
);

final class _UploadHoldingClient extends http.BaseClient {
  bool abortSeen = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    final response = Completer<http.StreamedResponse>();
    late final StreamSubscription<List<int>> body;
    body = request.finalize().listen(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {
        if (!response.isCompleted) response.completeError(error, stackTrace);
      },
      onDone: () {
        if (!response.isCompleted) {
          response.complete(http.StreamedResponse(Stream.value('{}'.codeUnits), 200));
        }
      },
    );
    if (request case http.Abortable(:final abortTrigger?)) {
      unawaited(
        abortTrigger.whenComplete(() {
          abortSeen = true;
          if (!response.isCompleted) {
            response.completeError(http.RequestAbortedException(request.url));
          }
          return body.cancel();
        }),
      );
    }
    return response.future;
  }
}
