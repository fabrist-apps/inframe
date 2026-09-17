import 'package:inlet/inlet.dart';
import 'package:test/test.dart';

void main() {
  group('Request.onResponse', () {
    test('should run once in reverse order after error recovery with forwarded values', () async {
      final order = <String>[];
      final app =
          Inlet(
              onReportError: (_, _) {},
              onError: (_, _, _, _) => Response.text('recovered', status: 422),
            )
            ..use((context, request, next) {
              request.onResponse((context, request, response) {
                order.add('outer');
                expect(request.headers['x-forwarded'], 'yes');
                expect(response.statusCode, 422);
                expect(response.headers['x-inner'], 'yes');
                return response.withHeaders(response.headers.set('x-outer', 'yes'));
              });
              return next(context, request.withHeaders(request.headers.set('x-forwarded', 'yes')));
            })
            ..use((context, request, next) {
              request.onResponse((context, request, response) {
                order.add('inner');
                return response.withHeaders(response.headers.set('x-inner', 'yes'));
              });
              return next(context, request);
            })
            ..get('/', (_, _) => throw StateError('failed'));
      final request = Request(method: 'GET', uri: Uri.parse('/'));
      addTearDown(request.close);
      final response = await app.handle(request);
      addTearDown(response.close);
      expect(order, ['inner', 'outer']);
      expect(response.headers['x-outer'], 'yes');
      expect(await response.text(), 'recovered');
    });

    test('should contain hook failures and reject replacement bodies', () async {
      final reported = <Object>[];
      final failure = StateError('hook failed');
      final rejected = Response.text('wrong', status: 201);
      final app = Inlet(onReportError: (error, _) => reported.add(error))
        ..use((context, request, next) {
          request
            ..onResponse(
              (_, _, response) => response.withHeaders(
                response.headers.set('x-completed', 'yes'),
              ),
            )
            ..onResponse((_, _, _) => rejected)
            ..onResponse((_, _, _) => throw failure);
          return next(context, request);
        })
        ..get('/', (_, _) => Response.text('original'));
      final request = Request(method: 'GET', uri: Uri.parse('/'));
      addTearDown(request.close);
      final response = await app.handle(request);
      addTearDown(response.close);
      expect(response.statusCode, 200);
      expect(response.headers['x-completed'], 'yes');
      expect(await response.text(), 'original');
      expect(reported, hasLength(2));
      expect(reported.first, same(failure));
      expect(reported.last, isA<StateError>());
      await expectLater(rejected.text(), throwsStateError);
    });

    test('should reject late registration through any request view', () async {
      final app = Inlet()..get('/', (_, _) => Response.empty());
      final request = Request(method: 'GET', uri: Uri.parse('/'));
      final viewed = request.withHeaders(const Headers.empty());
      addTearDown(request.close);
      request.onResponse((_, _, response) {
        expect(() => viewed.onResponse((_, _, response) => response), throwsStateError);
        return response;
      });
      final response = await app.handle(request);
      addTearDown(response.close);
      expect(() => request.onResponse((_, _, response) => response), throwsStateError);
    });

    test('should observe HEAD finalization without listening to a body', () async {
      var listened = false;
      Stream<List<int>> body() async* {
        listened = true;
        yield [1];
      }

      var calls = 0;
      final app = Inlet()
        ..use((context, request, next) {
          request.onResponse((_, _, response) {
            calls++;
            return response.withHeaders(response.headers.set('x-hook', 'yes'));
          });
          return next(context, request);
        })
        ..get('/', (_, _) => Response.stream(body()));
      final request = Request(method: 'HEAD', uri: Uri.parse('/'));
      addTearDown(request.close);
      final response = await app.handle(request);
      addTearDown(response.close);
      expect(response.headers['x-hook'], 'yes');
      expect(await response.bytes(), isEmpty);
      expect(listened, isFalse);
      expect(calls, 1);
    });
  });
}
