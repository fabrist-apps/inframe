import 'dart:io';

import 'package:inlet/inlet.dart';
import 'package:test/test.dart';

void main() {
  group('Response', () {
    test('should expose an inspectable WebSocket upgrade intent', () async {
      final response = Response.webSocket(
        onConnect: (_) {},
        headers: const Headers.empty().set('x-application', 'chat'),
      );
      addTearDown(response.close);

      expect(response.statusCode, HttpStatus.switchingProtocols);
      expect(response.isWebSocketUpgrade, isTrue);
      expect(response.headers['x-application'], 'chat');
      expect(response.headers.contains(HttpHeaders.contentTypeHeader), isFalse);
      expect(() => response.body.listen((_) {}), throwsStateError);
      await expectLater(response.bytes(), throwsStateError);
      await expectLater(response.text(), throwsStateError);
      await expectLater(response.json(), throwsStateError);
    });

    test('should validate and preserve WebSocket upgrade options', () async {
      var callbackCalls = 0;
      var selectorCalls = 0;
      final response = Response.webSocket(
        onConnect: (_) => callbackCalls++,
        selectProtocol: (_) {
          selectorCalls++;
          return null;
        },
        maxFrameBytes: 64,
        compression: CompressionOptions.compressionDefault,
      );
      final view = response.withHeaders(const Headers.empty().set('x-view', 'yes'));

      expect(view.isWebSocketUpgrade, isTrue);
      expect(view.statusCode, HttpStatus.switchingProtocols);
      expect(view.headers['x-view'], 'yes');
      expect(identical(response.close(), response.close()), isTrue);
      await view.close();
      expect(callbackCalls, 0);
      expect(selectorCalls, 0);
      expect(() => Response.webSocket(onConnect: (_) {}, maxFrameBytes: 0), throwsArgumentError);
      expect(() => Response.webSocket(onConnect: (_) {}, maxFrameBytes: -1), throwsArgumentError);
    });

    test('should reject handshake-owned WebSocket response headers', () {
      for (final name in [
        'sec-websocket-accept',
        'sec-websocket-extensions',
        'sec-websocket-protocol',
      ]) {
        final headers = Headers.from({
          name: ['value'],
        });
        expect(() => Response.webSocket(onConnect: (_) {}, headers: headers), throwsArgumentError);
        final response = Response.webSocket(onConnect: (_) {});
        expect(() => response.withHeaders(headers), throwsArgumentError);
      }
    });

    test('should snapshot constructor values and apply content types', () async {
      final document = <String, Object?>{'value': 1};
      final binary = <int>[1, 2, 3];
      final jsonResponse = Response.json(document);
      final binaryResponse = Response.bytes(binary, contentType: null);
      final explicitResponse = Response.bytes(
        binary,
        headers: Headers.from({
          'content-type': ['application/example'],
        }),
      );
      addTearDown(() async {
        await jsonResponse.close();
        await binaryResponse.close();
        await explicitResponse.close();
      });

      document['value'] = 2;
      binary[0] = 9;

      expect(await jsonResponse.json(), {'value': 1});
      expect(jsonResponse.headers['content-type'], 'application/json; charset=utf-8');
      expect(await binaryResponse.bytes(), [1, 2, 3]);
      expect(binaryResponse.headers.contains('content-type'), isFalse);
      expect(explicitResponse.headers['content-type'], 'application/example');
    });

    test('should validate status bytes and transport-owned headers', () {
      expect(() => Response.empty(status: 199), throwsArgumentError);
      expect(() => Response.empty(status: 600), throwsArgumentError);
      expect(() => Response.bytes([-1]), throwsArgumentError);
      expect(
        () => Response.text(
          'value',
          headers: Headers.from({
            HttpHeaders.contentLengthHeader: ['5'],
          }),
        ),
        throwsArgumentError,
      );
      expect(Response.empty().statusCode, HttpStatus.noContent);
      expect(Response.text('value').statusCode, HttpStatus.ok);
      expect(Response.empty().isWebSocketUpgrade, isFalse);
      expect(Response.sse(const Stream.empty()).isWebSocketUpgrade, isFalse);
    });
  });
}
