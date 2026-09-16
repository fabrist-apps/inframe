// Test fixture implementing the real interface without dynamic forwarding.
import 'dart:async';
import 'dart:io';

class DelegatingHttpClient implements HttpClient {
  DelegatingHttpClient(this.delegate);
  final HttpClient delegate;
  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) => delegate.openUrl(method, url);

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
