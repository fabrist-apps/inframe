import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:artificer_core/artificer_core.dart';
import 'package:artificer_core/transport.dart';
import 'package:artificer_google/artificer_google.dart';
import 'package:conflux/conflux.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

void main() {
  group('GoogleCachedContentsResource', () {
    test('should expose every lifecycle call as one explicit request', () async {
      final requests = <_ObservedRequest>[];
      var creates = 0;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        final body = await _body(request);
        requests.add(_ObservedRequest(request.method, request.uri.toString(), body));
        if (request.method == 'DELETE') {
          request.response.statusCode = HttpStatus.noContent;
        } else if (request.method == 'GET' && request.uri.path == '/v1beta/cachedContents') {
          _json(request, {
            'cachedContents': [_cache],
            'nextPageToken': 'next page',
            'futurePage': {'keep': true},
          });
        } else if (request.method == 'POST') {
          creates++;
          _json(request, {..._cache, 'name': 'cachedContents/cache-$creates'});
        } else {
          _json(request, _cache);
        }
        await request.response.close();
      });
      final client = _client(server);
      addTearDown(client.close);
      final caches = GoogleCachedContentsResource(client);
      final create = GoogleCreateCachedContentRequest(
        model: 'models/future-model',
        displayName: 'Reference material',
        contents: [
          GoogleContent(role: 'user', parts: [GooglePart.text('first corpus')]),
        ],
        systemInstruction: GoogleContent(parts: [GooglePart.text('Use the corpus.')]),
        tools: [GoogleSearchTool()],
        toolConfig: GoogleToolConfig(
          functionCallingConfig: GoogleFunctionCallingConfig(
            mode: GoogleFunctionCallingMode.auto,
          ),
        ),
        ttl: '3600s',
      );

      final created = await caches.create(create).runFuture();
      final second = await caches
          .create(
            GoogleCreateCachedContentRequest(
              model: 'models/future-model',
              contents: [
                GoogleContent(role: 'user', parts: [GooglePart.text('changed corpus')]),
              ],
              ttl: '3600s',
            ),
          )
          .runFuture();
      final page = await caches.list(pageSize: 1, pageToken: 'current page').runFuture();
      final retrieved = await caches.retrieve(created.value.name).runFuture();
      await caches
          .update(
            created.value.name,
            GoogleCachedContentExpirationUpdate(ttl: '600.5s'),
          )
          .runFuture();
      await caches
          .update(
            created.value.name,
            GoogleCachedContentExpirationUpdate(expireTime: '2026-09-13T12:00:00Z'),
          )
          .runFuture();
      final deleted = await caches.delete(created.value.name).runFuture();

      expect(created.value.name, 'cachedContents/cache-1');
      expect(second.value.name, 'cachedContents/cache-2');
      expect(page.value.cachedContents.single.name, 'cachedContents/cache-1');
      expect(page.value.nextPageToken, 'next page');
      expect(page.value.extensions.toDart()['futurePage'], {'keep': true});
      expect(retrieved.value.usageMetadata?.totalTokenCount, 1200);
      expect(retrieved.value.usageMetadata?.extensions.toDart()['futureUsage'], isTrue);
      expect(retrieved.value.extensions.toDart()['futureCache'], {'keep': true});
      expect(deleted.value.toDart(), isEmpty);
      expect(requests.map((request) => '${request.method} ${request.uri}'), [
        'POST /v1beta/cachedContents',
        'POST /v1beta/cachedContents',
        'GET /v1beta/cachedContents?pageSize=1&pageToken=current+page',
        'GET /v1beta/cachedContents/cache-1',
        'PATCH /v1beta/cachedContents/cache-1?updateMask=ttl',
        'PATCH /v1beta/cachedContents/cache-1?updateMask=expireTime',
        'DELETE /v1beta/cachedContents/cache-1',
      ]);
      expect(requests.first.body, {
        'model': 'models/future-model',
        'contents': [
          {
            'role': 'user',
            'parts': [
              {'text': 'first corpus'},
            ],
          },
        ],
        'tools': [
          {'googleSearch': <String, Object?>{}},
        ],
        'systemInstruction': {
          'parts': [
            {'text': 'Use the corpus.'},
          ],
        },
        'toolConfig': {
          'functionCallingConfig': {'mode': 'AUTO'},
        },
        'displayName': 'Reference material',
        'ttl': '3600s',
      });
      expect(requests[4].body, {'ttl': '600.5s'});
      expect(requests[5].body, {'expireTime': '2026-09-13T12:00:00Z'});
    });

    test(
      'should pass and clear a returned cache reference without hidden lifecycle calls',
      () async {
        final paths = <String>[];
        final generationBodies = <Map<String, Object?>>[];
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => server.close(force: true));
        server.listen((request) async {
          final body = await _body(request);
          paths.add('${request.method} ${request.uri}');
          if (request.uri.path == '/v1beta/cachedContents') {
            _json(request, _cache);
          } else {
            generationBodies.add(body);
            _json(request, _generation);
          }
          await request.response.close();
        });
        final borrowed = http.Client();
        addTearDown(borrowed.close);
        final root = Uri.parse('http://${server.address.address}:${server.port}');
        final cacheClient = ProviderHttpClient(
          baseUrl: root,
          headers: {'x-goog-api-key': 'secret'},
          client: borrowed,
        );
        addTearDown(cacheClient.close);
        final caches = GoogleCachedContentsResource(cacheClient);
        final provider = GoogleProvider(apiKey: 'secret', baseUrl: root, httpClient: borrowed);
        addTearDown(provider.close);

        final cache = await caches
            .create(
              GoogleCreateCachedContentRequest(
                model: 'models/future-model',
                contents: [
                  GoogleContent(role: 'user', parts: [GooglePart.text('corpus')]),
                ],
              ),
            )
            .runFuture();
        final model = provider.languageModel(
          'future-model',
          options: GoogleModelOptions(cachedContent: Setting.set(cache.value.name)),
        );
        final request = GenerationRequest(messages: [UserMessage.text('question')]);
        final result = await model.generate(request).runFuture();
        await model
            .generate(
              request,
              options: GoogleModelOptions(cachedContent: const Setting.clear()),
            )
            .runFuture();

        expect(result.text, 'answer');
        expect(generationBodies.first['cachedContent'], 'cachedContents/cache-1');
        expect(generationBodies.last.containsKey('cachedContent'), isFalse);
        expect(paths, [
          'POST /v1beta/cachedContents',
          'POST /v1beta/models/future-model:generateContent',
          'POST /v1beta/models/future-model:generateContent',
        ]);
      },
    );

    test('should reject invalid expiration unions before I/O', () {
      expect(GoogleCachedContentExpirationUpdate.new, throwsArgumentError);
      expect(
        () => GoogleCachedContentExpirationUpdate(
          ttl: '60s',
          expireTime: '2026-09-13T12:00:00Z',
        ),
        throwsArgumentError,
      );
      expect(
        () => GoogleCreateCachedContentRequest(
          model: 'models/model',
          ttl: '60s',
          expireTime: '2026-09-13T12:00:00Z',
        ),
        throwsArgumentError,
      );
    });

    test('should accept only range-valid RFC 3339 expiration timestamps', () {
      for (final expireTime in [
        '2026-09-13T12:00:00Z',
        '2026-09-13T12:00:00+05:30',
        '2026-09-13T12:00:00.123456789-04:00',
      ]) {
        expect(
          () => GoogleCachedContentExpirationUpdate(expireTime: expireTime),
          returnsNormally,
        );
      }

      for (final expireTime in [
        '2026-09-13 12:00:00Z',
        '2026-02-30T12:00:00Z',
        '2026-09-13T24:00:00Z',
        '2026-09-13T12:00:00+24:00',
        '2026-09-13T12:00:00.1234567890Z',
      ]) {
        expect(
          () => GoogleCachedContentExpirationUpdate(expireTime: expireTime),
          throwsArgumentError,
        );
      }
    });

    test('should retain native service errors', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        request.response
          ..statusCode = HttpStatus.tooManyRequests
          ..headers.contentType = ContentType.json
          ..headers.set('x-request-id', 'cache-request')
          ..headers.set('retry-after', '3')
          ..write(
            jsonEncode({
              'error': {
                'code': 429,
                'status': 'RESOURCE_EXHAUSTED',
                'message': 'Quota exceeded.',
                'details': [
                  {'@type': 'future-detail'},
                ],
              },
            }),
          );
        await request.response.close();
      });
      final client = _client(server);
      addTearDown(client.close);
      final caches = GoogleCachedContentsResource(client);

      final exit = await caches.list().runFutureExit();

      final error = _errorFrom(exit) as ProviderError;
      expect(error.statusCode, 429);
      expect(error.requestId, 'cache-request');
      expect(error.retryAfter, const Duration(seconds: 3));
      expect(error.details?.toDart(), containsPair('error', isA<Map<String, Object?>>()));
      expect(error.toString(), 'ProviderError');
    });
  });
}

ProviderHttpClient _client(HttpServer server) => ProviderHttpClient(
  baseUrl: Uri.parse('http://${server.address.address}:${server.port}'),
  headers: {'x-goog-api-key': 'secret'},
);

Future<Map<String, Object?>> _body(HttpRequest request) async {
  final text = await utf8.decoder.bind(request).join();
  return text.isEmpty ? {} : jsonDecode(text)! as Map<String, Object?>;
}

void _json(HttpRequest request, Map<String, Object?> body) {
  request.response
    ..headers.contentType = ContentType.json
    ..write(jsonEncode(body));
}

AiError _errorFrom(Object exit) =>
    ((exit as Failed<Object?, AiError>).cause as Expected<AiError>).error;

final class _ObservedRequest {
  const _ObservedRequest(this.method, this.uri, this.body);

  final String method;
  final String uri;
  final Map<String, Object?> body;
}

const _cache = <String, Object?>{
  'name': 'cachedContents/cache-1',
  'model': 'models/future-model',
  'displayName': 'Reference material',
  'createTime': '2026-09-12T10:00:00Z',
  'updateTime': '2026-09-12T10:05:00Z',
  'expireTime': '2026-09-12T11:00:00Z',
  'usageMetadata': {'totalTokenCount': 1200, 'futureUsage': true},
  'futureCache': {'keep': true},
};

const _generation = <String, Object?>{
  'candidates': [
    {
      'content': {
        'role': 'model',
        'parts': [
          {'text': 'answer'},
        ],
      },
      'finishReason': 'STOP',
      'index': 0,
    },
  ],
};
