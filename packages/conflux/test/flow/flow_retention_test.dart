@TestOn('vm')
library;

import 'dart:mirrors';

import 'package:conflux/effect.dart';
import 'package:conflux/flow.dart';
import 'package:test/test.dart';

void main() {
  group('Flow', () {
    test('should release completed concatMap cursor registrations', () async {
      final registrations = await Effect.build<({int initial, int after}), Never>((resolve) async {
        final cursor = await resolve(
          Flow.fromIterable(List.generate(101, (index) => index))
              .concatMap((value, _) => Flow.succeed<int, Never>(value))
              .open(),
        );
        await resolve(cursor.next());
        final initialRegistrations = _retainedFinalizers(cursor);
        for (var index = 1; index < 100; index += 1) {
          await resolve(cursor.next());
        }

        return (initial: initialRegistrations, after: _retainedFinalizers(cursor));
      }).runFuture();
      expect(registrations.after, lessThanOrEqualTo(registrations.initial));
    });
  });
}

// Inspect ownership directly: forced GC and weak references cannot establish a
// deterministic bound on the closures retained by a live consumption scope.
int _retainedFinalizers(FlowCursor<Object?, Never> cursor) {
  final execution = _field(cursor, '_execution');
  final scope = _field(execution, 'scope');
  return (_field(scope, '_finalizers') as Iterable<Object?>).length;
}

Object _field(Object owner, String name) {
  final mirror = reflect(owner);
  final symbol = mirror.type.declarations.keys.firstWhere(
    (symbol) => MirrorSystem.getName(symbol) == name,
  );
  return mirror.getField(symbol).reflectee as Object;
}
