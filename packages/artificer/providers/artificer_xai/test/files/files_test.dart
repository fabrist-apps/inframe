import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:artificer_core/artificer_core.dart';
import 'package:artificer_core/transport.dart';
import 'package:artificer_xai/artificer_xai.dart';
import 'package:conflux/conflux.dart';
import 'package:test/test.dart';

void main() {
  test('files are uploaded, listed, read, downloaded, and deleted explicitly', () async {
    final requests = <String>[];
    final uploadBodies = <List<int>>[];
    final contentTypes = <String>[];
    var opens = 0;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      requests.add('${request.method} ${request.uri}');
      if (request.method == 'POST') {
        contentTypes.add(request.headers.value('content-type')!);
        uploadBodies.add(
          await request.fold<List<int>>(<int>[], (bytes, chunk) => bytes..addAll(chunk)),
        );
        _json(request, _file);
      } else if (request.uri.path.endsWith('/content')) {
        request.response
          ..headers.contentType = ContentType.binary
          ..add([0, 1])
          ..add([2, 255]);
      } else if (request.method == 'DELETE') {
        _json(request, {'id': 'file_1', 'object': 'file', 'deleted': true, 'future': 1});
      } else if (request.uri.path == '/v1/files') {
        _json(request, {
          'data': [_file],
          'pagination_token': 'next page',
          'future_page': true,
        });
      } else {
        _json(request, _file);
      }
      await request.response.close();
    });
    final provider = _provider(server);
    addTearDown(provider.close);
    final source = UploadSource.stream(
      () {
        opens++;
        return Stream.value([0, 1, 2, 255]);
      },
      length: 4,
      filename: 'data.bin',
      mimeType: 'application/octet-stream',
    );
    final upload = provider.files.create(source, expiresAfter: 3600, purpose: 'assistants');

    final uploaded = await upload.runFuture();
    await upload.runFuture();
    final page = await provider.files
        .list(
          limit: 10,
          order: XaiFileOrder.ascending,
          sortBy: XaiFileSortBy.filename,
          paginationToken: 'previous page',
          filter: 'name:"data"',
        )
        .runFuture();
    final retrieved = await provider.files.retrieve('file/1').runFuture();
    final downloaded = await provider.files
        .content('file/1', format: XaiFileContentFormat.original)
        .runCollect()
        .runFuture();
    final deleted = await provider.files.delete('file/1').runFuture();

    expect(opens, 2);
    expect(uploaded.value.id, 'file_1');
    expect(uploaded.value.expiresAt, 456);
    expect(uploaded.value.extensions.toDart()['future'], {'keep': true});
    expect(uploaded.value.asResponseSource(mimeType: 'application/octet-stream').api, 'responses');
    expect(page.value.paginationToken, 'next page');
    expect(page.value.extensions.toDart()['future_page'], isTrue);
    expect(retrieved.value.purpose, 'assistants');
    expect(downloaded, everyElement(isA<Uint8List>()));
    expect(downloaded.expand((chunk) => chunk), [0, 1, 2, 255]);
    expect(deleted.value.deleted, isTrue);
    expect(requests, [
      'POST /v1/files',
      'POST /v1/files',
      'GET /v1/files?limit=10&order=asc&sort_by=filename&pagination_token=previous+page&filter=name%3A%22data%22',
      'GET /v1/files/file%2F1',
      'GET /v1/files/file%2F1/content?format=original',
      'DELETE /v1/files/file%2F1',
    ]);
    expect(contentTypes, everyElement(startsWith('multipart/form-data; boundary=')));
    for (final body in uploadBodies) {
      final text = latin1.decode(body);
      final expiry = text.indexOf('name="expires_after"\r\n\r\n3600');
      final purpose = text.indexOf('name="purpose"\r\n\r\nassistants');
      final file = text.indexOf('name="file"; filename="data.bin"');
      expect(expiry, greaterThanOrEqualTo(0));
      expect(purpose, greaterThan(expiry));
      expect(file, greaterThan(purpose));
      expect(text, contains('Content-Type: application/octet-stream'));
      expect(body, containsAllInOrder([0, 1, 2, 255]));
    }
  });

  test('invalid upload and bounded binary download fail through typed contracts', () async {
    final validationProvider = XaiProvider(apiKey: 'secret');
    addTearDown(validationProvider.close);
    expect(
      () => validationProvider.files.create(
        UploadSource.bytes([1], filename: 'a', mimeType: 'application/octet-stream'),
        expiresAfter: 3599,
      ),
      throwsArgumentError,
    );
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      await request.drain<void>();
      request.response
        ..headers.contentType = ContentType.binary
        ..add(List<int>.generate(32, (index) => index));
      await request.response.close();
    });
    final provider = _provider(server);
    addTearDown(provider.close);

    final exit = await provider.files
        .content('file_1', maxResponseBytes: 8)
        .runCollect()
        .runFutureExit();

    expect(exit, _failedWith<ResponseLimitError>());
  });

  test('early download termination leaves the provider usable', () async {
    var requestCount = 0;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      requestCount++;
      if (request.uri.path.endsWith('/content')) {
        request.response
          ..headers.contentType = ContentType.binary
          ..add([1, 2]);
      } else {
        _json(request, _file);
      }
      await request.response.close();
    });
    final provider = _provider(server);
    addTearDown(provider.close);

    final chunks = await provider.files.content('file_1').take(1).runCollect().runFuture();
    final metadata = await provider.files.retrieve('file_1').runFuture();

    expect(chunks.expand((chunk) => chunk), [1, 2]);
    expect(metadata.value.id, 'file_1');
    expect(requestCount, 2);
  });

  test('local upload and download cancellation never requests remote deletion', () async {
    final uploadStarted = Completer<void>();
    final downloadStarted = Completer<void>();
    final requests = <String>[];
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      requests.add('${request.method} ${request.uri.path}');
      if (request.method == 'POST') {
        uploadStarted.complete();
      } else {
        downloadStarted.complete();
      }
    });
    final provider = _provider(server);
    addTearDown(provider.close);
    final runtime = Runtime();
    addTearDown(runtime.close);
    final source = StreamController<List<int>>();
    addTearDown(source.close);

    final upload = runtime.fork(
      provider.files.create(
        UploadSource.stream(
          () => source.stream,
          length: 2,
          filename: 'data.bin',
          mimeType: 'application/octet-stream',
        ),
      ),
    );
    source.add([1]);
    await uploadStarted.future;
    final uploadExit = await upload.interrupt('cancel upload').timeout(const Duration(seconds: 2));
    final download = runtime.fork(provider.files.content('file_1').runCollect());
    await downloadStarted.future;
    final downloadExit = await download
        .interrupt('cancel download')
        .timeout(const Duration(seconds: 2));

    expect((uploadExit as Failed<Object?, AiError>).cause.containsInterruption, isTrue);
    expect((downloadExit as Failed<Object?, AiError>).cause.containsInterruption, isTrue);
    expect(requests, ['POST /v1/files', 'GET /v1/files/file_1/content']);
  });
}

Matcher _failedWith<E extends AiError>() => isA<Failed<Object?, AiError>>().having(
  (failure) => (failure.cause as Expected<AiError>).error,
  'error',
  isA<E>(),
);

void _json(HttpRequest request, Map<String, Object?> value) {
  request.response
    ..headers.contentType = ContentType.json
    ..headers.set('x-request-id', 'file-request')
    ..write(jsonEncode(value));
}

XaiProvider _provider(HttpServer server) => XaiProvider(
  apiKey: 'secret',
  baseUrl: Uri.parse('http://${server.address.address}:${server.port}/v1/'),
);

const _file = <String, Object?>{
  'id': 'file_1',
  'object': 'file',
  'bytes': 4,
  'created_at': 123,
  'expires_at': 456,
  'filename': 'data.bin',
  'purpose': 'assistants',
  'future': {'keep': true},
};
