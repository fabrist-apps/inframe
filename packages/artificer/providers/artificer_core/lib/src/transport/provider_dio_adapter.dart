import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:artificer_core/src/errors.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';

/// Dio's IO adapter with an independently joinable lifetime for each request.
/// Borrowed Dio clients must install this adapter before creating a provider.
class ProviderDioAdapter implements HttpClientAdapter {
  /// Creates one IO connection pool, optionally using a configured native client.
  ///
  /// [createAdapter] supports IO adapter configuration such as certificate
  /// validation. Custom adapters must use the supplied native client factory,
  /// delegate each exchange exactly once, and preserve its response stream.
  ProviderDioAdapter({
    HttpClient Function()? createHttpClient,
    IOHttpClientAdapter Function(HttpClient Function() createHttpClient)? createAdapter,
  }) {
    HttpClient trackedClient() => _TrackingHttpClient(createHttpClient?.call() ?? HttpClient());
    _delegate =
        createAdapter?.call(trackedClient) ?? IOHttpClientAdapter(createHttpClient: trackedClient);
  }

  late final IOHttpClientAdapter _delegate;
  static final Object _zoneKey = Object();

  /// Reserved metadata key; middleware must preserve its value unchanged.
  static const String lifetimeKey = 'artificer.requestLifetime';

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    final handle = options.extra[lifetimeKey];
    if (handle is! RequestLifetime) {
      return _delegate.fetch(options, requestStream, cancelFuture);
    }
    if (handle._fetchStarted) {
      throw StateError('Provider middleware must preserve one-attempt semantics.');
    }
    handle._fetchStarted = true;
    final fetch = runZoned(() async {
      try {
        final response = await _delegate.fetch(options, requestStream, cancelFuture);
        final tracked = _TrackedStream(response.stream);
        handle._response = tracked;
        response.stream = tracked.stream;
        if (handle._disposing) await tracked.dispose();
        return response;
      } finally {
        handle._fetchCompleted.complete();
      }
    }, zoneValues: {_zoneKey: handle});
    return fetch;
  }

  @override
  void close({bool force = false}) => _delegate.close(force: force);
}

/// Internal operation ownership shared by the client and its installed adapter.
class RequestLifetime {
  /// Cancellation signal unique to this execution.
  final CancelToken token = CancelToken();
  final Completer<void> _fetchCompleted = Completer<void>();

  /// Conservative evidence about whether a failed attempt reached the service.
  DeliveryState get deliveryState => _response != null
      ? DeliveryState.responseStarted
      : _nativeRequest != null
      ? DeliveryState.mayHaveReachedProvider
      : DeliveryState.notSent;

  Future<void>? _acquisition;
  HttpClientRequest? _nativeRequest;
  _TrackedStream? _response;
  bool _fetchStarted = false;
  bool _disposing = false;

  /// Whether cancellation originated with the SDK or Conflux.
  bool interrupted = false;
  Future<void>? _disposal;

  /// Stops this attempt and joins all resources it acquired.
  Future<void> dispose({bool interrupt = false}) {
    interrupted |= interrupt;
    _disposing = true;
    token.cancel('Provider request released');
    _nativeRequest?.abort();
    return _disposal ??= _dispose();
  }

  Future<void> _dispose() async {
    Object? cleanupError;
    StackTrace? cleanupStack;
    try {
      await _response?.dispose();
    } on Object catch (error, stack) {
      cleanupError = error;
      cleanupStack = stack;
    }
    // Even a broken stream disposer must not skip a late native acquisition.
    if (_fetchStarted) await _fetchCompleted.future;
    await _acquisition;
    try {
      // Dio can discard a response which arrives after its cancellation race.
      await _response?.dispose();
    } on Object catch (error, stack) {
      cleanupError ??= error;
      cleanupStack ??= stack;
    }
    if (cleanupError != null) Error.throwWithStackTrace(cleanupError, cleanupStack!);
  }
}

class _TrackedStream {
  _TrackedStream(Stream<Uint8List> source) {
    _controller = StreamController<Uint8List>(sync: true);
    _controller.onListen = () {
      _subscription = source.listen(
        _controller.add,
        onError: _controller.addError,
        onDone: _controller.close,
      );
    };
    _controller.onPause = () => _subscription?.pause();
    _controller.onResume = () => _subscription?.resume();
    _controller.onCancel = () async {
      // Dio initiates cancellation without awaiting its Future. The request
      // owner observes the original error through dispose instead, avoiding an
      // unhandled asynchronous error while preserving the cleanup defect.
      try {
        await _cancel();
      } on Object {
        // Reported by the protected operation finalizer.
      }
    };
  }
  late final StreamController<Uint8List> _controller;
  StreamSubscription<Uint8List>? _subscription;
  Future<void>? _cancellation;
  Stream<Uint8List> get stream => _controller.stream;
  Future<void> _cancel() => _cancellation ??= _subscription?.cancel() ?? Future.value();
  Future<void> dispose() async {
    if (!_controller.hasListener && _subscription == null) {
      // Listening then cancelling releases an otherwise unconsumed native body.
      final subscription = stream.listen((_) {}, onError: (Object _) {});
      await subscription.cancel();
    }
    await _cancel();
  }
}

/// Full public HttpClient delegation; only native acquisition is intercepted.
class _TrackingHttpClient implements HttpClient {
  _TrackingHttpClient(this.delegate);
  final HttpClient delegate;
  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) {
    final handle = Zone.current[ProviderDioAdapter._zoneKey];
    if (handle is! RequestLifetime) return delegate.openUrl(method, url);
    final acquired = delegate.openUrl(method, url).then((request) async {
      if (handle._disposing) {
        request.abort();
        await request.done.then<void>((_) {}, onError: (Object _, StackTrace _) {});
        throw StateError('Native request acquired after release.');
      }
      handle._nativeRequest = request;
      return request;
    });
    handle._acquisition = acquired.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return acquired;
  }

  @override
  Duration get idleTimeout => delegate.idleTimeout;
  @override
  set idleTimeout(Duration value) => delegate.idleTimeout = value;
  @override
  Duration? get connectionTimeout => delegate.connectionTimeout;
  @override
  set connectionTimeout(Duration? value) => delegate.connectionTimeout = value;
  @override
  int? get maxConnectionsPerHost => delegate.maxConnectionsPerHost;
  @override
  set maxConnectionsPerHost(int? value) => delegate.maxConnectionsPerHost = value;
  @override
  bool get autoUncompress => delegate.autoUncompress;
  @override
  set autoUncompress(bool value) => delegate.autoUncompress = value;
  @override
  String? get userAgent => delegate.userAgent;
  @override
  set userAgent(String? value) => delegate.userAgent = value;
  @override
  Future<HttpClientRequest> open(String method, String host, int port, String path) =>
      delegate.open(method, host, port, path);
  @override
  Future<HttpClientRequest> get(String host, int port, String path) =>
      delegate.get(host, port, path);
  @override
  Future<HttpClientRequest> getUrl(Uri url) => delegate.getUrl(url);
  @override
  Future<HttpClientRequest> post(String host, int port, String path) =>
      delegate.post(host, port, path);
  @override
  Future<HttpClientRequest> postUrl(Uri url) => delegate.postUrl(url);
  @override
  Future<HttpClientRequest> put(String host, int port, String path) =>
      delegate.put(host, port, path);
  @override
  Future<HttpClientRequest> putUrl(Uri url) => delegate.putUrl(url);
  @override
  Future<HttpClientRequest> delete(String host, int port, String path) =>
      delegate.delete(host, port, path);
  @override
  Future<HttpClientRequest> deleteUrl(Uri url) => delegate.deleteUrl(url);
  @override
  Future<HttpClientRequest> patch(String host, int port, String path) =>
      delegate.patch(host, port, path);
  @override
  Future<HttpClientRequest> patchUrl(Uri url) => delegate.patchUrl(url);
  @override
  Future<HttpClientRequest> head(String host, int port, String path) =>
      delegate.head(host, port, path);
  @override
  Future<HttpClientRequest> headUrl(Uri url) => delegate.headUrl(url);
  @override
  set authenticate(Future<bool> Function(Uri, String, String?)? callback) =>
      delegate.authenticate = callback;
  @override
  void addCredentials(Uri url, String realm, HttpClientCredentials credentials) =>
      delegate.addCredentials(url, realm, credentials);
  @override
  set connectionFactory(Future<ConnectionTask<Socket>> Function(Uri, String?, int?)? callback) =>
      delegate.connectionFactory = callback;
  @override
  set findProxy(String Function(Uri)? callback) => delegate.findProxy = callback;
  @override
  set authenticateProxy(Future<bool> Function(String, int, String, String?)? callback) =>
      delegate.authenticateProxy = callback;
  @override
  void addProxyCredentials(
    String host,
    int port,
    String realm,
    HttpClientCredentials credentials,
  ) => delegate.addProxyCredentials(host, port, realm, credentials);
  @override
  set badCertificateCallback(bool Function(X509Certificate, String, int)? callback) =>
      delegate.badCertificateCallback = callback;
  @override
  set keyLog(void Function(String)? callback) => delegate.keyLog = callback;
  @override
  void close({bool force = false}) => delegate.close(force: force);
}
