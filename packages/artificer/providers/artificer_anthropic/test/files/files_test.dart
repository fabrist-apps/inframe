import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:artificer_anthropic/artificer_anthropic.dart';
import 'package:artificer_anthropic/src/decode.dart';
import 'package:artificer_core/artificer_core.dart';
import 'package:artificer_core/json.dart';
import 'package:artificer_core/transport.dart';
import 'package:conflux/conflux.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

void main() {
  group('AnthropicFilesResource', () {
    test(
      'should upload, list, retrieve, download, and delete only when executed',
      () async {
        final requests = <String>[];
        final requestHeaders = <Map<String, String?>>[];
        List<int>? uploadBody;
        int? uploadContentLength;
        String? uploadContentType;
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => server.close(force: true));
        server.listen((request) async {
          requests.add('${request.method} ${request.uri}');
          requestHeaders.add({
            'x-api-key': request.headers.value('x-api-key'),
            'anthropic-version': request.headers.value('anthropic-version'),
            'anthropic-beta': request.headers.value('anthropic-beta'),
            'anthropic-workspace-id': request.headers.value('anthropic-workspace-id'),
            'accept': request.headers.value('accept'),
          });
          if (request.method == 'POST') {
            uploadContentLength = request.headers.contentLength;
            uploadContentType = request.headers.value('content-type');
            uploadBody = await request.fold<List<int>>(
              <int>[],
              (bytes, chunk) => bytes..addAll(chunk),
            );
            _json(request, _file);
          } else if (request.uri.path.endsWith('/content')) {
            request.response
              ..headers.contentType = ContentType.binary
              ..add([0, 1])
              ..add([2, 255]);
          } else if (request.method == 'DELETE') {
            _json(request, {
              'id': 'file_1',
              'type': 'file_deleted',
              'future_delete': true,
            });
          } else if (request.uri.path == '/v1/files') {
            _json(request, {
              'data': [_file],
              'next_page': 'page_2',
              'future_page': {'keep': true},
            });
          } else {
            _json(request, _file);
          }
          await request.response.close();
        });
        final provider = AnthropicProvider(
          apiKey: 'secret',
          baseUrl: _baseUri(server),
          betaFeatures: const [AnthropicBeta.filesApi20250414],
          workspaceId: 'workspace_1',
        );
        addTearDown(provider.close);
        final files = provider.files;
        var sourceOpens = 0;
        final source = UploadSource.stream(
          () {
            sourceOpens++;
            return Stream.value([0, 1, 2, 255]);
          },
          length: 4,
          filename: 'data.bin',
          mimeType: 'application/octet-stream',
        );
        final upload = files.upload(source, expiresInSeconds: 3600);

        expect(sourceOpens, 0);
        expect(requests, isEmpty);

        final uploaded = await upload.runFuture();
        final page = await files.list(limit: 2, page: 'page one').runFuture();
        final retrieved = await files.retrieveMetadata('file_1').runFuture();
        final downloaded = await files.download('file_1').runCollect().runFuture();
        final deleted = await files.delete('file_1').runFuture();

        expect(sourceOpens, 1);
        expect(uploaded.value.id, 'file_1');
        expect(uploaded.value.createdAt, '2026-09-12T10:30:00Z');
        expect(uploaded.value.downloadable, isTrue);
        expect(uploaded.value.expiresAt, '2026-09-12T11:30:00Z');
        expect(uploaded.value.extensions.toDart()['future'], {'keep': true});
        final messageSource = uploaded.value.asMessageSource();
        expect(messageSource.providerId, 'anthropic');
        expect(messageSource.api, 'messages');
        expect(messageSource.reference, 'file_1');
        expect(messageSource.mimeType, 'application/octet-stream');
        expect(page.value.data.single.id, 'file_1');
        expect(page.value.nextPage, 'page_2');
        expect(page.value.extensions.toDart()['future_page'], {'keep': true});
        expect(retrieved.value.filename, 'data.bin');
        expect(downloaded.expand((chunk) => chunk), [0, 1, 2, 255]);
        expect(deleted.value.type, 'file_deleted');
        expect(deleted.value.extensions.toDart()['future_delete'], isTrue);
        expect(requests, [
          'POST /v1/files',
          'GET /v1/files?limit=2&page=page+one',
          'GET /v1/files/file_1',
          'GET /v1/files/file_1/content',
          'DELETE /v1/files/file_1',
        ]);
        expect(
          requestHeaders,
          everyElement(
            allOf(
              containsPair('x-api-key', 'secret'),
              containsPair('anthropic-version', '2023-06-01'),
            ),
          ),
        );
        expect(
          requestHeaders,
          everyElement(
            allOf(
              containsPair('anthropic-beta', 'files-api-2025-04-14'),
              containsPair('anthropic-workspace-id', 'workspace_1'),
            ),
          ),
        );
        expect(requestHeaders[3]['accept'], 'application/binary');
        expect(uploadContentType, startsWith('multipart/form-data; boundary='));
        expect(uploadContentLength, uploadBody!.length);
        final uploadText = latin1.decode(uploadBody!);
        expect(uploadText, contains('name="expires_in_seconds"\r\n\r\n3600'));
        expect(uploadText, contains('name="file"; filename="data.bin"'));
        expect(uploadText, contains('Content-Type: application/octet-stream'));
        expect(uploadBody, containsAllInOrder([0, 1, 2, 255]));
      },
    );

    test('should request only the selected IDs as one page', () async {
      Uri? requestedUri;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        requestedUri = request.uri;
        await request.drain<void>();
        _json(request, {'data': <Object?>[], 'next_page': null});
        await request.response.close();
      });
      final client = _client(server);
      addTearDown(client.close);
      final files = AnthropicFilesResource(client);

      final page = await files.list(ids: ['file_1', 'file two', 'file_1']).runFuture();

      expect(page.value.data, isEmpty);
      expect(page.value.nextPage, isNull);
      expect(requestedUri?.queryParametersAll['ids'], ['file_1', 'file two']);
    });

    test(
      'should preserve a native download restriction and keep a borrowed client usable',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => server.close(force: true));
        server.listen((request) async {
          await request.drain<void>();
          if (request.uri.path.endsWith('/content')) {
            request.response
              ..statusCode = HttpStatus.forbidden
              ..headers.set('x-request-id', 'request_restricted')
              ..headers.set('retry-after', '7');
            _json(request, {
              'type': 'error',
              'error': {
                'code': 'permission_error',
                'message': 'This file is not downloadable.',
              },
            });
          } else if (request.uri.path == '/health') {
            request.response.write('ok');
          } else {
            _json(request, _file);
          }
          await request.response.close();
        });
        final borrowed = http.Client();
        addTearDown(borrowed.close);
        final client = _client(server, borrowed: borrowed);
        final files = AnthropicFilesResource(client);

        final exit = await files.download('restricted').runCollect().runFutureExit();

        final error = _expectedError(exit) as ProviderError;
        expect(error.statusCode, HttpStatus.forbidden);
        expect(error.code, 'permission_error');
        expect(error.message, 'This file is not downloadable.');
        expect(error.requestId, 'request_restricted');
        expect(error.retryAfter, const Duration(seconds: 7));
        expect(error.details?.toDart(), containsPair('type', 'error'));

        expect((await files.retrieveMetadata('file_1').runFuture()).value.id, 'file_1');
        await client.close();
        final health = await borrowed.get(_baseUri(server).resolve('../health'));
        expect(health.body, 'ok');
      },
    );

    test('should release a failed upload source without retrying or deleting', () async {
      final methods = <String>[];
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        methods.add(request.method);
        try {
          await request.drain<void>();
        } on Object {
          // The client intentionally terminates the request after the source fails.
        }
        try {
          _json(request, _file);
          await request.response.close();
        } on Object {
          // The response socket may already be closed by the failed upload.
        }
      });
      final client = _client(server);
      addTearDown(client.close);
      final files = AnthropicFilesResource(client);
      var sourceOpens = 0;
      var sourceCancelled = false;
      late final StreamController<List<int>> sourceController;
      sourceController = StreamController<List<int>>(
        onListen: () {
          sourceController
            ..add([1])
            ..addError(StateError('source failed'));
        },
        onCancel: () => sourceCancelled = true,
      );
      final source = UploadSource.stream(
        () {
          sourceOpens++;
          return sourceController.stream;
        },
        length: 2,
        filename: 'broken.bin',
        mimeType: 'application/octet-stream',
      );

      final exit = await files.upload(source).runFutureExit();

      expect(exit, _failedWith<TransportError>());
      expect(sourceOpens, 1);
      expect(sourceCancelled, isTrue);
      expect(methods.where((method) => method == 'POST').length, lessThanOrEqualTo(1));
      expect(methods, isNot(contains('DELETE')));
    });

    test('should reject invalid pagination and expiration before I/O', () {
      final client = ProviderHttpClient(baseUrl: Uri.parse('https://example.test/v1/'));
      addTearDown(client.close);
      final files = AnthropicFilesResource(client);
      final source = UploadSource.bytes(
        [1],
        filename: 'one.bin',
        mimeType: 'application/octet-stream',
      );

      expect(() => files.upload(source, expiresInSeconds: 3599), throwsArgumentError);
      expect(() => files.list(limit: 0), throwsArgumentError);
      expect(() => files.list(ids: []), throwsArgumentError);
      expect(() => files.list(ids: ['file_1'], limit: 1), throwsArgumentError);
      expect(() => files.list(page: ''), throwsArgumentError);
      expect(() => files.retrieveMetadata(''), throwsArgumentError);
    });

    test('should turn malformed file pages into protocol errors', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        await request.drain<void>();
        _json(request, {
          'data': [1],
          'next_page': null,
        });
        await request.response.close();
      });
      final client = _client(server);
      addTearDown(client.close);

      final exit = await AnthropicFilesResource(client).list().runFutureExit();

      expect(exit, _failedWith<ProtocolError>());
    });
  });

  group('AnthropicFileMetadata', () {
    test('should reject malformed optional native fields', () {
      final malformed = Map<String, Object?>.from(_file)..['downloadable'] = 'yes';

      expect(
        () => AnthropicFileMetadata.fromJson(JsonObject(malformed)),
        throwsFormatException,
      );
    });
  });

  group('AnthropicFilePage', () {
    test('should require next_page while accepting an explicit null', () async {
      final withNull = AnthropicFilePage.fromJson(
        JsonObject({'data': <Object?>[], 'next_page': null}),
      );
      final missingNextPage = JsonObject({'data': <Object?>[]});
      final response = NativeResponse(
        value: missingNextPage,
        payload: NativePayload(
          providerId: 'anthropic',
          api: 'files',
          modelId: 'files',
          json: missingNextPage,
        ),
        metadata: ResponseMetadata(statusCode: HttpStatus.ok),
      );

      final exit = await decodeNativeResponse(
        response,
        AnthropicFilePage.fromJson,
      ).runFutureExit();

      expect(withNull.nextPage, isNull);
      expect(exit, _failedWith<ProtocolError>());
    });
  });

  group('AnthropicDeletedFile', () {
    test('should preserve null type and reject other non-null discriminators', () {
      final withoutType = AnthropicDeletedFile.fromJson(
        JsonObject({'id': 'file_1', 'type': null}),
      );

      expect(withoutType.type, isNull);
      expect(
        () => AnthropicDeletedFile.fromJson(
          JsonObject({'id': 'file_1', 'type': 'future_deleted'}),
        ),
        throwsFormatException,
      );
    });
  });
}

Matcher _failedWith<E extends AiError>() => isA<Failed<Object?, AiError>>().having(
  _expectedError,
  'error',
  isA<E>(),
);

AiError _expectedError(Exit<Object?, AiError> exit) =>
    ((exit as Failed<Object?, AiError>).cause as Expected<AiError>).error;

void _json(HttpRequest request, Map<String, Object?> value) {
  request.response
    ..headers.contentType = ContentType.json
    ..write(jsonEncode(value));
}

ProviderHttpClient _client(HttpServer server, {http.Client? borrowed}) => ProviderHttpClient(
  baseUrl: _baseUri(server),
  client: borrowed,
  headers: const {
    'x-api-key': 'secret',
    'anthropic-version': '2023-06-01',
    'anthropic-beta': 'files-api-2025-04-14',
    'anthropic-workspace-id': 'workspace_1',
  },
);

Uri _baseUri(HttpServer server) => Uri.parse('http://${server.address.address}:${server.port}/v1/');

const _file = <String, Object?>{
  'id': 'file_1',
  'created_at': '2026-09-12T10:30:00Z',
  'filename': 'data.bin',
  'mime_type': 'application/octet-stream',
  'size_bytes': 4,
  'type': 'file',
  'downloadable': true,
  'expires_at': '2026-09-12T11:30:00Z',
  'future': {'keep': true},
};
