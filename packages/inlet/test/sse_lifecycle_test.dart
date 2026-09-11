import 'dart:async';

import 'package:inlet/inlet.dart';
import 'package:test/test.dart';

void main() {
  group('Response.sse lifecycle', () {
    test('should propagate in-process pause, resume, and cancellation', () async {
      final paused = Completer<void>();
      final resumed = Completer<void>();
      final cancelled = Completer<void>();
      final events = StreamController<SseEvent>(
        onPause: paused.complete,
        onResume: resumed.complete,
        onCancel: cancelled.complete,
      );
      final response = Response.sse(events.stream);
      final received = <List<int>>[];
      final firstReceived = Completer<void>();
      late StreamSubscription<List<int>> subscription;
      subscription = response.body.listen((event) {
        received.add(event);
        if (!firstReceived.isCompleted) {
          subscription.pause();
          firstReceived.complete();
        }
      });

      events.add(SseEvent(data: 'first'));
      await firstReceived.future;
      await paused.future;
      events.add(SseEvent(data: 'second'));
      await Future<void>.delayed(Duration.zero);
      expect(received, hasLength(1));

      subscription.resume();
      await resumed.future;
      await Future<void>.delayed(Duration.zero);
      expect(received, hasLength(2));

      await subscription.cancel();
      await cancelled.future;
      await response.close();
    });

    test('should close active delivery through every header view', () async {
      final listened = Completer<void>();
      final cancelled = Completer<void>();
      final events = StreamController<SseEvent>(
        onListen: listened.complete,
        onCancel: cancelled.complete,
      );
      final response = Response.sse(events.stream);
      final view = response.withHeaders(
        const Headers.empty().set('x-view', 'yes'),
      );
      response.body.listen(null);
      await listened.future;

      final firstClose = view.close();
      expect(response.close(), same(firstClose));
      await firstClose;

      await cancelled.future;
    });

    test('should release source resources after normal completion', () async {
      final released = Completer<void>();

      Stream<SseEvent> events() async* {
        try {
          yield SseEvent(data: 'value');
        } finally {
          released.complete();
        }
      }

      final response = Response.sse(events());
      addTearDown(response.close);

      expect(await response.body.length, 1);
      await released.future;
    });

    test('should preserve source failures and cancel remaining work', () async {
      final failure = StateError('source failed');
      final cancelled = Completer<void>();
      late StreamController<SseEvent> events;
      events = StreamController<SseEvent>(
        onListen: () => events.addError(failure),
        onCancel: cancelled.complete,
      );
      final response = Response.sse(events.stream);
      addTearDown(response.close);

      await expectLater(response.body.drain<void>(), throwsA(same(failure)));
      await cancelled.future;
    });
  });
}
