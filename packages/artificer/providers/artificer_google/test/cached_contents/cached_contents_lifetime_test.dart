import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:artificer_core/artificer_core.dart';
import 'package:artificer_core/transport.dart';
import 'package:artificer_google/src/cached_contents/cached_contents_resource.dart';
import 'package:conflux/conflux.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

void main() {
  group('GoogleCachedContentsResource lifetime', () {
    test('should cancel one pending request and keep a borrowed client usable', () async {
      final received = Completer<void>();
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        if (request.uri.path == '/unrelated') {
          request.response.write('ok');
          await request.response.close();
        } else {
          received.complete();
        }
      });
      final borrowed = http.Client();
      addTearDown(borrowed.close);
      final root = Uri.parse('http://${server.address.address}:${server.port}');
      final client = ProviderHttpClient(baseUrl: root, client: borrowed);
      addTearDown(client.close);
      final runtime = Runtime();
      addTearDown(runtime.close);
      final caches = GoogleCachedContentsResource(client);

      final fiber = runtime.fork(caches.retrieve('cachedContents/cache-1'));
      await received.future;
      final exit = await fiber.interrupt('caller stopped').timeout(const Duration(seconds: 2));
      final unrelated = await borrowed.get(root.resolve('/unrelated'));

      expect((exit as Failed<Object?, AiError>).cause.containsInterruption, isTrue);
      expect(unrelated.body, 'ok');
    });

    test('should close without deleting caches and reject later work', () async {
      final requests = <String>[];
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        requests.add('${request.method} ${request.uri.path}');
        request.response
          ..headers.contentType = ContentType.json
          ..write(jsonEncode(_cache));
        await request.response.close();
      });
      final client = ProviderHttpClient(
        baseUrl: Uri.parse('http://${server.address.address}:${server.port}'),
      );
      final caches = GoogleCachedContentsResource(client);

      await client.close();
      final exit = await caches.retrieve('cachedContents/cache-1').runFutureExit();

      expect(exit, _failedWith<ClientClosedError>());
      expect(requests, isEmpty);
    });
  });
}

Matcher _failedWith<E extends AiError>() => isA<Failed<Object?, AiError>>().having(
  (failure) => failure.cause,
  'cause',
  isA<Expected<AiError>>().having((expected) => expected.error, 'error', isA<E>()),
);

const _cache = <String, Object?>{
  'name': 'cachedContents/cache-1',
  'model': 'models/model',
};
