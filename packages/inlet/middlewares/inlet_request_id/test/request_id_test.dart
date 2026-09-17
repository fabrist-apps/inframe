import 'package:chrono_id/chrono_id.dart';
import 'package:context/context.dart';
import 'package:inlet/inlet.dart';
import 'package:inlet_request_id/inlet_request_id.dart';
import 'package:test/test.dart';

void main() {
  group('requestId', () {
    test('should attach the same generated ID to context, request and response', () async {
      final base = Context();
      String? contextId;
      String? headerId;
      final app = Inlet(context: base)
        ..use(requestId)
        ..get('/', (context, request) {
          contextId = context.requestId;
          headerId = request.headers['x-request-id'];
          return Response.text('ok');
        });
      final request = Request(method: 'GET', uri: Uri.parse('/'));
      addTearDown(request.close);
      final response = await app.handle(request);
      addTearDown(response.close);

      expect(response.statusCode, 200);
      expect(contextId, isNotNull);
      expect(ChronoID.isValid(contextId!, prefix: 'req'), isTrue);
      expect(headerId, contextId);
      expect(response.headers['x-request-id'], contextId);
      expect(await response.text(), 'ok');
      expect(request.headers['x-request-id'], isNull);
      expect(() => base.requestId, throwsA(isA<MissingContextValue>()));
    });

    test('should replace incoming IDs and isolate concurrent requests', () async {
      final app = Inlet()
        ..use(requestId)
        ..post('/items/:item', (context, request) async {
          await Future<void>.delayed(Duration.zero);
          expect(request.headers['x-request-id'], context.requestId);
          expect(request.headers['x-other'], 'kept');
          expect(request.pathParameters['item'], '42');
          expect(await request.text(), 'input');
          return Response.stream(
            Stream.value([1, 2, 3]),
            status: 201,
            headers: Headers.from({
              'x-request-id': ['downstream'],
              'x-other': ['response'],
            }),
          );
        });
      final ids = await Future.wait(
        List.generate(8, (_) async {
          final request = Request(
            method: 'POST',
            uri: Uri.parse('/items/42'),
            headers: Headers.from({
              'X-Request-ID': ['incoming', 'duplicate'],
              'x-other': ['kept'],
            }),
            body: Stream.value('input'.codeUnits),
          );
          addTearDown(request.close);
          final response = await app.handle(request);
          addTearDown(response.close);
          final id = response.headers['x-request-id']!;
          expect(ChronoID.isValid(id, prefix: 'req'), isTrue);
          expect(response.headers.all('x-request-id'), [id]);
          expect(response.headers['x-other'], 'response');
          expect(response.statusCode, 201);
          expect(await response.bytes(), [1, 2, 3]);
          expect(request.headers.all('x-request-id'), ['incoming', 'duplicate']);
          return id;
        }),
      );
      expect(ids.toSet(), hasLength(ids.length));
    });

    test('should attach an ID to unmatched route responses', () async {
      final app = Inlet()..use(requestId);
      final request = Request(method: 'GET', uri: Uri.parse('/missing'));
      addTearDown(request.close);
      final response = await app.handle(request);
      addTearDown(response.close);
      expect(response.statusCode, 404);
      expect(ChronoID.isValid(response.headers['x-request-id']!, prefix: 'req'), isTrue);
    });

    test('should make the ID available to the application error handler', () async {
      final failure = StateError('handler failed');
      final app =
          Inlet(
              onReportError: (_, _) {},
              onError: (context, request, error, stackTrace) {
                expect(error, same(failure));
                expect(request.headers['x-request-id'], context.requestId);
                return Response.empty(
                  status: 500,
                  headers: const Headers.empty().set('x-request-id', context.requestId),
                );
              },
            )
            ..use(requestId)
            ..get('/', (_, _) => throw failure);
      final request = Request(method: 'GET', uri: Uri.parse('/'));
      addTearDown(request.close);
      final response = await app.handle(request);
      addTearDown(response.close);
      expect(response.statusCode, 500);
      expect(ChronoID.isValid(response.headers['x-request-id']!, prefix: 'req'), isTrue);
    });
  });
}
