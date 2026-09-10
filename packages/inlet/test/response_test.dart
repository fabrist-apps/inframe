import 'dart:io';

import 'package:inlet/inlet.dart';
import 'package:test/test.dart';

void main() {
  group('Response', () {
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
    });
  });
}
