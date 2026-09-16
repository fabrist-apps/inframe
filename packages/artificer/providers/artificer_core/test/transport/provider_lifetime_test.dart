import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:artificer_core/artificer_core.dart';
import 'package:artificer_core/transport.dart';
import 'package:conflux/effect.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:test/test.dart';

import 'http_client_fixture.dart';

void main() {
  group('ProviderDioAdapter request lifetime', () {
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
    Uri endpoint([String path = '/']) => Uri.parse('http://127.0.0.1:${server.port}$path');

    test('should join late native acquisition after connect timeout without sending', () async {
      var sent = 0;
      server.listen((_) => sent++);
      final native = _DelayedClient(HttpClient());
      final dio = Dio()..httpClientAdapter = ProviderDioAdapter(createHttpClient: () => native);
      addTearDown(() => dio.close(force: true));
      final client = ProviderHttpClient(dio: dio, connectTimeout: const Duration(milliseconds: 10));
      addTearDown(client.close);
      var settled = false;
      final pending = runtime.run(client.requestJson(url: endpoint()));
      unawaited(pending.then((_) => settled = true));
      await native.acquired.future;
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(settled, isFalse);
      native.release.complete();
      final exit = await pending;
      expect(
        (exit as Failed<ProviderJsonResponse, AiError>).cause,
        isA<Expected<AiError>>().having((cause) => cause.error, 'error', isA<TransportError>()),
      );
      expect(sent, 0);
    });

    test('should join late native acquisition after interruption without sending', () async {
      var sent = 0;
      server.listen((_) => sent++);
      final native = _DelayedClient(HttpClient());
      final dio = Dio()..httpClientAdapter = ProviderDioAdapter(createHttpClient: () => native);
      addTearDown(() => dio.close(force: true));
      final client = ProviderHttpClient(dio: dio);
      addTearDown(client.close);
      final fiber = runtime.fork(client.requestJson(url: endpoint()));
      await native.acquired.future;
      var settled = false;
      final pending = fiber.interrupt('test');
      unawaited(pending.then((_) => settled = true));
      await Future<void>.delayed(Duration.zero);
      expect(settled, isFalse);
      native.release.complete();
      final exit = await pending;
      expect((exit as Failed<ProviderJsonResponse, AiError>).cause, isA<Interrupted<AiError>>());
      expect(sent, 0);
    });

    test('should cancel and join a late unconsumed adapter response', () async {
      server.listen((request) async {
        request.response.write('{}');
        await request.response.close();
      });
      late _ControlledAdapter adapter;
      final dio = Dio()
        ..httpClientAdapter = ProviderDioAdapter(
          createAdapter: (factory) => adapter = _ControlledAdapter(factory, delayResponse: true),
        );
      addTearDown(() => dio.close(force: true));
      final client = ProviderHttpClient(dio: dio);
      addTearDown(client.close);
      final fiber = runtime.fork(client.requestJson(url: endpoint()));
      await adapter.headers.future;
      var settled = false;
      final pending = fiber.interrupt('test');
      unawaited(pending.then((_) => settled = true));
      adapter.responseRelease.complete();
      await adapter.cancelStarted.future.timeout(
        const Duration(seconds: 2),
        onTimeout: () => throw StateError('cancel never started'),
      );
      expect(settled, isFalse);
      adapter.cancelRelease.complete();
      final exit = await pending;
      expect(adapter.cancellations, 1);
      expect((exit as Failed<ProviderJsonResponse, AiError>).cause, isA<Interrupted<AiError>>());
    });

    test('should retain a body limit failure when upstream cancellation fails', () async {
      server.listen((request) async {
        request.response.bufferOutput = false;
        request.response.write('"${'x' * 4096}"');
        await request.response.flush();
      });
      late _ControlledAdapter adapter;
      final cleanupError = StateError('controlled cleanup failure');
      final dio = Dio()
        ..httpClientAdapter = ProviderDioAdapter(
          createAdapter: (factory) =>
              adapter = _ControlledAdapter(factory, cleanupError: cleanupError),
        );
      addTearDown(() => dio.close(force: true));
      final client = ProviderHttpClient(dio: dio, maxResponseBytes: 4);
      addTearDown(client.close);
      final pending = runtime.run(client.requestJson(url: endpoint()));
      await adapter.cancelStarted.future;
      adapter.cancelRelease.complete();
      final exit = await pending;
      final cause = (exit as Failed<ProviderJsonResponse, AiError>).cause;
      expect(cause, isA<Sequential<AiError>>());
      expect(cause.expectedErrors, contains(isA<ResponseLimitError>()));
      expect(_defects(cause), contains(same(cleanupError)));
    });

    test('should isolate shared providers and preserve borrowed Dio configuration', () async {
      final firstStarted = Completer<void>();
      server.listen((request) async {
        if (request.uri.path == '/first') {
          firstStarted.complete();
          return;
        }
        await Future<void>.delayed(const Duration(milliseconds: 20));
        request.response.write('{}');
        await request.response.close();
      });
      final options = BaseOptions(
        baseUrl: 'https://unused.invalid',
        connectTimeout: const Duration(milliseconds: 1),
        sendTimeout: const Duration(milliseconds: 1),
        receiveTimeout: const Duration(milliseconds: 1),
      );
      final dio = Dio(options)..httpClientAdapter = ProviderDioAdapter();
      addTearDown(() => dio.close(force: true));
      final adapter = dio.httpClientAdapter;
      final transformer = dio.transformer;
      final tokens = <CancelToken?>[];
      final interceptor = InterceptorsWrapper(
        onRequest: (options, handler) {
          tokens.add(options.cancelToken);
          expect(options.connectTimeout, const Duration(seconds: 30));
          expect(options.sendTimeout, Duration.zero);
          expect(options.receiveTimeout, Duration.zero);
          expect(options.followRedirects, isFalse);
          expect(options.responseType, ResponseType.stream);
          handler.next(options);
        },
      );
      dio.interceptors.add(interceptor);
      final interceptors = dio.interceptors.toList();
      final first = ProviderHttpClient(dio: dio);
      final second = ProviderHttpClient(dio: dio);
      addTearDown(second.close);
      final firstPending = runtime.run(first.requestJson(url: endpoint('/first')));
      await firstStarted.future;
      final secondPending = runtime.run(second.requestJson(url: endpoint('/second')));
      final closing = first.close();
      expect(first.close(), same(closing));
      await closing;
      final stopped = await firstPending;
      expect((stopped as Failed<ProviderJsonResponse, AiError>).cause, isA<Interrupted<AiError>>());
      expect(await secondPending, isA<Succeeded<ProviderJsonResponse, AiError>>());
      expect(
        await runtime.run(second.requestJson(url: endpoint('/reuse'))),
        isA<Succeeded<ProviderJsonResponse, AiError>>(),
      );
      final rejected = await runtime.run(first.requestJson(url: endpoint('/rejected')));
      expect(
        (rejected as Failed<ProviderJsonResponse, AiError>).cause.expectedErrors.single,
        isA<ClientClosedError>(),
      );
      expect(tokens.toSet().length, 3);
      expect(dio.options, same(options));
      expect(dio.options.receiveTimeout, const Duration(milliseconds: 1));
      expect(dio.httpClientAdapter, same(adapter));
      expect(dio.transformer, same(transformer));
      expect(dio.interceptors, orderedEquals(interceptors));
    });

    test('should keep unrelated middleware cancellation in the transport error channel', () async {
      final dio = Dio()..httpClientAdapter = ProviderDioAdapter();
      addTearDown(() => dio.close(force: true));
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            handler.reject(
              DioException.requestCancelled(requestOptions: options, reason: 'middleware'),
            );
          },
        ),
      );
      final client = ProviderHttpClient(dio: dio);
      addTearDown(client.close);
      final exit = await runtime.run(client.requestJson(url: endpoint()));
      final cause = (exit as Failed<ProviderJsonResponse, AiError>).cause;
      expect(cause, isA<Expected<AiError>>());
      expect(cause.expectedErrors.single, isA<TransportError>());
    });

    test('should retain unexpected middleware failures as defects', () async {
      final dio = Dio()..httpClientAdapter = ProviderDioAdapter();
      addTearDown(() => dio.close(force: true));
      final defect = StateError('middleware programming error');
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            handler.reject(DioException(requestOptions: options, error: defect));
          },
        ),
      );
      final client = ProviderHttpClient(dio: dio);
      addTearDown(client.close);
      final exit = await runtime.run(client.requestJson(url: endpoint()));
      expect(
        (exit as Failed<ProviderJsonResponse, AiError>).cause,
        isA<Defect<AiError>>().having((cause) => cause.error, 'error', same(defect)),
      );
    });

    test('should keep closeEffect lazy and retain cleanup defects with interruption', () async {
      server.listen((request) async {
        request.response.bufferOutput = false;
        request.response.write('{"value":"${'x' * 4096}');
        await request.response.flush();
      });
      late _ControlledAdapter adapter;
      final cleanupError = StateError('close cleanup failure');
      final dio = Dio()
        ..httpClientAdapter = ProviderDioAdapter(
          createAdapter: (factory) =>
              adapter = _ControlledAdapter(factory, cleanupError: cleanupError),
        );
      addTearDown(() => dio.close(force: true));
      final client = ProviderHttpClient(dio: dio);
      final closeProgram = client.closeEffect();
      final pending = runtime.run(client.requestJson(url: endpoint()));
      await adapter.bodyStarted.future;
      final closing = runtime.run(closeProgram);
      await adapter.cancelStarted.future;
      adapter.cancelRelease.complete();
      final closeExit = await closing;
      expect(
        (closeExit as Failed<void, Never>).cause,
        isA<Defect<Never>>().having((cause) => cause.error, 'error', same(cleanupError)),
      );
      final operationExit = await pending;
      final cause = (operationExit as Failed<ProviderJsonResponse, AiError>).cause;
      expect(cause.containsInterruption, isTrue);
      expect(_defects(cause), contains(same(cleanupError)));
      final rejected = await runtime.run(client.requestJson(url: endpoint()));
      expect(
        (rejected as Failed<ProviderJsonResponse, AiError>).cause.expectedErrors.single,
        isA<ClientClosedError>(),
      );
    });

    test('should settle an active body after provider shutdown cancels its subscription', () async {
      server.listen((request) async {
        request.response.bufferOutput = false;
        request.response.write('{"value":"${'x' * 4096}');
        await request.response.flush();
      });
      late _ControlledAdapter adapter;
      final dio = Dio()
        ..httpClientAdapter = ProviderDioAdapter(
          createAdapter: (factory) => adapter = _ControlledAdapter(factory),
        );
      addTearDown(() => dio.close(force: true));
      final client = ProviderHttpClient(dio: dio);
      final pending = runtime.run(client.requestJson(url: endpoint()));
      addTearDown(() {
        if (!adapter.cancelRelease.isCompleted) adapter.cancelRelease.complete();
      });
      await adapter.bodyStarted.future.timeout(
        const Duration(seconds: 2),
        onTimeout: () => throw StateError('body never started'),
      );
      final closing = client.close();
      await adapter.cancelStarted.future.timeout(
        const Duration(seconds: 2),
        onTimeout: () => throw StateError('cancel never started'),
      );
      adapter.cancelRelease.complete();
      await closing;
      final exit = await pending.timeout(const Duration(seconds: 1));
      expect((exit as Failed<ProviderJsonResponse, AiError>).cause, isA<Interrupted<AiError>>());
    });
  });
}

class _DelayedClient extends DelegatingHttpClient {
  _DelayedClient(super.delegate);
  final acquired = Completer<void>();
  final release = Completer<void>();
  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async {
    final request = await super.openUrl(method, url);
    acquired.complete();
    await release.future;
    return request;
  }
}

class _ControlledAdapter extends IOHttpClientAdapter {
  _ControlledAdapter(HttpClient Function() factory, {this.delayResponse = false, this.cleanupError})
    : super(createHttpClient: factory);
  final bool delayResponse;
  final Object? cleanupError;
  final headers = Completer<void>();
  final responseRelease = Completer<void>();
  final cancelStarted = Completer<void>();
  final cancelRelease = Completer<void>();
  final bodyStarted = Completer<void>();
  int cancellations = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final response = await super.fetch(options, requestStream, cancelFuture);
    final source = response.stream;
    late StreamSubscription<Uint8List> subscription;
    late StreamController<Uint8List> controller;
    controller = StreamController<Uint8List>(
      onListen: () {
        subscription = source.listen(
          (bytes) {
            controller.add(bytes);
            if (!bodyStarted.isCompleted) bodyStarted.complete();
          },
          onError: controller.addError,
          onDone: controller.close,
        );
      },
      onPause: () => subscription.pause(),
      onResume: () => subscription.resume(),
      onCancel: () async {
        cancellations++;
        cancelStarted.complete();
        await subscription.cancel();
        await cancelRelease.future;
        if (cleanupError != null) throw cleanupError!;
      },
    );
    response.stream = controller.stream;
    headers.complete();
    if (delayResponse) await responseRelease.future;
    return response;
  }
}

List<Object> _defects(Cause<AiError> cause) => switch (cause) {
  Defect<AiError>(:final error) => [error],
  Sequential<AiError>(:final causes) ||
  Parallel<AiError>(:final causes) => causes.expand(_defects).toList(),
  _ => [],
};
