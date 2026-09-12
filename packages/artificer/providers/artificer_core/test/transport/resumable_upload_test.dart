import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:artificer_core/artificer_core.dart';
import 'package:artificer_core/json.dart';
import 'package:artificer_core/transport.dart';
import 'package:conflux/conflux.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

void main() {
  group('ProviderHttpClient resumable upload', () {
    test('should keep both exchanges in one repeatable credential-safe operation', () async {
      final uploads = <List<int>>[];
      final uploadHeaders = <HttpHeaders>[];
      final uploadServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => uploadServer.close(force: true));
      uploadServer.listen((request) async {
        uploadHeaders.add(request.headers);
        uploads.add(await request.fold(<int>[], (bytes, chunk) => bytes..addAll(chunk)));
        request.response.write('{"file":{"name":"files/file-1"}}');
        await request.response.close();
      });
      var starts = 0;
      final startServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => startServer.close(force: true));
      startServer.listen((request) async {
        starts++;
        expect(request.headers.value('x-api-key'), 'secret');
        expect(await utf8.decoder.bind(request).join(), '{"file":{"displayName":"sample"}}');
        request.response.headers
          ..set(
            'x-goog-upload-url',
            'http://${uploadServer.address.address}:${uploadServer.port}/session',
          )
          ..set('x-guploader-uploadid', 'upload-1');
        await request.response.close();
      });
      final client = ProviderHttpClient(
        baseUrl: Uri.parse('http://${startServer.address.address}:${startServer.port}'),
        headers: {'x-api-key': 'secret'},
      );
      addTearDown(client.close);
      var opens = 0;
      final operation = client.sendResumableUpload(
        ProviderResumableUploadRequest(
          startRequest: ProviderHttpRequest(
            method: 'POST',
            path: '/start',
            body: JsonObject({
              'file': {'displayName': 'sample'},
            }),
          ),
          uploadHeaders: {
            'x-goog-upload-offset': '0',
            'x-goog-upload-command': 'upload, finalize',
          },
          remoteResourceIdHeader: 'x-guploader-uploadid',
        ),
        UploadSource.stream(
          () {
            opens++;
            return Stream.value([1, 2, 3]);
          },
          length: 3,
          filename: 'sample.bin',
          mimeType: 'application/octet-stream',
        ),
        providerId: 'fixture',
        api: 'files',
      );

      expect(starts, 0);
      expect(opens, 0);
      await operation.runFuture();
      await operation.runFuture();

      expect(starts, 2);
      expect(opens, 2);
      expect(uploads, [
        [1, 2, 3],
        [1, 2, 3],
      ]);
      expect(uploadHeaders, hasLength(2));
      for (final headers in uploadHeaders) {
        expect(headers.value('x-api-key'), isNull);
        expect(headers.value('x-goog-upload-offset'), '0');
        expect(headers.value('x-goog-upload-command'), 'upload, finalize');
        expect(headers.contentLength, 3);
      }
    });

    for (final entry in const {
      'a relative': '/relative',
      'an absolute non-HTTP': 'ftp://upload.example/session',
    }.entries) {
      test('should reject ${entry.key} upload URL before opening the source', () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => server.close(force: true));
        server.listen((request) async {
          request.response.headers
            ..set('x-goog-upload-url', entry.value)
            ..set('x-guploader-uploadid', 'upload-2');
          await request.response.close();
        });
        final client = ProviderHttpClient(
          baseUrl: Uri.parse('http://${server.address.address}:${server.port}'),
        );
        addTearDown(client.close);
        var opens = 0;

        final exit = await client
            .sendResumableUpload(
              ProviderResumableUploadRequest(
                startRequest: ProviderHttpRequest(method: 'POST', path: '/start'),
                remoteResourceIdHeader: 'x-guploader-uploadid',
              ),
              UploadSource.stream(
                () {
                  opens++;
                  return Stream.value([1]);
                },
                length: 1,
                filename: 'sample.bin',
                mimeType: 'application/octet-stream',
              ),
              providerId: 'fixture',
              api: 'files',
            )
            .runFutureExit();

        final error = ((exit as Failed<Object?, AiError>).cause as Expected<AiError>).error;
        expect(error, isA<ProtocolError>());
        expect((error as ProtocolError).remoteResourceId, 'upload-2');
        expect(opens, 0);
      });
    }

    test('should cancel a synchronous transfer and preserve a borrowed client', () async {
      final transferStarted = Completer<void>();
      final sourceCancelled = Completer<void>();
      final borrowed = _SynchronousListeningResumableClient(transferStarted);
      addTearDown(borrowed.dispose);
      final client = ProviderHttpClient(
        baseUrl: Uri.parse('https://start.example/'),
        headers: {'x-api-key': 'secret'},
        client: borrowed,
      );
      final runtime = Runtime();
      addTearDown(runtime.close);
      final fiber = runtime.fork(
        client.sendResumableUpload(
          ProviderResumableUploadRequest(
            startRequest: ProviderHttpRequest(method: 'POST', path: 'files'),
            remoteResourceIdHeader: 'x-upload-id',
          ),
          UploadSource.stream(
            () => StreamController<List<int>>(
              onListen: () {},
              onCancel: sourceCancelled.complete,
            ).stream,
            length: 3,
            filename: 'sample.bin',
            mimeType: 'application/octet-stream',
          ),
          providerId: 'fixture',
          api: 'files',
        ),
      );
      await transferStarted.future;

      await client.close().timeout(const Duration(seconds: 2));
      final exit = await fiber.join();

      expect((exit as Failed<Object?, AiError>).cause.containsInterruption, isTrue);
      expect(borrowed.transferAbortSeen, isTrue);
      await sourceCancelled.future.timeout(const Duration(seconds: 2));
      final sibling = await borrowed.get(Uri.parse('https://sibling.example/'));
      expect(sibling.statusCode, 200);
      expect(borrowed.closed, isFalse);
    });
  });

  group('ProviderHttpClient empty success', () {
    test('should retain metadata while decoding an empty successful body as an object', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        request.response
          ..statusCode = 200
          ..headers.set('x-request-id', 'delete-1');
        await request.response.close();
      });
      final client = ProviderHttpClient(
        baseUrl: Uri.parse('http://${server.address.address}:${server.port}'),
      );
      addTearDown(client.close);

      final response = await client
          .sendJson(
            ProviderHttpRequest(method: 'DELETE', path: '/files/file-1'),
            providerId: 'fixture',
            api: 'files',
            modelId: 'files',
            allowEmptySuccess: true,
          )
          .runFuture();

      expect(response.value.toDart(), isEmpty);
      expect(response.payload.json.toDart(), isEmpty);
      expect(response.metadata.statusCode, 200);
      expect(response.metadata.requestId, 'delete-1');
    });
  });
}

final class _SynchronousListeningResumableClient extends http.BaseClient {
  _SynchronousListeningResumableClient(this.transferStarted);

  final Completer<void> transferStarted;
  StreamSubscription<List<int>>? _bodySubscription;
  bool transferAbortSeen = false;
  bool closed = false;
  int requests = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    requests++;
    if (request.url.host == 'sibling.example') {
      return Future.value(http.StreamedResponse(Stream.value(const []), 200));
    }
    if (requests == 1) {
      return Future.value(
        http.StreamedResponse(
          Stream.value(const []),
          200,
          headers: {
            'x-goog-upload-url': 'https://upload.example/session',
            'x-upload-id': 'upload-3',
          },
        ),
      );
    }
    transferStarted.complete();
    final response = Completer<http.StreamedResponse>();
    _bodySubscription = request.finalize().listen((_) {});
    if (request case http.Abortable(:final abortTrigger?)) {
      unawaited(
        abortTrigger.whenComplete(() {
          transferAbortSeen = true;
          if (!response.isCompleted) {
            response.completeError(http.RequestAbortedException(request.url));
          }
        }),
      );
    }
    return response.future;
  }

  @override
  void close() {
    closed = true;
  }

  Future<void> dispose() async {
    await _bodySubscription?.cancel();
  }
}
