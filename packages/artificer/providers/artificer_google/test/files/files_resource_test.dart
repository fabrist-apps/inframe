import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:artificer_core/artificer_core.dart';
import 'package:artificer_core/json.dart';
import 'package:artificer_core/transport.dart';
import 'package:artificer_google/artificer_google.dart';
import 'package:conflux/conflux.dart';
import 'package:test/test.dart';

void main() {
  group('GoogleFilesResource upload', () {
    test('should run exact resumable exchanges lazily with a fresh source each time', () async {
      final uploadedBytes = <List<int>>[];
      final uploadServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => uploadServer.close(force: true));
      uploadServer.listen((request) async {
        expect(request.method, 'POST');
        expect(request.uri.path, '/upload-session');
        expect(request.headers.value('x-goog-api-key'), isNull);
        expect(request.headers.value('x-goog-upload-offset'), '0');
        expect(request.headers.value('x-goog-upload-command'), 'upload, finalize');
        uploadedBytes.add(
          await request.fold(<int>[], (bytes, chunk) => bytes..addAll(chunk)),
        );
        _json(request, {
          'file': _file(
            state: 'PROCESSING',
            extra: {
              'futureFile': {'keep': true},
            },
          ),
          'futureUpload': true,
        });
        await request.response.close();
      });
      final startBodies = <Map<String, Object?>>[];
      final startServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => startServer.close(force: true));
      startServer.listen((request) async {
        expect(request.method, 'POST');
        expect(request.uri.path, '/upload/v1beta/files');
        expect(request.headers.value('x-goog-api-key'), 'secret');
        expect(request.headers.value('x-goog-upload-protocol'), 'resumable');
        expect(request.headers.value('x-goog-upload-command'), 'start');
        expect(request.headers.value('x-goog-upload-header-content-length'), '3');
        expect(request.headers.value('x-goog-upload-header-content-type'), 'text/plain');
        expect(request.headers.contentType?.mimeType, 'application/json');
        startBodies.add(
          jsonDecode(await utf8.decoder.bind(request).join()) as Map<String, Object?>,
        );
        request.response.headers
          ..set(
            'x-goog-upload-url',
            'http://${uploadServer.address.address}:${uploadServer.port}/upload-session',
          )
          ..set('x-guploader-uploadid', 'upload-1');
        await request.response.close();
      });
      final provider = GoogleProvider(
        apiKey: 'secret',
        baseUrl: Uri.parse('http://${startServer.address.address}:${startServer.port}'),
      );
      addTearDown(provider.close);
      final files = provider.files;
      var opens = 0;
      final operation = files.upload(
        UploadSource.stream(
          () {
            opens++;
            return Stream.value([1, 2, 3]);
          },
          length: 3,
          filename: 'source.txt',
          mimeType: 'text/plain',
        ),
        displayName: 'Readable name',
      );

      expect(opens, 0);
      final first = await operation.runFuture();
      final second = await operation.runFuture();

      expect(opens, 2);
      expect(uploadedBytes, [
        [1, 2, 3],
        [1, 2, 3],
      ]);
      expect(startBodies, [
        {
          'file': {'display_name': 'Readable name'},
        },
        {
          'file': {'display_name': 'Readable name'},
        },
      ]);
      expect(first.value.name, 'files/file-1');
      expect(first.value.state, GoogleFileState.processing);
      expect(first.value.extensions.toDart()['futureFile'], {'keep': true});
      expect(first.payload.json.toDart()['futureUpload'], isTrue);
      expect(second.value.state, GoogleFileState.processing);
    });

    test('should copy byte sources and default the display name to the filename', () async {
      final sourceBytes = [4, 5, 6];
      final source = UploadSource.bytes(
        sourceBytes,
        filename: 'copied.bin',
        mimeType: 'application/octet-stream',
      );
      sourceBytes[0] = 9;
      late Map<String, Object?> startBody;
      late List<int> uploadBody;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        if (request.uri.path == '/upload/v1beta/files') {
          startBody = jsonDecode(await utf8.decoder.bind(request).join()) as Map<String, Object?>;
          request.response.headers.set(
            'x-goog-upload-url',
            'http://${server.address.address}:${server.port}/session',
          );
        } else {
          uploadBody = await request.fold(<int>[], (bytes, chunk) => bytes..addAll(chunk));
          _json(request, {'file': _file(state: 'ACTIVE')});
        }
        await request.response.close();
      });
      final provider = GoogleProvider(
        apiKey: 'secret',
        baseUrl: Uri.parse('http://${server.address.address}:${server.port}'),
      );
      addTearDown(provider.close);

      final response = await provider.files.upload(source).runFuture();

      expect(startBody, {
        'file': {'display_name': 'copied.bin'},
      });
      expect(uploadBody, [4, 5, 6]);
      expect(response.value.state, GoogleFileState.active);
    });

    test('should retain an upload ID on transfer failure without retry or deletion', () async {
      final requests = <String>[];
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        requests.add('${request.method} ${request.uri.path}');
        if (request.uri.path == '/upload/v1beta/files') {
          await request.drain<void>();
          request.response.headers
            ..set(
              'x-goog-upload-url',
              'http://${server.address.address}:${server.port}/session',
            )
            ..set('x-guploader-uploadid', 'upload-partial-1');
        } else {
          await request.drain<void>();
          request.response
            ..statusCode = 503
            ..write('{"error":{"code":"unavailable","message":"later"}}');
        }
        await request.response.close();
      });
      final provider = GoogleProvider(
        apiKey: 'secret',
        baseUrl: Uri.parse('http://${server.address.address}:${server.port}'),
      );
      addTearDown(provider.close);

      final exit = await provider.files
          .upload(
            UploadSource.bytes(
              [1],
              filename: 'one.bin',
              mimeType: 'application/octet-stream',
            ),
          )
          .runFutureExit();

      final error = ((exit as Failed<Object?, AiError>).cause as Expected<AiError>).error;
      expect((error as ProviderError).remoteResourceId, 'upload-partial-1');
      expect(requests, ['POST /upload/v1beta/files', 'POST /session']);
    });
  });

  group('GoogleFilesResource lifecycle', () {
    test('should list one page, retrieve one status, and accept an empty delete', () async {
      final requests = <String>[];
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        requests.add('${request.method} ${request.uri}');
        switch ((request.method, request.uri.path)) {
          case ('GET', '/v1beta/files'):
            _json(request, {
              'files': [
                _file(state: 'PROCESSING'),
                _file(name: 'files/file-2', state: 'ACTIVE'),
                _file(name: 'files/file-3', state: 'FAILED', withError: true),
                _file(name: 'files/file-4', state: 'QUEUED_FOR_SCAN'),
              ],
              'nextPageToken': 'next page',
              'futurePage': true,
            });
          case ('GET', '/v1beta/files/file-3'):
            _json(request, _file(name: 'files/file-3', state: 'FAILED', withError: true));
          case ('DELETE', '/v1beta/files/file-3'):
            request.response.headers.set('x-request-id', 'delete-1');
          case _:
            request.response.statusCode = 404;
            request.response.write('{"error":{"message":"unexpected"}}');
        }
        await request.response.close();
      });
      final provider = GoogleProvider(
        apiKey: 'secret',
        baseUrl: Uri.parse('http://${server.address.address}:${server.port}'),
      );
      addTearDown(provider.close);
      final files = provider.files;

      final page = await files.list(pageSize: 4, pageToken: 'current page').runFuture();
      final failed = await files.retrieve('files/file-3').runFuture();
      final deleted = await files.delete('files/file-3').runFuture();

      expect(page.value.files.map((file) => file.state), [
        GoogleFileState.processing,
        GoogleFileState.active,
        GoogleFileState.failed,
        const TypeMatcher<GoogleFileState>(),
      ]);
      final unknown = page.value.files.last.state!;
      expect(unknown.value, 'QUEUED_FOR_SCAN');
      expect(unknown.isKnown, isFalse);
      expect(page.value.nextPageToken, 'next page');
      expect(page.value.extensions.toDart()['futurePage'], isTrue);
      expect(failed.value.error?.code, 9);
      expect(failed.value.error?.message, 'processing failed');
      expect(failed.value.error?.details.single.toDart(), {'reason': 'fixture'});
      expect(failed.value.error?.extensions.toDart()['futureStatus'], isTrue);
      expect(deleted.value.toDart(), isEmpty);
      expect(deleted.metadata.requestId, 'delete-1');
      expect(requests, [
        'GET /v1beta/files?pageSize=4&pageToken=current+page',
        'GET /v1beta/files/file-3',
        'DELETE /v1beta/files/file-3',
      ]);
    });

    test('should create a tagged Google media source from a ready file', () {
      final file = GoogleFile.fromJson(
        JsonObject.fromDart(_file(state: 'ACTIVE')),
      );

      final source = file.asMediaSource();

      expect(source.providerId, 'google');
      expect(source.api, 'files');
      expect(source.reference, 'https://generativelanguage.googleapis.com/v1beta/files/file-1');
      expect(source.mimeType, 'text/plain');
    });

    test('should report a non-object page entry as a protocol error', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        _json(request, {
          'files': ['not-a-file'],
        });
        await request.response.close();
      });
      final provider = GoogleProvider(
        apiKey: 'secret',
        baseUrl: Uri.parse('http://${server.address.address}:${server.port}'),
      );
      addTearDown(provider.close);

      final exit = await provider.files.list().runFutureExit();

      final error = ((exit as Failed<Object?, AiError>).cause as Expected<AiError>).error;
      expect(error, isA<ProtocolError>());
      expect(error.message, 'files must contain objects.');
    });
  });
}

Map<String, Object?> _file({
  required String state,
  String name = 'files/file-1',
  bool withError = false,
  Map<String, Object?> extra = const {},
}) => {
  'name': name,
  'displayName': 'Fixture',
  'mimeType': 'text/plain',
  'sizeBytes': '3',
  'createTime': '2026-09-12T00:00:00Z',
  'updateTime': '2026-09-12T00:00:01Z',
  'expirationTime': '2026-09-14T00:00:00Z',
  'sha256Hash': 'AQID',
  'uri': 'https://generativelanguage.googleapis.com/v1beta/$name',
  'downloadUri': 'https://download.example/$name',
  'state': state,
  'source': 'UPLOADED',
  if (withError)
    'error': {
      'code': 9,
      'message': 'processing failed',
      'details': [
        {'reason': 'fixture'},
      ],
      'futureStatus': true,
    },
  'videoMetadata': {'videoDuration': '3s', 'futureVideo': true},
  ...extra,
};

void _json(HttpRequest request, Map<String, Object?> body) {
  request.response
    ..headers.contentType = ContentType.json
    ..write(jsonEncode(body));
}
