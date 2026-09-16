import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:artificer_core/artificer_core.dart';
import 'package:artificer_core/transport.dart';
import 'package:conflux/effect.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';

void main() {
  group('ProviderHttpClient', () {
    late HttpServer server;
    late Runtime runtime;
    setUp(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      runtime = Runtime();
    });
    tearDown(() async {
      await server.close(force: true);
      await runtime.close();
    });
    Uri endpoint() => Uri.parse('http://127.0.0.1:${server.port}/generate');

    test('should run cold JSON requests independently and retain native metadata', () async {
      var requests = 0;
      server.listen((request) async {
        requests++;
        expect(request.headers.value('authorization'), 'Bearer fixture');
        expect(jsonDecode(await utf8.decoder.bind(request).join()), {'text': 'hello'});
        request.response.headers.set('x-request-id', 'request-1');
        request.response.write('{"text":"reply","unknown":{"nested":true}}');
        await request.response.close();
      });
      final client = ProviderHttpClient();
      addTearDown(client.close);
      final operation = client.requestJson(
        url: endpoint(),
        headers: {'authorization': 'Bearer fixture'},
        body: {'text': 'hello'},
      );
      expect(requests, 0);
      final results = await Future.wait([runtime.run(operation), runtime.run(operation)]);
      expect(requests, 2);
      for (final result in results) {
        final reply = (result as Succeeded<ProviderJsonResponse, AiError>).value;
        expect(reply.data, {
          'text': 'reply',
          'unknown': {'nested': true},
        });
        expect(reply.metadata.requestId, 'request-1');
        expect(reply.metadata.statusCode, 200);
      }
    });

    test('should bound bytes and retain unsuccessful native JSON', () async {
      var count = 0;
      server.listen((request) async {
        if (count++ == 0) {
          request.response.write('"123456789"');
        } else {
          request.response.statusCode = 429;
          request.response.write('{"e":1}');
        }
        await request.response.close();
      });
      final client = ProviderHttpClient(maxResponseBytes: 8);
      addTearDown(client.close);
      final first = await runtime.run(client.requestJson(url: endpoint()));
      expect(
        (first as Failed<ProviderJsonResponse, AiError>).cause,
        isA<Expected<AiError>>().having((e) => e.error, 'error', isA<ResponseLimitError>()),
      );
      final second = await runtime.run(client.requestJson(url: endpoint()));
      final error =
          ((second as Failed<ProviderJsonResponse, AiError>).cause as Expected<AiError>).error
              as ProviderError;
      expect(error.statusCode, 429);
      expect(error.details, {'e': 1});
    });

    test('should interrupt body consumption when the provider closes', () async {
      final bodyStarted = Completer<void>();
      server.listen((request) async {
        request.response.write('{"partial":');
        await request.response.flush();
        bodyStarted.complete();
      });
      final client = ProviderHttpClient();
      final pending = runtime.run(client.requestJson(url: endpoint()));
      await bodyStarted.future;
      await client.close();
      final exit = await pending.timeout(const Duration(seconds: 2));
      expect((exit as Failed<ProviderJsonResponse, AiError>).cause, isA<Interrupted<AiError>>());
    });

    test('should reject nonfinite native JSON numbers as protocol errors', () async {
      server.listen((request) async {
        request.response.write('{"number":1e999}');
        await request.response.close();
      });
      final client = ProviderHttpClient();
      addTearDown(client.close);
      final exit = await runtime.run(client.requestJson(url: endpoint()));
      expect(exit, isA<Failed<ProviderJsonResponse, AiError>>());
      expect(
        (exit as Failed<ProviderJsonResponse, AiError>).cause,
        isA<Expected<AiError>>().having((cause) => cause.error, 'error', isA<ProtocolError>()),
      );
    });

    test('should reject incompatible borrowed adapters without replacing them', () {
      final dio = Dio();
      addTearDown(() => dio.close(force: true));
      final original = dio.httpClientAdapter;
      expect(() => ProviderHttpClient(dio: dio), throwsArgumentError);
      expect(dio.httpClientAdapter, same(original));
    });
  });
}
