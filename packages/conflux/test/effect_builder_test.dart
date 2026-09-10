import 'package:conflux/conflux.dart';
import 'package:context/context.dart';
import 'package:test/test.dart';

void main() {
  group('Effect builder', () {
    test('should stay lazy and use fresh state on every run', () async {
      var runs = 0;
      final effect = Effect.defer(() {
        runs += 1;
        return Effect.succeed<int, String>(runs);
      });
      final runtime = Runtime();

      expect(runs, 0);
      expect(await runtime.run(effect), isA<Succeeded<int, String>>());
      expect(await runtime.run(effect), isA<Succeeded<int, String>>());
      expect(runs, 2);
    });

    test('should bind asynchronous Effects and synchronous Results', () async {
      final effect = Effect.build<String?, String>(($) async {
        final number = await $(Effect.succeed<int, String>(42));
        final nullable = $.sync<String?>(const Success(null));
        return number == 42 ? nullable : 'wrong';
      });

      final exit = await Runtime().run(effect);

      expect(exit, isA<Succeeded<String?, String>>());
      expect((exit as Succeeded<String?, String>).value, isNull);
    });

    test('should preserve a bound failure caught by builder code', () async {
      var laterWorkStarted = false;
      final effect = Effect.build<int, String>(($) async {
        try {
          $.sync<int>(const Failure('invalid'));
        } on Object {
          try {
            await $(
              Effect.defer(() {
                laterWorkStarted = true;
                return Effect.succeed<int, String>(1);
              }),
            );
          } on Object {
            return 2;
          }
        }
        return 3;
      });

      final exit = await Runtime().run(effect);

      expect(laterWorkStarted, isFalse);
      expect(exit, isA<Failed<int, String>>());
      expect((exit as Failed<int, String>).cause, isA<Expected<String>>());
    });

    test('should capture synchronous throws and builder throws as defects', () async {
      final syncExit = await Runtime().run(
        Effect.sync<int>(() => throw StateError('sync')),
      );
      final buildExit = await Runtime().run(
        Effect.build<int, Never>((_) => throw StateError('build')),
      );

      expect((syncExit as Failed<int, Never>).cause, isA<Defect<Never>>());
      expect((buildExit as Failed<int, Never>).cause, isA<Defect<Never>>());
    });

    test('should reject builder use after the callback ends', () async {
      late EffectBuilder<Never> escaped;
      final runtime = Runtime();
      await runtime.run(
        Effect.build<void, Never>(($) {
          escaped = $;
        }),
      );

      expect(() => escaped.context, throwsStateError);
      await expectLater(
        escaped(Effect.succeed<int, Never>(1)),
        throwsStateError,
      );
    });
  });

  group('Effect context', () {
    test('should replace context only for descendants', () async {
      final key = ContextKey<String>('name');
      final parent = Context().withBinding(key.bind('parent'));
      final child = parent.withBinding(key.bind('child'));
      final read = Effect.context<String>((context) => context.require(key));
      final runtime = Runtime(context: parent);

      final childExit = await runtime.run(read.withContext(child));
      final parentExit = await runtime.run(read);

      expect((childExit as Succeeded<String, Never>).value, 'child');
      expect((parentExit as Succeeded<String, Never>).value, 'parent');
    });

    test('should turn missing bindings into defects', () async {
      final key = ContextKey<String>('required');
      final exit = await Runtime().run(
        Effect.context<String>((context) => context.require(key)),
      );

      expect((exit as Failed<String, Never>).cause, isA<Defect<Never>>());
    });
  });
}
