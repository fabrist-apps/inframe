import 'package:inlet/inlet.dart';
import 'package:test/test.dart';

void main() {
  group('Request.routeTemplate', () {
    test('should expose mounted templates in middleware and header views', () async {
      final child = Router()
        ..get('/items/:id', (context, request) {
          expect(request.pathParameters['id'], 'private-id');
          return Response.text(request.routeTemplate!);
        });
      final app = Inlet()
        ..use((context, request, next) {
          expect(request.routeTemplate, '/api/items/:id');
          return next(context, request.withHeaders(request.headers.set('x-test', 'value')));
        })
        ..route('/api', child);
      final request = Request(method: 'GET', uri: Uri.parse('/api/items/private-id'));
      addTearDown(request.close);
      expect(request.routeTemplate, isNull);
      final response = await app.handle(request);
      addTearDown(response.close);
      expect(await response.text(), '/api/items/:id');
      expect(request.routeTemplate, isNull);
    });

    test('should have no template when no route is selected', () async {
      final app = Inlet()
        ..use((context, request, next) {
          expect(request.routeTemplate, isNull);
          return next(context, request);
        });
      final request = Request(method: 'GET', uri: Uri.parse('/missing'));
      addTearDown(request.close);
      final response = await app.handle(request);
      addTearDown(response.close);
      expect(response.statusCode, 404);
    });
  });
}
