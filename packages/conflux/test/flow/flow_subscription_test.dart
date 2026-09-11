import 'dart:async';

import 'package:conflux/effect.dart';
import 'package:conflux/flow.dart';
import 'package:test/test.dart';

void main() {
  group('Flow subscriptions and Stream interop', () {
    test('should expose consumer completion after scoped cleanup', () async {
      final values = <int>[];
      final events = <String>[];
      final subscription = Flow.fromIterable([1, 2])
          .ensuring(Effect.sync(() => events.add('cleanup')))
          .subscribe((value) => Effect.sync(() => values.add(value)));

      final exit = await subscription.completion;

      expect(exit, isA<Succeeded<void, Never>>());
      expect(values, [1, 2]);
      expect(events, ['cleanup']);
    });

    test('should make repeated cancellation await cleanup once', () async {
      final started = Completer<void>();
      final pending = Completer<int>();
      var cleaned = 0;
      final flow =
          Effect.tryFuture<int, String>(
            () {
              started.complete();
              return pending.future;
            },
            onError: (error, stackTrace) => '$error',
          ).asFlow().ensuring(
            Effect.sleep(const Duration(milliseconds: 20)).tap(
              (_) => Effect.sync(() => cleaned += 1),
            ),
          );
      final subscription = flow.subscribe((_) => Effect.succeed(null));
      await started.future;

      var completed = false;
      final first = subscription.cancel('stop').then((exit) {
        completed = true;
        return exit;
      });
      final second = subscription.cancel('stop again');
      await Future<void>.delayed(Duration.zero);
      expect(completed, isFalse);

      expect(await first, isA<Failed<void, String>>());
      expect(await second, isA<Failed<void, String>>());
      expect(cleaned, 1);
      expect(await subscription.completion, isA<Failed<void, String>>());
    });

    test('should emit values and preserve a terminal Cause in Stream errors', () async {
      final values = await Flow.fromIterable<int?>([1, null]).toStream().toList();
      expect(values, [1, null]);

      final error = await Flow.fail<int, String>('failed')
          .toStream()
          .first
          .then<Object?>((_) => null, onError: (Object error) => error);
      expect(error, isA<FlowException<String>>());
      expect((error! as FlowException<String>).cause.expectedErrors, ['failed']);
    });

    test('should stop pulling while the Stream listener is paused', () async {
      var pulled = 0;
      late StreamSubscription<int> subscription;
      final first = Completer<void>();
      final done = Completer<void>();
      final stream = Flow.fromIterable([1, 2, 3])
          .tap((_) => Effect.sync(() => pulled += 1))
          .toStream();

      subscription = stream.listen(
        (_) {
          if (!first.isCompleted) {
            subscription.pause();
            first.complete();
          }
        },
        onDone: done.complete,
      );
      addTearDown(subscription.cancel);
      await first.future;
      await Future<void>.delayed(Duration.zero);
      expect(pulled, lessThanOrEqualTo(2));

      subscription.resume();
      await done.future;
      expect(pulled, 3);
    });

    test('should honor a new pause before a pending delivery resumes', () async {
      final values = <int>[];
      final first = Completer<void>();
      final done = Completer<void>();
      late StreamSubscription<int> subscription;
      subscription = Flow.fromIterable([1, 2, 3]).toStream().listen(
        (value) {
          values.add(value);
          if (value == 1) {
            subscription.pause();
            first.complete();
          }
        },
        onDone: done.complete,
      );
      addTearDown(subscription.cancel);
      await first.future;

      subscription
        ..resume()
        ..pause();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(values, [1]);
      subscription.resume();
      await done.future;
      expect(values, [1, 2, 3]);
    });

    test('should await Flow cleanup when a Stream subscription is cancelled', () async {
      final started = Completer<void>();
      final pending = Completer<int>();
      var cleaned = false;
      final stream =
          Effect.tryFuture<int, String>(
                () {
                  started.complete();
                  return pending.future;
                },
                onError: (error, stackTrace) => '$error',
              )
              .asFlow()
              .ensuring(
                Effect.sleep(const Duration(milliseconds: 20)).tap(
                  (_) => Effect.sync(() => cleaned = true),
                ),
              )
              .toStream();
      final subscription = stream.listen((_) {});
      await started.future;

      final cancelled = subscription.cancel();
      await Future<void>.delayed(Duration.zero);
      expect(cleaned, isFalse);
      await cancelled;
      expect(cleaned, isTrue);
    });
  });
}
