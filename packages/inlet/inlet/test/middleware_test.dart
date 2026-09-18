import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:context/context.dart';
import 'package:inlet/inlet.dart';
import 'package:test/test.dart';

void main() {
  group('Inlet middleware', () {
    test('should enter every matched scope and unwind in reverse', () async {
      final events = <String>[];
      Middleware named(String name) => (context, request, next) async {
        events.add('$name enter:${request.pathParameters['id']}');
        final response = await next(context, request);
        events.add('$name exit:${request.pathParameters['id']}');
        return response;
      };

      final leaf = Router()
        ..use(named('leaf'))
        ..get(
          '/items/:id',
          (_, request) {
            events.add('handler:${request.pathParameters['id']}');
            return Response.empty();
          },
          middleware: [named('route one'), named('route two')],
        );
      final child = Router()
        ..use(named('child'))
        ..route('/v1', leaf);
      final application = Inlet()
        ..route('/api', child)
        ..use(named('root one'))
        ..use(named('root two'));

      final exchange = await _dispatch(application, 'GET', '/api/v1/items/42');
      await exchange.close();

      expect(events, [
        'root one enter:42',
        'root two enter:42',
        'child enter:42',
        'leaf enter:42',
        'route one enter:42',
        'route two enter:42',
        'handler:42',
        'route two exit:42',
        'route one exit:42',
        'leaf exit:42',
        'child exit:42',
        'root two exit:42',
        'root one exit:42',
      ]);
    });

    test('should run only root middleware for routing responses', () async {
      final statuses = <int>[];
      final child = Router()
        ..use((context, request, next) {
          fail('child middleware must not run for routing failures');
        })
        ..get('/item', (_, _) => Response.empty());
      final application = Inlet()
        ..route('/api', child)
        ..use((context, request, next) async {
          final response = await next(context, request);
          statuses.add(response.statusCode);
          return response;
        });

      final missing = await _dispatch(application, 'GET', '/missing');
      final unsupported = await _dispatch(application, 'POST', '/api/item');
      final malformed = await _dispatch(application, 'GET', '/%FF');
      await Future.wait([missing.close(), unsupported.close(), malformed.close()]);

      expect(statuses, [404, 405, 400]);
      expect(unsupported.response.headers['allow'], 'GET, HEAD');
    });

    test('should allow middleware to return before the handler', () async {
      var handlerCalls = 0;
      final application = Inlet()
        ..use((_, _, _) => Response.text('early'))
        ..get('/resource', (_, _) {
          handlerCalls++;
          return Response.text('late');
        });

      final exchange = await _dispatch(application, 'GET', '/resource');
      expect(await exchange.response.text(), 'early');
      expect(handlerCalls, 0);
      await exchange.close();
    });

    test('should reject reused, late, and unrelated continuations', () async {
      final reports = <Object>[];
      late Next lateNext;
      late Context forwardedContext;
      late Request forwardedRequest;
      var handlerCalls = 0;
      final application = Inlet(onReportError: (error, _) => reports.add(error))
        ..use((context, request, next) async {
          lateNext = next;
          forwardedContext = context;
          forwardedRequest = request;
          final first = next(context, request);
          expect(() => next(context, request), throwsStateError);
          final unrelated = Request(method: 'GET', uri: Uri.parse('/resource'));
          addTearDown(unrelated.close);
          expect(() => next(context, unrelated), throwsStateError);
          return first;
        })
        ..get('/resource', (_, _) {
          handlerCalls++;
          return Response.empty();
        });

      final exchange = await _dispatch(application, 'GET', '/resource');
      expect(handlerCalls, 1);
      expect(
        () => lateNext(forwardedContext, forwardedRequest),
        throwsStateError,
      );
      expect(reports, hasLength(3));
      expect(reports, everyElement(isA<StateError>()));
      await exchange.close();
    });

    test('should reject an earlier request view after routing adds captures', () async {
      final reports = <Object>[];
      final original = Request(method: 'GET', uri: Uri.parse('/items/42'));
      final application = Inlet(onReportError: (error, _) => reports.add(error))
        ..use((context, request, next) {
          expect(() => next(context, original), throwsStateError);
          return next(context, request);
        })
        ..get('/items/:id', (_, request) => Response.text(request.pathParameters['id']!));

      final response = await application.handle(original);

      expect(await response.text(), '42');
      expect(reports, hasLength(1));
      await response.close();
      await original.close();
    });

    test('should fail and close responses when middleware abandons downstream work', () async {
      final release = Completer<void>();
      final reports = <Object>[];
      late Response premature;
      late Response orphan;
      final application = Inlet(onReportError: (error, _) => reports.add(error))
        ..use((context, request, next) {
          unawaited(next(context, request));
          return premature = Response.text('premature');
        })
        ..get('/resource', (_, _) async {
          await release.future;
          return orphan = Response.text('orphan');
        });

      final exchange = await _dispatch(application, 'GET', '/resource');
      expect(exchange.response.statusCode, HttpStatus.internalServerError);
      await expectLater(premature.bytes(), throwsStateError);
      release.complete();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      await expectLater(orphan.bytes(), throwsStateError);
      expect(reports, hasLength(1));
      expect(reports.single, isA<StateError>());
      await exchange.close();
    });

    test('should report abandoned downstream work even when outer middleware catches it', () async {
      final release = Completer<void>();
      final reports = <Object>[];
      late Response premature;
      late Response orphan;
      final application = Inlet(onReportError: (error, _) => reports.add(error))
        ..use((context, request, next) async {
          try {
            return await next(context, request);
          } on Object catch (error) {
            if (error is StateError) {
              return Response.text('caught');
            }
            rethrow;
          }
        })
        ..use((context, request, next) {
          unawaited(next(context, request));
          return premature = Response.text('premature');
        })
        ..get('/resource', (_, _) async {
          await release.future;
          return orphan = Response.text('orphan');
        });

      final exchange = await _dispatch(application, 'GET', '/resource');

      expect(await exchange.response.text(), 'caught');
      expect(reports, hasLength(1));
      await expectLater(premature.bytes(), throwsStateError);
      release.complete();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      await expectLater(orphan.bytes(), throwsStateError);
      expect(reports, hasLength(1));
      await exchange.close();
    });

    test('should forward derived context and request views without mutation', () async {
      final requestId = ContextKey<String>('request ID');
      final base = Context().withBinding(requestId.bind('base'));
      final override = Context().withBinding(requestId.bind('override'));
      final application = Inlet(context: base)
        ..use((context, request, next) {
          final derived = context.withBinding(requestId.bind('derived'));
          final viewed = request.withHeaders(request.headers.set('x-view', 'yes'));
          return next(derived, viewed);
        })
        ..get('/items/:id', (context, request) {
          return Response.json({
            'context': context.require(requestId),
            'header': request.headers['x-view'],
            'capture': request.pathParameters['id'],
          });
        });

      final request = Request(method: 'GET', uri: Uri.parse('/items/42'));
      final response = await application.handle(request, context: override);
      expect(await response.json(), {
        'context': 'derived',
        'header': 'yes',
        'capture': '42',
      });
      expect(base.require(requestId), 'base');
      expect(override.require(requestId), 'override');
      expect(request.headers['x-view'], isNull);
      await response.close();
      await request.close();
    });

    test('should let outer middleware catch downstream errors', () async {
      var hookCalls = 0;
      final reports = <Object>[];
      final application =
          Inlet(
              onError: (_, _, _, _) {
                hookCalls++;
                return Response.text('hook');
              },
              onReportError: (error, _) => reports.add(error),
            )
            ..use((context, request, next) async {
              try {
                return await next(context, request);
              } on Object catch (error) {
                if (error is StateError) {
                  return Response.text('caught');
                }
                rethrow;
              }
            })
            ..get('/resource', (_, _) => throw StateError('handler failed'));

      final exchange = await _dispatch(application, 'GET', '/resource');
      expect(await exchange.response.text(), 'caught');
      expect(hookCalls, 0);
      expect(reports, isEmpty);
      await exchange.close();
    });

    test('should recover with the latest valid forwarded values', () async {
      final requestId = ContextKey<String>('request ID');
      var hookCalls = 0;
      final reports = <Object>[];
      final application =
          Inlet(
              onError: (context, request, error, _) {
                hookCalls++;
                return Response.json({
                  'id': context.require(requestId),
                  'header': request.headers['x-forwarded'],
                  'error': error.toString(),
                });
              },
              onReportError: (error, _) => reports.add(error),
            )
            ..use((context, request, next) {
              return next(
                context.withBinding(requestId.bind('deepest')),
                request.withHeaders(request.headers.set('x-forwarded', 'yes')),
              );
            })
            ..get('/resource', (_, _) => throw StateError('failed'));

      final exchange = await _dispatch(application, 'GET', '/resource');
      expect(await exchange.response.json(), {
        'id': 'deepest',
        'header': 'yes',
        'error': 'Bad state: failed',
      });
      expect(hookCalls, 1);
      expect(reports, hasLength(1));
      await exchange.close();
    });

    test('should map body failures and report only unexpected failures', () async {
      final reports = <Object>[];
      final application = Inlet(onReportError: (error, _) => reports.add(error))
        ..post('/json', (_, request) async {
          await request.json();
          return Response.empty();
        })
        ..post('/limited', (_, request) async {
          await request.bytes(maxBytes: 1);
          return Response.empty();
        })
        ..get('/failed', (_, _) => throw StateError('failed'));

      final malformed = await _dispatch(
        application,
        'POST',
        '/json',
        body: utf8.encode('{bad'),
      );
      final oversized = await _dispatch(
        application,
        'POST',
        '/limited',
        body: [1, 2],
      );
      final failed = await _dispatch(application, 'GET', '/failed');

      expect(malformed.response.statusCode, HttpStatus.badRequest);
      expect(oversized.response.statusCode, HttpStatus.requestEntityTooLarge);
      expect(failed.response.statusCode, HttpStatus.internalServerError);
      expect(await malformed.response.bytes(), isEmpty);
      expect(await oversized.response.bytes(), isEmpty);
      expect(await failed.response.bytes(), isEmpty);
      expect(reports, hasLength(1));
      expect(reports.single, isA<StateError>());
      await Future.wait([malformed.close(), oversized.close(), failed.close()]);
    });

    test('should let the error hook replace typed defaults and survive hook failure', () async {
      final typedReports = <Object>[];
      final typed =
          Inlet(
            onError: (_, _, error, _) => Response.text(error.runtimeType.toString(), status: 422),
            onReportError: (error, _) => typedReports.add(error),
          )..post('/json', (_, request) async {
            await request.json();
            return Response.empty();
          });
      final typedExchange = await _dispatch(
        typed,
        'POST',
        '/json',
        body: utf8.encode('{bad'),
      );

      final hookReports = <Object>[];
      var hookCalls = 0;
      final brokenHook = Inlet(
        onError: (_, _, _, _) {
          hookCalls++;
          throw StateError('hook failed');
        },
        onReportError: (error, _) => hookReports.add(error),
      )..get('/failed', (_, _) => throw StateError('handler failed'));
      final brokenExchange = await _dispatch(brokenHook, 'GET', '/failed');

      expect(typedExchange.response.statusCode, 422);
      expect(await typedExchange.response.text(), 'MalformedBodyException');
      expect(typedReports, isEmpty);
      expect(brokenExchange.response.statusCode, HttpStatus.internalServerError);
      expect(hookCalls, 1);
      expect(hookReports, hasLength(2));
      expect(hookReports.map((error) => error.toString()), [
        'Bad state: handler failed',
        'Bad state: hook failed',
      ]);
      await Future.wait([typedExchange.close(), brokenExchange.close()]);
    });

    test('should isolate concurrent continuations and forwarded error context', () async {
      final requestId = ContextKey<String>('request ID');
      final gates = <String, Completer<void>>{
        'one': Completer<void>(),
        'two': Completer<void>(),
      };
      final application =
          Inlet(
              onError: (context, request, _, _) => Response.text(
                '${context.require(requestId)}:${request.headers['x-request-id']}',
              ),
              onReportError: (_, _) {},
            )
            ..use((context, request, next) {
              final id = request.pathParameters['id']!;
              return next(
                context.withBinding(requestId.bind(id)),
                request.withHeaders(request.headers.set('x-request-id', id)),
              );
            })
            ..get('/work/:id', (_, request) async {
              await gates[request.pathParameters['id']]!.future;
              throw StateError('failed');
            });

      final oneRequest = Request(method: 'GET', uri: Uri.parse('/work/one'));
      final twoRequest = Request(method: 'GET', uri: Uri.parse('/work/two'));
      final oneFuture = application.handle(oneRequest);
      final twoFuture = application.handle(twoRequest);
      gates['two']!.complete();
      final two = await twoFuture;
      gates['one']!.complete();
      final one = await oneFuture;

      expect(await one.text(), 'one:one');
      expect(await two.text(), 'two:two');
      await Future.wait([
        one.close(),
        two.close(),
        oneRequest.close(),
        twoRequest.close(),
      ]);
    });

    test('should allow middleware to rebuild an inspected response', () async {
      final application = Inlet()
        ..use((context, request, next) async {
          final response = await next(context, request);
          final bytes = await response.bytes();
          await response.close();
          return Response.bytes(
            bytes,
            status: response.statusCode,
            headers: response.headers.set('x-inspected', 'yes'),
            contentType: null,
          );
        })
        ..get('/resource', (_, _) => Response.text('content'));

      final exchange = await _dispatch(application, 'GET', '/resource');
      expect(await exchange.response.text(), 'content');
      expect(exchange.response.headers['x-inspected'], 'yes');
      await exchange.close();
    });

    test('should suppress HEAD bodies after middleware and error recovery', () async {
      var bodySubscriptions = 0;
      Response streamed(String value) => Response.stream(
        Stream<List<int>>.multi((controller) {
          bodySubscriptions++;
          unawaited((controller..add(utf8.encode(value))).close());
        }),
      );
      final middlewareResponse = Inlet()
        ..use((_, _, _) => streamed('middleware'))
        ..get('/resource', (_, _) => streamed('handler'));
      final errorResponse = Inlet(
        onError: (_, _, _, _) => streamed('error'),
        onReportError: (_, _) {},
      )..get('/resource', (_, _) => throw StateError('failed'));

      final fromMiddleware = await _dispatch(
        middlewareResponse,
        'HEAD',
        '/resource',
      );
      final fromError = await _dispatch(errorResponse, 'HEAD', '/resource');

      final routingResponse = Inlet()
        ..use((context, request, next) async {
          final response = await next(context, request);
          await response.close();
          return streamed('routing');
        });
      final fromRouting = await _dispatch(routingResponse, 'HEAD', '/missing');

      expect(await fromMiddleware.response.bytes(), isEmpty);
      expect(await fromError.response.bytes(), isEmpty);
      expect(await fromRouting.response.bytes(), isEmpty);
      expect(bodySubscriptions, 0);
      await Future.wait([
        fromMiddleware.close(),
        fromError.close(),
        fromRouting.close(),
      ]);
    });
  });
}

Future<_Exchange> _dispatch(
  Inlet application,
  String method,
  String path, {
  List<int>? body,
}) async {
  final request = Request(
    method: method,
    uri: Uri.parse(path),
    body: body == null ? const Stream.empty() : Stream.value(body),
  );
  final response = await application.handle(request);
  return _Exchange(request, response);
}

final class _Exchange {
  const _Exchange(this.request, this.response);

  final Request request;
  final Response response;

  Future<void> close() async {
    await response.close();
    await request.close();
  }
}
