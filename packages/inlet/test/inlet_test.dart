import 'dart:convert';
import 'dart:io';

import 'package:inlet/inlet.dart';
import 'package:test/test.dart';

void main() {
  group('Inlet', () {
    test('should return a WebSocket intent in process without invoking callbacks', () async {
      var callbackCalls = 0;
      var selectorCalls = 0;
      final application = Inlet()
        ..get('/chat', (_, _) {
          return Response.webSocket(
            onConnect: (_) => callbackCalls++,
            selectProtocol: (_) {
              selectorCalls++;
              return 'chat.v1';
            },
          );
        });
      final request = Request(
        method: 'GET',
        uri: Uri.parse('/chat'),
        headers: const Headers.empty().set('sec-websocket-protocol', ',invalid'),
      );
      final response = await application.handle(request);
      addTearDown(() async {
        await response.close();
        await request.close();
      });

      expect(response.isWebSocketUpgrade, isTrue);
      expect(response.statusCode, HttpStatus.switchingProtocols);
      expect(callbackCalls, 0);
      expect(selectorCalls, 0);
    });

    test('should reject a WebSocket intent from HEAD fallback', () async {
      var callbackCalls = 0;
      final application = Inlet()
        ..get('/chat', (_, _) => Response.webSocket(onConnect: (_) => callbackCalls++));
      final request = Request(method: 'HEAD', uri: Uri.parse('/chat'));
      final response = await application.handle(request);
      addTearDown(() async {
        await response.close();
        await request.close();
      });

      expect(response.statusCode, HttpStatus.methodNotAllowed);
      expect(response.headers[HttpHeaders.allowHeader], 'GET');
      expect(response.isWebSocketUpgrade, isFalse);
      expect(await response.bytes(), isEmpty);
      expect(callbackCalls, 0);
    });

    test('should run a JSON handler in process', () async {
      final encodedBody = utf8.encode('{"message":"hello"}');
      final application = Inlet()
        ..post('/echo', (context, request) async {
          final document = await request.json(maxBytes: encodedBody.length);
          return Response.json(document);
        });
      final request = Request(
        method: 'POST',
        uri: Uri.parse('/echo'),
        body: Stream.value(encodedBody),
      );

      final response = await application.handle(request);
      addTearDown(() async {
        await response.close();
        await request.close();
      });

      expect(response.statusCode, 200);
      expect(response.headers['content-type'], 'application/json; charset=utf-8');
      expect(await response.json(), {'message': 'hello'});
    });
  });
}
