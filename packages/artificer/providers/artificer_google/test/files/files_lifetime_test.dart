import 'dart:async';

import 'package:artificer_core/artificer_core.dart';
import 'package:artificer_core/transport.dart';
import 'package:artificer_google/artificer_google.dart';
import 'package:conflux/conflux.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

void main() {
  group('GoogleFilesResource lifetime', () {
    test('should release a resumable transfer on caller interruption', () async {
      final transport = _HoldingTransferClient();
      final provider = GoogleProvider(
        apiKey: 'secret',
        baseUrl: Uri.parse('https://start.example/'),
        httpClient: transport,
      );
      addTearDown(provider.close);
      final runtime = Runtime();
      addTearDown(runtime.close);
      final sourceCancelled = Completer<void>();
      final fiber = runtime.fork(
        provider.files.upload(
          UploadSource.stream(
            () => StreamController<List<int>>(
              onListen: () {},
              onCancel: sourceCancelled.complete,
            ).stream,
            length: 4,
            filename: 'four.bin',
            mimeType: 'application/octet-stream',
          ),
        ),
      );
      await transport.transferStarted.future;

      final exit = await fiber
          .interrupt('caller stopped')
          .timeout(
            const Duration(seconds: 2),
          );

      expect((exit as Failed<Object?, AiError>).cause.containsInterruption, isTrue);
      expect(transport.transferAbortSeen, isTrue);
      await sourceCancelled.future.timeout(const Duration(seconds: 2));
      expect(transport.methods, ['POST', 'POST']);
    });

    test(
      'should await and release a late initiation response without opening the source',
      () async {
        final transport = _LateInitiationClient();
        final provider = GoogleProvider(
          apiKey: 'secret',
          baseUrl: Uri.parse('https://start.example/'),
          httpClient: transport,
        );
        final runtime = Runtime();
        addTearDown(runtime.close);
        var opens = 0;
        final fiber = runtime.fork(
          provider.files.upload(
            UploadSource.stream(
              () {
                opens++;
                return Stream.value([1]);
              },
              length: 1,
              filename: 'one.bin',
              mimeType: 'application/octet-stream',
            ),
          ),
        );
        await transport.started.future;

        var closed = false;
        final closing = provider.close().whenComplete(() => closed = true);
        await transport.abortSeen.future;
        await Future<void>.delayed(Duration.zero);
        expect(closed, isFalse);
        transport.completeLateResponse();
        await closing.timeout(const Duration(seconds: 2));
        final exit = await fiber.join();

        expect((exit as Failed<Object?, AiError>).cause.containsInterruption, isTrue);
        expect(opens, 0);
        expect(transport.lateBodyCancelled, isTrue);
        expect(transport.methods, ['POST']);
        expect(transport.closed, isFalse);
      },
    );

    test('should cancel the source while transferring a known upload session', () async {
      final transport = _HoldingTransferClient();
      final provider = GoogleProvider(
        apiKey: 'secret',
        baseUrl: Uri.parse('https://start.example/'),
        httpClient: transport,
      );
      final runtime = Runtime();
      addTearDown(runtime.close);
      final sourceCancelled = Completer<void>();
      final fiber = runtime.fork(
        provider.files.upload(
          UploadSource.stream(
            () => StreamController<List<int>>(
              onListen: () {},
              onCancel: sourceCancelled.complete,
            ).stream,
            length: 4,
            filename: 'four.bin',
            mimeType: 'application/octet-stream',
          ),
        ),
      );
      await transport.transferStarted.future;

      await provider.close().timeout(const Duration(seconds: 2));
      final exit = await fiber.join();

      expect((exit as Failed<Object?, AiError>).cause.containsInterruption, isTrue);
      expect(transport.transferAbortSeen, isTrue);
      await sourceCancelled.future.timeout(const Duration(seconds: 2));
      expect(transport.uploadId, 'upload-known-1');
      expect(transport.methods, ['POST', 'POST']);
      expect(transport.closed, isFalse);
    });

    test('should cancel a final response body after all upload bytes were sent', () async {
      final transport = _HoldingFinalResponseClient();
      final provider = GoogleProvider(
        apiKey: 'secret',
        baseUrl: Uri.parse('https://start.example/'),
        httpClient: transport,
      );
      final runtime = Runtime();
      addTearDown(runtime.close);
      final fiber = runtime.fork(
        provider.files.upload(
          UploadSource.bytes(
            [1, 2, 3],
            filename: 'three.bin',
            mimeType: 'application/octet-stream',
          ),
        ),
      );
      await transport.finalResponseListening.future;

      await provider.close().timeout(const Duration(seconds: 2));
      final exit = await fiber.join();

      expect((exit as Failed<Object?, AiError>).cause.containsInterruption, isTrue);
      expect(transport.uploadedBytes, [1, 2, 3]);
      expect(transport.finalResponseCancelled, isTrue);
      expect(transport.methods, ['POST', 'POST']);
      expect(transport.closed, isFalse);
    });
  });
}

final class _LateInitiationClient extends http.BaseClient {
  final started = Completer<void>();
  final abortSeen = Completer<void>();
  final _response = Completer<http.StreamedResponse>();
  final methods = <String>[];
  bool lateBodyCancelled = false;
  bool closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    methods.add(request.method);
    started.complete();
    if (request case http.Abortable(:final abortTrigger?)) {
      unawaited(abortTrigger.whenComplete(abortSeen.complete));
    }
    return _response.future;
  }

  void completeLateResponse() {
    _response.complete(
      http.StreamedResponse(
        StreamController<List<int>>(
          onListen: () {},
          onCancel: () => lateBodyCancelled = true,
        ).stream,
        200,
        headers: {
          'x-goog-upload-url': 'https://upload.example/session',
          'x-guploader-uploadid': 'upload-late-1',
        },
      ),
    );
  }

  @override
  void close() {
    closed = true;
  }
}

final class _HoldingTransferClient extends http.BaseClient {
  final transferStarted = Completer<void>();
  final methods = <String>[];
  bool transferAbortSeen = false;
  bool closed = false;
  String? uploadId;
  int requests = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    methods.add(request.method);
    requests++;
    if (requests == 1) {
      uploadId = 'upload-known-1';
      return Future.value(
        http.StreamedResponse(
          Stream.value(const []),
          200,
          headers: {
            'x-goog-upload-url': 'https://upload.example/session',
            'x-guploader-uploadid': uploadId!,
          },
        ),
      );
    }
    transferStarted.complete();
    final response = Completer<http.StreamedResponse>();
    final body = request.finalize().listen((_) {});
    if (request case http.Abortable(:final abortTrigger?)) {
      unawaited(
        abortTrigger.whenComplete(() async {
          transferAbortSeen = true;
          await body.cancel();
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
}

final class _HoldingFinalResponseClient extends http.BaseClient {
  final finalResponseListening = Completer<void>();
  final methods = <String>[];
  final uploadedBytes = <int>[];
  bool finalResponseCancelled = false;
  bool closed = false;
  int requests = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    methods.add(request.method);
    requests++;
    if (requests == 1) {
      return http.StreamedResponse(
        Stream.value(const []),
        200,
        headers: {
          'x-goog-upload-url': 'https://upload.example/session',
          'x-guploader-uploadid': 'upload-known-2',
        },
      );
    }
    uploadedBytes.addAll(await request.finalize().expand((chunk) => chunk).toList());
    return http.StreamedResponse(
      StreamController<List<int>>(
        onListen: finalResponseListening.complete,
        onCancel: () => finalResponseCancelled = true,
      ).stream,
      200,
    );
  }

  @override
  void close() {
    closed = true;
  }
}
