import 'dart:convert';

import 'package:inlet/inlet.dart';
import 'package:test/test.dart';

void main() {
  group('Inlet', () {
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
