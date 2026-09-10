import 'dart:async';
import 'dart:convert';

import 'package:inlet/inlet.dart';
import 'package:test/test.dart';

void main() {
  group('Request body', () {
    test('should share one buffered read and return private copies', () async {
      final source = _TrackedByteSource();
      final request = Request(method: 'POST', uri: Uri.parse('/'), body: source.stream);
      final encoded = utf8.encode('{"items":[1]}');

      final firstBytes = request.bytes(maxBytes: encoded.length);
      final text = request.text(maxBytes: encoded.length);
      final document = request.json(maxBytes: encoded.length);
      source
        ..add(encoded)
        ..close();

      final first = await firstBytes;
      expect(await text, '{"items":[1]}');
      expect(await document, {
        'items': [1],
      });
      first[0] = 0;
      expect(await request.bytes(maxBytes: encoded.length), encoded);
      expect(source.listens, 1);
      await request.close();
    });

    test('should enforce each reader limit without invalidating the cache', () async {
      final source = _TrackedByteSource();
      final request = Request(method: 'POST', uri: Uri.parse('/'), body: source.stream);

      final larger = request.bytes(maxBytes: 4);
      final smallerExpectation = expectLater(
        request.bytes(maxBytes: 3),
        throwsA(
          isA<BodyLimitExceededException>().having(
            (error) => error.maxBytes,
            'maxBytes',
            3,
          ),
        ),
      );
      source
        ..add([1, 2, 3, 4])
        ..close();

      expect(await larger, [1, 2, 3, 4]);
      await smallerExpectation;
      expect(await request.bytes(maxBytes: 4), [1, 2, 3, 4]);
      expect(source.listens, 1);
      await request.close();
    });

    test('should preserve the first physical limit failure', () async {
      final source = _TrackedByteSource();
      final request = Request(method: 'POST', uri: Uri.parse('/'), body: source.stream);
      final physicalLimit = request.bytes(maxBytes: 3);
      final largerLimit = request.bytes(maxBytes: 100);
      final physicalExpectation = expectLater(
        physicalLimit,
        throwsA(
          isA<BodyLimitExceededException>().having(
            (error) => error.maxBytes,
            'maxBytes',
            3,
          ),
        ),
      );
      final largerExpectation = expectLater(
        largerLimit,
        throwsA(
          isA<BodyLimitExceededException>().having(
            (error) => error.maxBytes,
            'maxBytes',
            3,
          ),
        ),
      );

      source.add([1, 2, 3, 4]);

      await physicalExpectation;
      await largerExpectation;
      await expectLater(
        request.bytes(maxBytes: 1000),
        throwsA(
          isA<BodyLimitExceededException>().having(
            (error) => error.maxBytes,
            'maxBytes',
            3,
          ),
        ),
      );
      expect(source.listens, 1);
      await request.close();
    });

    test('should reject a negative limit without listening', () async {
      final source = _TrackedByteSource();
      final request = Request(method: 'POST', uri: Uri.parse('/'), body: source.stream);

      await expectLater(request.bytes(maxBytes: -1), throwsArgumentError);

      expect(source.listens, 0);
      final validRead = request.bytes(maxBytes: 1);
      source
        ..add([1])
        ..close();
      expect(await validRead, [1]);
      expect(source.listens, 1);
      await request.close();
    });

    test('should accept an empty body with a zero limit', () async {
      final request = Request(method: 'POST', uri: Uri.parse('/'));

      expect(await request.bytes(maxBytes: 0), isEmpty);

      await request.close();
    });

    test('should default buffering to one mebibyte', () async {
      final request = Request(
        method: 'POST',
        uri: Uri.parse('/'),
        body: Stream.value(List<int>.filled(1024 * 1024 + 1, 0)),
      );

      await expectLater(
        request.bytes(),
        throwsA(
          isA<BodyLimitExceededException>().having(
            (error) => error.maxBytes,
            'maxBytes',
            1024 * 1024,
          ),
        ),
      );

      await request.close();
    });

    test('should keep cached bytes after malformed JSON', () async {
      final encoded = utf8.encode('{not-json}');
      final request = Request(
        method: 'POST',
        uri: Uri.parse('/'),
        body: Stream.value(encoded),
      );

      await expectLater(request.json(), throwsA(isA<MalformedBodyException>()));
      expect(await request.text(), '{not-json}');
      expect(await request.bytes(), encoded);

      await request.close();
    });

    test('should strictly reject malformed UTF-8 without losing bytes', () async {
      final request = Request(
        method: 'POST',
        uri: Uri.parse('/'),
        body: Stream.value([0xC3, 0x28]),
      );

      await expectLater(request.text(), throwsA(isA<MalformedBodyException>()));
      expect(await request.bytes(), [0xC3, 0x28]);

      await request.close();
    });

    test('should decode independent mutable JSON collections', () async {
      final request = Request(
        method: 'POST',
        uri: Uri.parse('/'),
        body: Stream.value(utf8.encode('{"items":[1]}')),
      );

      final first = (await request.json())! as Map<String, Object?>;
      final second = (await request.json())! as Map<String, Object?>;
      (first['items']! as List<Object?>).add(2);

      expect(first, {
        'items': [1, 2],
      });
      expect(second, {
        'items': [1],
      });
      expect(identical(first, second), isFalse);
      await request.close();
    });

    test('should leave the body untouched until the raw stream is listened to', () async {
      final source = _TrackedByteSource();
      final request = Request(method: 'POST', uri: Uri.parse('/'), body: source.stream);

      final rawBody = request.body;
      expect(source.listens, 0);
      final buffered = request.bytes();
      source
        ..add([1, 2, 3])
        ..close();

      expect(await buffered, [1, 2, 3]);
      expect(() => rawBody.listen(null), throwsStateError);
      await request.close();
    });

    test('should keep raw streaming exclusive after completion', () async {
      final source = _TrackedByteSource();
      final request = Request(method: 'POST', uri: Uri.parse('/'), body: source.stream);

      final streamed = request.body.toList();
      final bufferingExpectation = expectLater(request.bytes(), throwsStateError);
      source
        ..add([1])
        ..add([2])
        ..close();

      expect(await streamed, [
        [1],
        [2],
      ]);
      await bufferingExpectation;
      expect(() => request.body.listen(null), throwsStateError);
      await request.close();
    });

    test('should propagate raw pause resume and cancellation', () async {
      final cancelGate = Completer<void>();
      final source = _TrackedByteSource(cancelGate: cancelGate);
      final request = Request(method: 'POST', uri: Uri.parse('/'), body: source.stream);
      final received = <List<int>>[];
      final firstReceived = Completer<void>();
      final subscription = request.body.listen((chunk) {
        received.add(chunk);
        if (!firstReceived.isCompleted) {
          firstReceived.complete();
        }
      });

      source.add([1]);
      await firstReceived.future;
      subscription.pause();
      expect(source.pauses, 1);
      source.add([2]);
      expect(received, [
        [1],
      ]);

      subscription.resume();
      await Future<void>.delayed(Duration.zero);
      expect(source.resumes, 1);
      expect(received, [
        [1],
        [2],
      ]);

      final cancellation = subscription.cancel();
      var cancellationCompleted = false;
      unawaited(cancellation.then((_) => cancellationCompleted = true));
      await Future<void>.delayed(Duration.zero);
      expect(source.cancellations, 1);
      expect(cancellationCompleted, isFalse);

      cancelGate.complete();
      await cancellation;
      await request.close();
      expect(source.cancellations, 1);
    });

    test('should copy raw chunks before forwarding them', () async {
      final source = _TrackedByteSource();
      final request = Request(method: 'POST', uri: Uri.parse('/'), body: source.stream);
      final emitted = <int>[1, 2, 3];
      late List<int> received;
      final done = Completer<void>();
      request.body.listen(
        (chunk) {
          received = chunk;
        },
        onDone: done.complete,
      );

      source.add(emitted);
      emitted[0] = 9;
      source.close();
      await done.future;

      expect(received, [1, 2, 3]);
      await request.close();
    });

    test('should reject invalid byte values instead of truncating them', () async {
      final source = _TrackedByteSource();
      final request = Request(method: 'POST', uri: Uri.parse('/'), body: source.stream);
      final streamed = request.body.toList();
      final errorExpectation = expectLater(streamed, throwsArgumentError);

      source.add([-1, 256]);

      await errorExpectation;
      await request.close();
    });

    test('should close an untouched body without listening', () async {
      final source = _TrackedByteSource();
      final request = Request(method: 'POST', uri: Uri.parse('/'), body: source.stream);

      final firstClose = request.close();
      final secondClose = request.close();

      expect(identical(firstClose, secondClose), isTrue);
      await firstClose;
      expect(source.listens, 0);
      expect(source.cancellations, 0);
      await expectLater(request.bytes(), throwsStateError);
      expect(() => request.body.listen(null), throwsStateError);
    });

    test('should cancel an active buffered read when closed', () async {
      var cancellations = 0;
      final cancelGate = Completer<void>();
      final source = StreamController<List<int>>(
        onCancel: () {
          cancellations++;
          return cancelGate.future;
        },
      );
      final request = Request(method: 'POST', uri: Uri.parse('/'), body: source.stream);

      final reading = request.bytes();
      final readingExpectation = expectLater(reading, throwsStateError);
      await Future<void>.delayed(Duration.zero);
      final firstClose = request.close();
      final secondClose = request.close();

      expect(identical(firstClose, secondClose), isTrue);
      expect(cancellations, 1);
      await readingExpectation;
      var closeCompleted = false;
      unawaited(firstClose.then((_) => closeCompleted = true));
      await Future<void>.delayed(Duration.zero);
      expect(closeCompleted, isFalse);

      cancelGate.complete();
      await firstClose;
    });

    test('should cancel active raw delivery when closed', () async {
      final cancelGate = Completer<void>();
      final source = _TrackedByteSource(cancelGate: cancelGate);
      final request = Request(method: 'POST', uri: Uri.parse('/'), body: source.stream);
      final firstChunk = Completer<void>();
      request.body.listen((_) => firstChunk.complete());
      source.add([1]);
      await firstChunk.future;

      final firstClose = request.close();
      final secondClose = request.close();

      expect(identical(firstClose, secondClose), isTrue);
      expect(source.cancellations, 1);
      var closeCompleted = false;
      unawaited(firstClose.then((_) => closeCompleted = true));
      await Future<void>.delayed(Duration.zero);
      expect(closeCompleted, isFalse);

      cancelGate.complete();
      await firstClose;
    });
  });

  group('Response body', () {
    test('should share buffered content and close across header views', () async {
      final response = Response.stream(Stream.value(utf8.encode('value')));
      final view = response.withHeaders(
        Headers.from({
          'x-view': ['forwarded'],
        }),
      );

      expect(await view.text(), 'value');
      expect(await response.text(), 'value');
      expect(() => response.body.listen(null), throwsStateError);
      final firstClose = view.close();
      final secondClose = response.close();
      expect(identical(firstClose, secondClose), isTrue);
      await firstClose;
      await expectLater(response.bytes(), throwsStateError);
    });

    test('should classify response limits separately from request limits', () async {
      final response = Response.stream(Stream.value([1, 2]));

      await expectLater(
        response.bytes(maxBytes: 1),
        throwsA(
          isA<ResponseBodyLimitExceededException>().having(
            (error) => error.maxBytes,
            'maxBytes',
            1,
          ),
        ),
      );

      await response.close();
    });

    test('should default response buffering to one mebibyte', () async {
      final response = Response.stream(
        Stream.value(List<int>.filled(1024 * 1024 + 1, 0)),
      );

      await expectLater(
        response.bytes(),
        throwsA(
          isA<ResponseBodyLimitExceededException>().having(
            (error) => error.maxBytes,
            'maxBytes',
            1024 * 1024,
          ),
        ),
      );

      await response.close();
    });

    test('should keep response decoding failures as format errors', () async {
      final malformedText = Response.bytes([0xC3, 0x28]);
      final malformedJson = Response.text('{not-json}');

      await expectLater(malformedText.text(), throwsFormatException);
      await expectLater(malformedJson.json(), throwsFormatException);

      await malformedText.close();
      await malformedJson.close();
    });

    test('should stream lazily from a request after dispatch returns', () async {
      final source = _TrackedByteSource();
      final request = Request(method: 'POST', uri: Uri.parse('/echo'), body: source.stream);
      final application = Inlet()..post('/echo', (_, request) => Response.stream(request.body));

      final response = await application.handle(request);
      expect(source.listens, 0);
      final streamed = response.body.toList();
      source
        ..add([1])
        ..add([2])
        ..close();

      expect(await streamed, [
        [1],
        [2],
      ]);
      await response.close();
      await request.close();
    });

    test('should suppress bodyless statuses without subscribing', () async {
      for (final status in [204, 205, 304]) {
        final source = _TrackedByteSource();
        final response = Response.stream(source.stream, status: status);

        expect(await response.body.toList(), isEmpty, reason: 'status $status');
        expect(await response.bytes(), isEmpty, reason: 'status $status');
        expect(source.listens, 0, reason: 'status $status');
        await response.close();
        expect(source.listens, 0, reason: 'status $status');
      }
    });

    test('should release a lazy source when active consumption is closed', () async {
      var opened = 0;
      var released = 0;
      final continueProducing = Completer<void>();

      Stream<List<int>> lazyBody() async* {
        opened++;
        try {
          yield [1];
          await continueProducing.future;
          yield [2];
        } finally {
          released++;
        }
      }

      final response = Response.stream(lazyBody());
      expect(opened, 0);
      final firstChunk = Completer<void>();
      response.body.listen((_) {
        if (!firstChunk.isCompleted) {
          firstChunk.complete();
        }
      });
      await firstChunk.future;

      expect(opened, 1);
      await response.close();
      expect(released, 1);
    });

    test('should release a lazy source after normal completion', () async {
      var released = 0;

      Stream<List<int>> lazyBody() async* {
        try {
          yield [1];
        } finally {
          released++;
        }
      }

      final response = Response.stream(lazyBody());

      expect(await response.body.toList(), [
        [1],
      ]);
      expect(released, 1);
      await response.close();
    });

    test('should release a lazy source and preserve its failure', () async {
      final failure = StateError('source failed');
      var released = 0;

      Stream<List<int>> lazyBody() async* {
        try {
          yield [1];
          throw failure;
        } finally {
          released++;
        }
      }

      final response = Response.stream(lazyBody());

      await expectLater(response.body.toList(), throwsA(same(failure)));
      expect(released, 1);
      await response.close();
    });
  });
}

final class _TrackedByteSource {
  _TrackedByteSource({this.cancelGate}) {
    controller = StreamController<List<int>>(sync: true)
      ..onListen = () {
        listens++;
      }
      ..onPause = () {
        pauses++;
      }
      ..onResume = () {
        resumes++;
      }
      ..onCancel = () {
        cancellations++;
        return cancelGate?.future;
      };
  }

  final Completer<void>? cancelGate;
  late final StreamController<List<int>> controller;

  int listens = 0;
  int pauses = 0;
  int resumes = 0;
  int cancellations = 0;

  Stream<List<int>> get stream => controller.stream;

  void add(List<int> chunk) => controller.add(chunk);

  void addError(Object error, [StackTrace? stackTrace]) => controller.addError(error, stackTrace);

  void close() {
    controller.close().ignore();
  }
}
