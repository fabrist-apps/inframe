import 'dart:convert';
import 'dart:io';

import 'package:inlet/inlet.dart';
import 'package:test/test.dart';

void main() {
  group('Request', () {
    test('should validate methods and URIs', () {
      expect(() => Request(method: '', uri: Uri.parse('/')), throwsArgumentError);
      expect(() => Request(method: 'BAD METHOD', uri: Uri.parse('/')), throwsArgumentError);
      expect(() => Request(method: 'GET', uri: Uri.parse('relative')), throwsArgumentError);
      expect(
        () => Request(method: 'GET', uri: Uri.parse('ftp://example.com/path')),
        throwsArgumentError,
      );
      expect(
        () => Request(method: 'GET', uri: Uri.parse('http://user@example.com/path')),
        throwsArgumentError,
      );
      expect(
        () => Request(method: 'GET', uri: Uri.parse('/path#fragment')),
        throwsArgumentError,
      );

      final request = Request(
        method: 'custom',
        uri: Uri.parse('https://example.com/path?q=one&q=two'),
      );
      expect(request.method, 'custom');
      expect(request.uri.queryParametersAll['q'], ['one', 'two']);
    });

    test('should share body and admission identity between header views', () async {
      final connection = ConnectionInfo(
        remoteAddress: InternetAddress.loopbackIPv4,
        remotePort: 1234,
        localPort: 8080,
        isSecure: false,
      );
      final request = Request(
        method: 'POST',
        uri: Uri.parse('/echo'),
        headers: Headers.from({
          'x-view': ['original'],
        }),
        body: Stream.value(utf8.encode('body')),
        connection: connection,
      );
      final view = request.withHeaders(
        Headers.from({
          'x-view': ['forwarded'],
        }),
      );
      var calls = 0;
      final application = Inlet()
        ..post('/echo', (context, request) async {
          calls++;
          return Response.text(await request.text());
        });

      final response = await application.handle(view);
      addTearDown(() async {
        await response.close();
        await request.close();
      });

      expect(view.method, request.method);
      expect(view.uri, request.uri);
      expect(view.connection, same(connection));
      expect(view.pathParameters, isEmpty);
      expect(view.headers['x-view'], 'forwarded');
      expect(await response.text(), 'body');
      await expectLater(application.handle(request), throwsStateError);
      expect(calls, 1);
    });

    test('should validate connection ports', () {
      expect(
        () => ConnectionInfo(
          remoteAddress: InternetAddress.loopbackIPv4,
          remotePort: -1,
          localPort: 8080,
          isSecure: false,
        ),
        throwsArgumentError,
      );
      expect(
        () => ConnectionInfo(
          remoteAddress: InternetAddress.loopbackIPv4,
          remotePort: 1234,
          localPort: 65536,
          isSecure: false,
        ),
        throwsArgumentError,
      );
    });
  });
}
