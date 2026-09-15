import 'dart:convert';
import 'dart:io';

import 'package:clickhouse/clickhouse.dart';

const validResult = '{"meta":[{"name":"value","type":"UInt8"}],"data":[{"value":1}],"rows":1}';

ClickHouseClient createClient(
  String endpoint, {
  String password = 'secret',
  Duration timeout = const Duration(seconds: 30),
  int maxRequestBytes = 16 * 1024 * 1024,
  int maxResponseBytes = 16 * 1024 * 1024,
}) => ClickHouseClient(
  endpoint: endpoint,
  database: 'analytics',
  username: 'tester',
  password: password,
  timeout: timeout,
  maxRequestBytes: maxRequestBytes,
  maxResponseBytes: maxResponseBytes,
  allowInsecureHttp: true,
);

String serverUrl(HttpServer server) => 'http://${server.address.host}:${server.port}';

Future<HttpServer> jsonServer(Object? body) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    request.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(body));
    await request.response.close();
  });
  return server;
}

Future<HttpServer> responseServer(
  List<int> body, {
  int statusCode = HttpStatus.ok,
  String? contentEncoding,
  String? queryId,
  int? exceptionCode,
}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    await request.drain<void>();
    request.response.statusCode = statusCode;
    if (contentEncoding != null) {
      request.response.headers.set(HttpHeaders.contentEncodingHeader, contentEncoding);
    }
    if (queryId != null) {
      request.response.headers.set('x-clickhouse-query-id', queryId);
    }
    if (exceptionCode != null) {
      request.response.headers.set('x-clickhouse-exception-code', exceptionCode);
    }
    request.response.add(body);
    await request.response.close();
  });
  return server;
}
