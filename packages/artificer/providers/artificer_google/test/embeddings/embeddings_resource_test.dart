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
  group('GoogleEmbeddingsResource', () {
    test('should use the exact single and synchronous batch routes', () async {
      final requests = <({String path, Map<String, Object?> body})>[];
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        requests.add((
          path: request.uri.path,
          body: jsonDecode(await utf8.decoder.bind(request).join())! as Map<String, Object?>,
        ));
        _json(
          request,
          requests.length == 1
              ? {
                  'embedding': {
                    'values': [1, 2],
                    'futureEmbedding': true,
                  },
                  'futureSingle': true,
                }
              : {
                  'embeddings': [
                    {
                      'values': [3, 4],
                    },
                    {
                      'values': [5, 6],
                    },
                  ],
                  'usageMetadata': {'promptTokenCount': 7},
                  'futureBatch': true,
                },
        );
        await request.response.close();
      });
      final client = _client(server);
      addTearDown(client.close);
      final resource = GoogleEmbeddingsResource(client);
      final content = GoogleContent(parts: [GooglePart.text('first')]);

      final single = await resource
          .embedContent(
            GoogleEmbedContentRequest(
              model: 'models/gemini-embedding-001',
              content: content,
            ),
          )
          .runFuture();
      final batch = await resource
          .batchEmbedContents(
            GoogleBatchEmbedContentsRequest(
              model: 'models/gemini-embedding-001',
              requests: [
                GoogleEmbedContentRequest(
                  model: 'models/gemini-embedding-001',
                  content: content,
                ),
                GoogleEmbedContentRequest(
                  model: 'models/gemini-embedding-001',
                  content: GoogleContent(parts: [GooglePart.text('second')]),
                ),
              ],
            ),
          )
          .runFuture();
      final normalizedSingle = resource.normalizeEmbedContent(single);
      final normalizedBatch = resource.normalizeBatchEmbedContents(batch, inputCount: 2);

      expect(requests.map((request) => request.path), [
        '/v1beta/models/gemini-embedding-001:embedContent',
        '/v1beta/models/gemini-embedding-001:batchEmbedContents',
      ]);
      expect(requests.first.body, {
        'content': {
          'parts': [
            {'text': 'first'},
          ],
        },
      });
      expect(requests.last.body, {
        'requests': [
          {
            'model': 'models/gemini-embedding-001',
            'content': {
              'parts': [
                {'text': 'first'},
              ],
            },
          },
          {
            'model': 'models/gemini-embedding-001',
            'content': {
              'parts': [
                {'text': 'second'},
              ],
            },
          },
        ],
      });
      expect(single.value.extensions.toDart()['futureSingle'], isTrue);
      expect(single.metadata.requestId, 'embedding-request');
      expect(batch.value.embeddings.map((value) => value.values), [
        [3, 4],
        [5, 6],
      ]);
      expect(batch.value.usageMetadata!.promptTokenCount, 7);
      expect(batch.value.extensions.toDart()['futureBatch'], isTrue);
      expect(normalizedSingle.vectors, [
        [1, 2],
      ]);
      expect(normalizedBatch.vectors, [
        [3, 4],
        [5, 6],
      ]);
      expect(requests, hasLength(2));
    });

    test('should preserve multimodal item and part order in one common batch', () async {
      late Map<String, Object?> body;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        body = jsonDecode(await utf8.decoder.bind(request).join())! as Map<String, Object?>;
        _json(request, {
          'embeddings': [
            {
              'values': [1, 1],
            },
            {
              'values': [2, 2],
            },
            {
              'values': [3, 3],
            },
            {
              'values': [4, 4],
            },
            {
              'values': [5, 5],
            },
          ],
          'usageMetadata': {
            'promptTokenCount': 12,
            'futureUsage': {'keep': true},
          },
          'futureResponse': true,
        });
        await request.response.close();
      });
      final client = _client(server);
      addTearDown(client.close);
      final model = GoogleEmbeddingModel(
        GoogleEmbeddingsResource(client),
        'gemini-embedding-2',
        GoogleEmbeddingOptions(),
      );

      final result = await model
          .embed(
            EmbeddingRequest(
              items: [
                EmbeddingInput([
                  TextInputPart('deployment'),
                  _bytes(MediaKind.image, 'image/png', [1, 2, 3]),
                ]),
                EmbeddingInput([
                  _bytes(MediaKind.audio, 'audio/mpeg', [4, 5]),
                ]),
                EmbeddingInput([
                  _bytes(MediaKind.video, 'video/mp4', [6, 7]),
                ]),
                EmbeddingInput([
                  _bytes(MediaKind.document, 'application/pdf', [8, 9]),
                ]),
                EmbeddingInput([
                  MediaInputPart(
                    kind: MediaKind.image,
                    mimeType: 'image/jpeg',
                    source: ProviderFileSource(
                      providerId: 'google',
                      api: 'files',
                      reference: 'https://generativelanguage.googleapis.com/v1beta/files/image-1',
                      mimeType: 'image/jpeg',
                    ),
                  ),
                ]),
              ],
            ),
          )
          .runFuture();

      expect(result.vectors, [
        [1, 1],
        [2, 2],
        [3, 3],
        [4, 4],
        [5, 5],
      ]);
      expect(result.modelId, 'gemini-embedding-2');
      expect(result.usage!.inputTokens, 12);
      expect(result.nativePayload.json.toDart()['futureResponse'], isTrue);
      final nativeRequests = body['requests']! as List<Object?>;
      expect(nativeRequests, hasLength(5));
      expect(nativeRequests.first, {
        'model': 'models/gemini-embedding-2',
        'content': {
          'parts': [
            {'text': 'deployment'},
            {
              'inlineData': {'mimeType': 'image/png', 'data': 'AQID'},
            },
          ],
        },
      });
      expect(nativeRequests[1], {
        'model': 'models/gemini-embedding-2',
        'content': {
          'parts': [
            {
              'inlineData': {'mimeType': 'audio/mpeg', 'data': 'BAU='},
            },
          ],
        },
      });
      expect(nativeRequests.last, {
        'model': 'models/gemini-embedding-2',
        'content': {
          'parts': [
            {
              'fileData': {
                'mimeType': 'image/jpeg',
                'fileUri': 'https://generativelanguage.googleapis.com/v1beta/files/image-1',
              },
            },
          ],
        },
      });
    });

    test('should aggregate several parts in one item into one vector', () async {
      late Map<String, Object?> body;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        expect(request.uri.path, '/v1beta/models/gemini-embedding-2:embedContent');
        body = jsonDecode(await utf8.decoder.bind(request).join())! as Map<String, Object?>;
        _json(request, {
          'embedding': {
            'values': [1, 2],
          },
        });
        await request.response.close();
      });
      final client = _client(server);
      addTearDown(client.close);
      final model = GoogleEmbeddingModel(
        GoogleEmbeddingsResource(client),
        'gemini-embedding-2',
        GoogleEmbeddingOptions(),
      );

      final result = await model
          .embed(
            EmbeddingRequest(
              items: [
                EmbeddingInput([
                  TextInputPart('diagram'),
                  _bytes(MediaKind.image, 'image/png', [1]),
                ]),
              ],
            ),
          )
          .runFuture();

      expect(result.vectors, [
        [1, 2],
      ]);
      expect(body, {
        'content': {
          'parts': [
            {'text': 'diagram'},
            {
              'inlineData': {'mimeType': 'image/png', 'data': 'AQ=='},
            },
          ],
        },
      });
    });

    test('should inherit typed options and validate known conflicts before I/O', () async {
      final bodies = <Map<String, Object?>>[];
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        bodies.add(jsonDecode(await utf8.decoder.bind(request).join())! as Map<String, Object?>);
        _json(request, {
          'embedding': {
            'values': List<double>.filled(768, 1),
          },
        });
        await request.response.close();
      });
      final client = _client(server);
      addTearDown(client.close);
      final resource = GoogleEmbeddingsResource(client);
      final textModel = GoogleEmbeddingModel(
        resource,
        'gemini-embedding-001',
        GoogleEmbeddingOptions(
          taskType: const Setting.set(GoogleEmbeddingTaskType.retrievalDocument),
          title: const Setting.set('Model title'),
          dimensions: const Setting.set(1536),
        ),
      );

      final result = await textModel
          .embed(
            EmbeddingRequest(items: [EmbeddingInput.text('document')]),
            options: GoogleEmbeddingOptions(
              title: const Setting.set('Call title'),
              dimensions: const Setting.set(768),
            ),
          )
          .runFuture();
      final conflict = await textModel
          .embed(
            EmbeddingRequest(items: [EmbeddingInput.text('document')], dimensions: 512),
            options: GoogleEmbeddingOptions(dimensions: const Setting.set(768)),
          )
          .runFutureExit();
      final taskOnEmbedding2 = await GoogleEmbeddingModel(
        resource,
        'gemini-embedding-2',
        GoogleEmbeddingOptions(
          taskType: const Setting.set(GoogleEmbeddingTaskType.classification),
        ),
      ).embed(EmbeddingRequest(items: [EmbeddingInput.text('classify me')])).runFutureExit();
      final mediaOnTextModel = await textModel
          .embed(
            EmbeddingRequest(
              items: [
                EmbeddingInput([
                  _bytes(MediaKind.image, 'image/png', [1]),
                ]),
              ],
            ),
          )
          .runFutureExit();
      final oversized = await textModel
          .embed(
            EmbeddingRequest(
              items: List.generate(101, (index) => EmbeddingInput.text('$index')),
            ),
          )
          .runFutureExit();
      final undersized = await textModel
          .embed(
            EmbeddingRequest(
              items: [EmbeddingInput.text('document')],
              dimensions: 127,
            ),
            options: GoogleEmbeddingOptions(dimensions: const Setting.clear()),
          )
          .runFutureExit();

      expect(result.vectors.single, hasLength(768));
      expect(bodies.single['embedContentConfig'], {
        'taskType': 'RETRIEVAL_DOCUMENT',
        'title': 'Call title',
        'outputDimensionality': 768,
      });
      expect(conflict, _failedWith<InvalidRequestError>());
      expect(taskOnEmbedding2, _failedWith<UnsupportedFeatureError>());
      expect(mediaOnTextModel, _failedWith<UnsupportedFeatureError>());
      expect(oversized, _failedWith<UnsupportedFeatureError>());
      expect(undersized, _failedWith<InvalidRequestError>());
      expect(bodies, hasLength(1));
    });

    test('should reject unsupported sources but preserve unknown-model service errors', () async {
      var requests = 0;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        requests++;
        await request.drain<void>();
        request.response
          ..statusCode = HttpStatus.badRequest
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode({
              'error': {
                'code': 400,
                'status': 'INVALID_ARGUMENT',
                'message': 'future model rejected this modality',
                'details': [
                  {'future': true},
                ],
              },
            }),
          );
        await request.response.close();
      });
      final client = _client(server);
      addTearDown(client.close);
      final resource = GoogleEmbeddingsResource(client);
      final unknown = GoogleEmbeddingModel(
        resource,
        'future-embedding-model',
        GoogleEmbeddingOptions(),
      );
      final url = await unknown
          .embed(
            EmbeddingRequest(
              items: [
                EmbeddingInput([
                  MediaInputPart(
                    kind: MediaKind.image,
                    mimeType: 'image/png',
                    source: UrlMediaSource(Uri.parse('https://example.com/image.png')),
                  ),
                ]),
              ],
            ),
          )
          .runFutureExit();
      final upstream = await unknown
          .embed(
            EmbeddingRequest(
              items: [
                EmbeddingInput([
                  _bytes(MediaKind.image, 'image/png', [1]),
                ]),
              ],
            ),
          )
          .runFutureExit();

      expect(url, _failedWith<UnsupportedFeatureError>());
      expect(upstream, _failedWith<ProviderError>());
      expect(requests, 1);
    });

    test('should reject missing, extra, empty, inconsistent, and mismatched vectors', () {
      final client = ProviderHttpClient(baseUrl: Uri.parse('http://127.0.0.1:1'));
      addTearDown(client.close);
      final resource = GoogleEmbeddingsResource(client);

      expect(
        () => resource.normalizeBatchEmbedContents(
          _batchResponse([
            [1, 2],
          ]),
          inputCount: 2,
        ),
        throwsA(isA<ProtocolError>()),
      );
      expect(
        () => resource.normalizeBatchEmbedContents(
          _batchResponse([
            [1, 2],
            [3, 4],
            [5, 6],
          ]),
          inputCount: 2,
        ),
        throwsA(isA<ProtocolError>()),
      );
      expect(
        () => resource.normalizeBatchEmbedContents(
          _batchResponse([
            <num>[],
            [1, 2],
          ]),
          inputCount: 2,
        ),
        throwsA(isA<ProtocolError>()),
      );
      expect(
        () => resource.normalizeBatchEmbedContents(
          _batchResponse([
            [1],
            [2, 3],
          ]),
          inputCount: 2,
        ),
        throwsA(isA<ProtocolError>()),
      );
      expect(
        () => resource.normalizeEmbedContent(_singleResponse([1, 2]), requestedDimensions: 3),
        throwsA(isA<ProtocolError>()),
      );
    });

    test('should stay lazy across runs and integrate interruption and close', () async {
      final requestStarted = Completer<void>();
      var requests = 0;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        requests++;
        await request.drain<void>();
        if (requests == 1) {
          requestStarted.complete();
          return;
        }
        _json(request, {
          'embedding': {
            'values': [1, 2],
          },
        });
        await request.response.close();
      });
      final client = _client(server);
      final runtime = Runtime();
      addTearDown(runtime.close);
      addTearDown(client.close);
      final model = GoogleEmbeddingModel(
        GoogleEmbeddingsResource(client),
        'future-embedding-model',
        GoogleEmbeddingOptions(),
      );
      final operation = model.embed(
        EmbeddingRequest(items: [EmbeddingInput.text('lazy')]),
      );

      expect(requests, 0);
      final fiber = runtime.fork(operation);
      await requestStarted.future;
      final interrupted = await fiber
          .interrupt('stop embedding')
          .timeout(
            const Duration(seconds: 2),
          );
      final repeated = await Future.wait([operation.runFuture(), operation.runFuture()]);
      await client.close();
      final closed = await operation.runFutureExit();

      expect((interrupted as Failed<Object?, AiError>).cause.containsInterruption, isTrue);
      expect(repeated.map((result) => result.vectors.single), [
        [1, 2],
        [1, 2],
      ]);
      expect(closed, _failedWith<ClientClosedError>());
      expect(requests, 3);
    });
  });
}

MediaInputPart _bytes(MediaKind kind, String mimeType, List<int> bytes) => MediaInputPart(
  kind: kind,
  mimeType: mimeType,
  source: BytesMediaSource(bytes),
);

ProviderHttpClient _client(HttpServer server) => ProviderHttpClient(
  baseUrl: Uri.parse('http://${server.address.address}:${server.port}'),
  headers: const {'x-goog-api-key': 'secret'},
);

void _json(HttpRequest request, Map<String, Object?> body) {
  request.response
    ..headers.contentType = ContentType.json
    ..headers.set('x-request-id', 'embedding-request')
    ..write(jsonEncode(body));
}

NativeResponse<GoogleBatchEmbedContentsResponse> _batchResponse(List<List<num>> vectors) {
  final json = JsonObject({
    'embeddings': [
      for (final vector in vectors) {'values': vector},
    ],
  });
  return NativeResponse(
    value: GoogleBatchEmbedContentsResponse.fromJson(json),
    payload: NativePayload(
      providerId: 'google',
      api: 'embeddings',
      modelId: 'model',
      json: json,
    ),
    metadata: ResponseMetadata(statusCode: 200),
  );
}

NativeResponse<GoogleEmbedContentResponse> _singleResponse(List<num> vector) {
  final json = JsonObject({
    'embedding': {'values': vector},
  });
  return NativeResponse(
    value: GoogleEmbedContentResponse.fromJson(json),
    payload: NativePayload(
      providerId: 'google',
      api: 'embeddings',
      modelId: 'model',
      json: json,
    ),
    metadata: ResponseMetadata(statusCode: 200),
  );
}

Matcher _failedWith<E extends AiError>() => isA<Failed<Object?, AiError>>().having(
  (failure) => failure.cause,
  'cause',
  isA<Expected<AiError>>().having((expected) => expected.error, 'error', isA<E>()),
);
