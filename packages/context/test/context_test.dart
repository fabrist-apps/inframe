import 'package:context/context.dart';
import 'package:test/test.dart';

import 'support/analytics.dart';
import 'support/http.dart';

void main() {
  group('Context', () {
    test('should retrieve the same typed object after binding', () {
      final key = ContextKey<List<String>>('events');
      final events = <String>[];
      final context = Context().withBinding(key.bind(events));

      final read = context.read(key);
      final required = context.require(key);
      expect(read, same(events));
      expect(required, same(events));
    });

    test('should compose independent extensions in either setup order', () {
      final events = <String>[];
      final responses = <String>[];
      final context = Context().withAnalytics(events).withHttp(responses);
      final reversed = Context().withHttp(responses).withAnalytics(events);

      context.analytics.add('page_view');
      context.http.add('Hello');

      expect(events, ['page_view']);
      expect(responses, ['Hello']);
      expect(reversed.analytics, same(events));
      expect(reversed.http, same(responses));
    });

    test('should report missing setup through an extension', () {
      expect(
        () => Context().analytics,
        throwsA(
          isA<MissingContextValue>().having(
            (error) => error.debugName,
            'debugName',
            'analytics',
          ),
        ),
      );
    });
    test('should return null for an absent key', () {
      expect(Context().read(ContextKey<String>('missing')), isNull);
    });

    test('should identify the missing required key', () {
      expect(
        () => Context().require(ContextKey<String>('request')),
        throwsA(
          isA<MissingContextValue>()
              .having((error) => error.debugName, 'debugName', 'request')
              .having((error) => error.toString(), 'message', contains('request')),
        ),
      );
    });

    test('should keep distinct keys with identical names independent', () {
      final first = ContextKey<String>('name');
      final second = ContextKey<String>('name');
      final context = Context().withBinding(first.bind('first')).withBinding(second.bind('second'));

      expect(context.require(first), 'first');
      expect(context.require(second), 'second');
      expect(context.read(ContextKey<String>('name')), isNull);
    });

    test('should preserve unrelated heterogeneous bindings when deriving', () {
      final eventsKey = ContextKey<List<String>>('events');
      final countKey = ContextKey<int>('count');
      final events = <String>[];
      final parent = Context().withBinding(eventsKey.bind(events));
      final child = parent.withBinding(countKey.bind(0));

      expect(child.require(eventsKey), same(events));
      expect(child.require(countKey), 0);
      expect(parent.read(countKey), isNull);
      expect(child, isNot(same(parent)));
    });

    test('should isolate replacement from parents and siblings', () {
      final key = ContextKey<String>('request');
      final parent = Context().withBinding(key.bind('parent'));
      final left = parent.withBinding(key.bind('left'));
      final right = parent.withBinding(key.bind('right'));
      final descendant = left.withBinding(key.bind('descendant'));

      expect(parent.require(key), 'parent');
      expect(left.require(key), 'left');
      expect(right.require(key), 'right');
      expect(descendant.require(key), 'descendant');
    });

    test('should borrow mutable values across derived contexts', () {
      final key = ContextKey<List<String>>('events');
      final events = <String>[];
      final parent = Context().withBinding(key.bind(events));
      final child = parent.withBinding(ContextKey<int>('request').bind(1));

      child.require(key).add('page_view');

      expect(parent.require(key), same(events));
      expect(child.require(key), same(events));
      expect(events, ['page_view']);
    });

    test('should reject incompatible binding through a widened key', () {
      final key = ContextKey<int>('count');
      final ContextKey<Object> widened = key;
      final context = Context().withBinding(key.bind(42));

      expect(() => widened.bind('wrong type'), throwsA(isA<TypeError>()));
      expect(context.require(key), 42);
      expect(context.require(widened), 42);
      expect(context.withBinding(widened.bind(7)).require(key), 7);
    });
  });
}
