import 'dart:convert';
import 'dart:io';

import 'package:artificer_core/artificer_core.dart';
import 'package:artificer_core/json.dart';
import 'package:artificer_core/transport.dart';
import 'package:artificer_openai/artificer_openai.dart';
import 'package:conflux/conflux.dart';
import 'package:test/test.dart';

void main() {
  test('files are uploaded, listed, read, downloaded, and deleted only explicitly', () async {
    final requests = <String>[];
    List<int>? uploadBody;
    String? uploadContentType;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      requests.add('${request.method} ${request.uri}');
      if (request.method == 'POST') {
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
        _json(request, {'id': 'file_1', 'object': 'file', 'deleted': true, 'future': 1});
      } else if (request.uri.path == '/v1/files') {
        _json(request, {
          'object': 'list',
          'data': [_file],
          'first_id': 'file_1',
          'last_id': 'file_1',
          'has_more': false,
          'future_page': true,
        });
      } else {
        _json(request, _file);
      }
      await request.response.close();
    });
    final provider = _provider(server);
    final source = UploadSource.bytes(
      [0, 1, 2, 255],
      filename: 'data.bin',
      mimeType: 'application/octet-stream',
    );

    final uploaded = await provider.files
        .create(source, purpose: OpenAIFilePurpose.userData)
        .runFuture();
    final page = await provider.files
        .list(
          purpose: OpenAIFilePurpose.userData,
          limit: 10,
          order: OpenAIListOrder.ascending,
          after: 'file before',
        )
        .runFuture();
    final retrieved = await provider.files.retrieve('file_1').runFuture();
    final downloaded = await provider.files.content('file_1').runCollect().runFuture();
    final deleted = await provider.files.delete('file_1').runFuture();
    await provider.close();

    expect(uploaded.value.id, 'file_1');
    expect(uploaded.value.status, OpenAIFileStatus.processed);
    expect(uploaded.value.extensions.toDart()['future'], {'keep': true});
    expect(uploaded.value.asResponseSource(mimeType: 'application/octet-stream').api, 'responses');
    expect(page.value.data.single.id, 'file_1');
    expect(page.value.extensions.toDart()['future_page'], isTrue);
    expect(retrieved.value.purpose, OpenAIFilePurpose.userData);
    expect(downloaded.expand((chunk) => chunk), [0, 1, 2, 255]);
    expect(deleted.value.deleted, isTrue);
    expect(requests, [
      'POST /v1/files',
      'GET /v1/files?purpose=user_data&limit=10&order=asc&after=file+before',
      'GET /v1/files/file_1',
      'GET /v1/files/file_1/content',
      'DELETE /v1/files/file_1',
    ]);
    expect(uploadContentType, startsWith('multipart/form-data; boundary='));
    final uploadText = latin1.decode(uploadBody!);
    expect(uploadText, contains('name="purpose"\r\n\r\nuser_data'));
    expect(uploadText, contains('name="file"; filename="data.bin"'));
    expect(uploadText, contains('Content-Type: application/octet-stream'));
    expect(uploadBody, containsAllInOrder([0, 1, 2, 255]));
  });

  test('deprecated status may be absent and malformed pages fail as protocol errors', () async {
    final withoutStatus = Map<String, Object?>.from(_file)..remove('status');
    expect(
      OpenAIFile.fromJson(JsonObject(withoutStatus)).status,
      OpenAIFileStatus.unknown,
    );
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      await request.drain<void>();
      _json(request, {
        'object': 'list',
        'data': [1],
        'has_more': false,
      });
      await request.response.close();
    });
    final provider = _provider(server);
    addTearDown(provider.close);

    final exit = await provider.files.list().runFutureExit();

    expect(exit, _failedWith<ProtocolError>());
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

OpenAIProvider _provider(HttpServer server) => OpenAIProvider(
  apiKey: 'secret',
  baseUrl: Uri.parse('http://${server.address.address}:${server.port}/v1/'),
);

const _file = <String, Object?>{
  'id': 'file_1',
  'object': 'file',
  'bytes': 4,
  'created_at': 123,
  'filename': 'data.bin',
  'purpose': 'user_data',
  'status': 'processed',
  'future': {'keep': true},
};
