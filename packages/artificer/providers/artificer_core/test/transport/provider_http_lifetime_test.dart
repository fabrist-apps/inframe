import 'dart:async';
import 'dart:io';

import 'package:artificer_core/artificer_core.dart';
import 'package:artificer_core/transport.dart';
import 'package:conflux/conflux.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

void main() {
  group('ProviderHttpClient lifetime', () {
    test('should abort a real request before response headers', () async {
      final received = Completer<void>();
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) {
        received.complete();
      });
      final client = ProviderHttpClient(
        baseUrl: Uri.parse('http://${server.address.address}:${server.port}/'),
      );
      final runtime = Runtime();
      addTearDown(runtime.close);
      addTearDown(client.close);
      final fiber = runtime.fork(
        client.sendJson(
          ProviderHttpRequest(method: 'GET', path: 'slow'),
          providerId: 'fixture',
          api: 'generate',
          modelId: 'model',
        ),
      );
      await received.future;

      final exit = await fiber.interrupt('caller').timeout(const Duration(seconds: 2));

      expect((exit as Failed<Object?, AiError>).cause, isA<Interrupted<AiError>>());
    });

    test('should cancel a real response body and keep the shared client usable', () async {
      final bodyStarted = Completer<void>();
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        if (request.uri.path == '/next') {
          request.response.write('{}');
          await request.response.close();
          return;
        }
        request.response.write('{"output":"');
        await request.response.flush();
        bodyStarted.complete();
      });
      final client = ProviderHttpClient(
        baseUrl: Uri.parse('http://${server.address.address}:${server.port}/'),
      );
      final runtime = Runtime();
      addTearDown(runtime.close);
      addTearDown(client.close);
      final fiber = runtime.fork(
        client.sendJson(
          ProviderHttpRequest(method: 'GET', path: 'slow'),
          providerId: 'fixture',
          api: 'generate',
          modelId: 'model',
        ),
      );
      await bodyStarted.future;

      final exit = await fiber.interrupt('caller').timeout(const Duration(seconds: 2));
      final next = await runtime.run(
        client.sendJson(
          ProviderHttpRequest(method: 'GET', path: 'next'),
          providerId: 'fixture',
          api: 'generate',
          modelId: 'model',
        ),
      );

      expect((exit as Failed<Object?, AiError>).cause, isA<Interrupted<AiError>>());
      expect(next, isA<Succeeded<NativeResponse<Object?>, AiError>>());
    });

    test('should await a late response and release its body after caller cancellation', () async {
      final borrowed = _DelayedClient();
      final client = ProviderHttpClient(
        baseUrl: Uri.parse('https://example.test/'),
        client: borrowed,
      );
      final runtime = Runtime();
      addTearDown(runtime.close);
      addTearDown(client.close);
      final fiber = runtime.fork(
        client.sendJson(
          ProviderHttpRequest(method: 'GET', path: 'slow'),
          providerId: 'fixture',
          api: 'generate',
          modelId: 'model',
        ),
      );
      await borrowed.sent.future;

      var interruptionCompleted = false;
      final interrupted = fiber
          .interrupt('caller')
          .whenComplete(() => interruptionCompleted = true);
      await Future<void>.delayed(Duration.zero);
      expect(interruptionCompleted, isFalse);

      borrowed.completeLateResponse();
      final exit = await interrupted;

      expect(exit, isA<Failed<NativeResponse<Object?>, AiError>>());
      expect((exit as Failed<Object?, AiError>).cause, isA<Interrupted<AiError>>());
      expect(borrowed.bodyCancelled, isTrue);
    });

    test('should interrupt active work and share one idempotent close future', () async {
      final borrowed = _DelayedClient();
      final client = ProviderHttpClient(
        baseUrl: Uri.parse('https://example.test/'),
        client: borrowed,
      );
      final runtime = Runtime();
      addTearDown(runtime.close);
      final fiber = runtime.fork(
        client.sendJson(
          ProviderHttpRequest(method: 'GET', path: 'slow'),
          providerId: 'fixture',
          api: 'generate',
          modelId: 'model',
        ),
      );
      await borrowed.sent.future;

      final firstClose = client.close();
      final secondClose = client.close();
      expect(identical(firstClose, secondClose), isTrue);
      borrowed.completeLateResponse();
      await firstClose;
      final exit = await fiber.join();

      expect((exit as Failed<Object?, AiError>).cause, isA<Interrupted<AiError>>());
      expect(borrowed.bodyCancelled, isTrue);
      expect(borrowed.closed, isFalse);

      final afterClose = await runtime.run(
        client.sendJson(
          ProviderHttpRequest(method: 'GET', path: 'later'),
          providerId: 'fixture',
          api: 'generate',
          modelId: 'model',
        ),
      );
      expect(afterClose, _expectedError<ClientClosedError>());
    });

    test('should leave a borrowed client usable for unrelated requests', () async {
      final borrowed = _ImmediateClient();
      final client = ProviderHttpClient(
        baseUrl: Uri.parse('https://example.test/'),
        client: borrowed,
      );

      await client.close();
      final response = await borrowed.get(Uri.parse('https://example.test/unrelated'));

      expect(response.statusCode, 204);
      expect(borrowed.closed, isFalse);
    });

    test('should isolate cancellation across concurrent requests', () async {
      final borrowed = _MultipleDelayedClient();
      final client = ProviderHttpClient(
        baseUrl: Uri.parse('https://example.test/'),
        client: borrowed,
      );
      final runtime = Runtime();
      addTearDown(runtime.close);
      addTearDown(client.close);
      final first = runtime.fork(
        client.sendJson(
          ProviderHttpRequest(method: 'GET', path: 'first'),
          providerId: 'fixture',
          api: 'generate',
          modelId: 'model',
        ),
      );
      await borrowed.firstSent.future;
      final second = runtime.fork(
        client.sendJson(
          ProviderHttpRequest(method: 'GET', path: 'second'),
          providerId: 'fixture',
          api: 'generate',
          modelId: 'model',
        ),
      );
      await borrowed.secondSent.future;

      final interrupted = first.interrupt('caller');
      borrowed.completeFirstLate();
      borrowed.completeSecond();
      final exits = await Future.wait([interrupted, second.join()]);

      expect((exits[0] as Failed<Object?, AiError>).cause, isA<Interrupted<AiError>>());
      expect(exits[1], isA<Succeeded<NativeResponse<Object?>, AiError>>());
      expect(borrowed.firstBodyCancelled, isTrue);
    });

    test('should retain interruption when response cleanup is defective', () async {
      final borrowed = _CleanupFailureClient();
      final client = ProviderHttpClient(
        baseUrl: Uri.parse('https://example.test/'),
        client: borrowed,
      );
      final runtime = Runtime();
      addTearDown(runtime.close);
      addTearDown(client.close);
      final fiber = runtime.fork(
        client.sendJson(
          ProviderHttpRequest(method: 'GET', path: 'slow'),
          providerId: 'fixture',
          api: 'generate',
          modelId: 'model',
        ),
      );
      await borrowed.listening.future;

      final exit = await fiber.interrupt('caller');
      final cause = (exit as Failed<Object?, AiError>).cause;

      expect(cause.containsInterruption, isTrue);
      expect(_containsDefect(cause), isTrue);
    });
  });
}

Matcher _expectedError<E extends AiError>() => isA<Failed<Object?, AiError>>().having(
  (failure) => failure.cause,
  'cause',
  isA<Expected<AiError>>().having((cause) => cause.error, 'error', isA<E>()),
);

bool _containsDefect<E>(Cause<E> cause) => switch (cause) {
  Defect<E>() => true,
  Sequential<E>(:final causes) || Parallel<E>(:final causes) => causes.any(_containsDefect<E>),
  Expected<E>() || Interrupted<E>() => false,
};

final class _DelayedClient extends http.BaseClient {
  final Completer<void> sent = Completer<void>();
  final Completer<http.StreamedResponse> _response = Completer<http.StreamedResponse>();
  bool bodyCancelled = false;
  bool closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    sent.complete();
    return _response.future;
  }

  void completeLateResponse() {
    final controller = StreamController<List<int>>(onCancel: () => bodyCancelled = true);
    _response.complete(http.StreamedResponse(controller.stream, 200));
  }

  @override
  void close() {
    closed = true;
  }
}

final class _ImmediateClient extends http.BaseClient {
  bool closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      http.StreamedResponse(const Stream.empty(), 204);

  @override
  void close() {
    closed = true;
  }
}

final class _MultipleDelayedClient extends http.BaseClient {
  final Completer<void> firstSent = Completer<void>();
  final Completer<void> secondSent = Completer<void>();
  final List<Completer<http.StreamedResponse>> _responses = [];
  bool firstBodyCancelled = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    final response = Completer<http.StreamedResponse>();
    _responses.add(response);
    if (_responses.length == 1) {
      firstSent.complete();
    } else {
      secondSent.complete();
    }
    return response.future;
  }

  void completeFirstLate() {
    final body = StreamController<List<int>>(onCancel: () => firstBodyCancelled = true);
    _responses[0].complete(http.StreamedResponse(body.stream, 200));
  }

  void completeSecond() {
    _responses[1].complete(
      http.StreamedResponse(Stream.value('{}'.codeUnits), 200),
    );
  }
}

final class _CleanupFailureClient extends http.BaseClient {
  final Completer<void> listening = Completer<void>();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final body = StreamController<List<int>>(
      onListen: listening.complete,
      onCancel: () => Future<void>.error(StateError('cleanup failed')),
    );
    return http.StreamedResponse(body.stream, 200);
  }
}
