import 'package:conflux/val.dart';
import 'package:test/test.dart';

import 'schema_test.dart' show issues;

void main() {
  group('Val lazy schemas', () {
    test('should defer resolution until first parse and reuse successful resolution', () {
      var builds = 0;
      final schema = Val.lazy(() {
        builds++;
        return Val.string();
      });
      expect(builds, 0);
      expect(schema.parse('x'), 'x');
      expect(schema.parse('y'), 'y');
      expect(builds, 1);
      issues(schema, 1);
      expect(builds, 1);
    });
    test('should reset resolution after builder throws and reject re-entry', () {
      var builds = 0;
      final defect = StateError('builder');
      final schema = Val.lazy(() {
        if (builds++ == 0) throw defect;
        return Val.string();
      });
      expect(() => schema.parse('x'), throwsA(same(defect)));
      expect(schema.parse('x'), 'x');
      expect(builds, 2);
      late Schema<String> reentrant;
      reentrant = Val.lazy(() {
        reentrant.parse('x');
        return Val.string();
      });
      expect(() => reentrant.parse('x'), throwsStateError);
      expect(() => reentrant.parse('x'), throwsStateError);
    });
    test('should count active lazy entries and restore sibling and repeated-parse depth', () {
      late Schema<Map<String, Object?>> node;
      node = Val.lazy(
        () => Val.object({'label': Val.string(), 'children': Val.list(node).optional()}),
        maxDepth: 2,
        name: ' Node ',
      );
      final leaf = {'label': 'leaf'};
      expect(
        node.parse({
          'label': 'root',
          'children': [leaf, leaf],
        }),
        {
          'label': 'root',
          'children': [leaf, leaf],
        },
      );
      final error = issues(node, {
        'label': 'root',
        'children': [
          {
            'label': 'child',
            'children': [leaf],
          },
        ],
      }).single;
      expect(error.code, 'MAX_DEPTH');
      expect(error.message, 'Node must not exceed the maximum nesting depth');
      expect(error.path, [const Field('children'), Index(0), const Field('children'), Index(0)]);
      expect(node.parse(leaf), leaf);
      final cycle = <String, Object?>{'label': 'cycle'};
      cycle['children'] = [cycle];
      expect(issues(node, cycle).single.code, 'MAX_DEPTH');
      expect(node.parse(leaf), leaf);
    });
    test('should restore traversal depth after callback exceptions', () {
      final defect = StateError('predicate');
      var throws = true;
      final schema = Val.lazy(
        () => Val.string().refine((_) {
          if (throws) throw defect;
          return true;
        }),
        maxDepth: 1,
      );
      expect(() => schema.parse('x'), throwsA(same(defect)));
      throws = false;
      expect(schema.parse('x'), 'x');
    });
    test('should retain delegated errors and outer presence while labeling only depth', () {
      final schema = Val.lazy(
        () => Val.string(name: 'Child').optional(),
        name: 'Parent',
        code: 'DEPTH',
      );
      expect(issues(schema, 1).single.message, 'Child must be a string');
      expect(issues(schema, 1).single.code, 'INVALID_TYPE');
      expect(issues(Val.object({'x': schema}), {}).single.code, 'REQUIRED');
      expect(Val.object({'x': schema.optional()}).parse({}), isEmpty);
      expect(Val.lazy(() => Val.string().nullable()).parse(null), isNull);
      expect(schema.nullable().parse(null), isNull);
      late Schema<Object?> recursive;
      recursive = Val.lazy(() => recursive, maxDepth: 1, code: '', message: 'Limit');
      final error = issues(recursive, 'x').single;
      expect((error.code, error.kind, error.message), ('', IssueKind.maxDepth, 'Limit'));
      expect(() => Val.lazy(Val.string, maxDepth: 0), throwsArgumentError);
    });
  });
  group('Val JSON values', () {
    test('should accept finite JSON scalars and nested null without accepting root null', () {
      final schema = Val.any();
      for (final value in <Object>['x', true, 1, 1.5]) {
        expect(schema.parse(value), value);
      }
      expect(
        schema.parse({
          'a': [null, 'x'],
        }),
        {
          'a': [null, 'x'],
        },
      );
      expect(issues(schema, null).single.code, 'NOT_NULL');
      expect(schema.nullable().parse(null), isNull);
      for (final value in [Object(), double.nan, double.infinity]) {
        expect(issues(schema, value).single.message, 'Must be a JSON value');
      }
    });
    test('should report all invalid nested values at their structural paths', () {
      final errors = issues(Val.any(), {
        'a': [Object(), double.nan],
        'b': {1: 'not string'},
      });
      expect(errors.map((e) => e.path), [
        [const Field('a'), Index(0)],
        [const Field('a'), Index(1)],
        [const Field('b')],
      ]);
      expect(errors.map((e) => e.code), everyElement('INVALID_TYPE'));
    });
    test('should count only containers and distinguish cycles from shared siblings', () {
      final schema = Val.any(maxDepth: 2, name: 'Payload');
      expect(
        schema.parse([
          [1],
        ]),
        [
          [1],
        ],
      );
      expect(
        issues(schema, [
          [
            [1],
          ],
        ]).single.path,
        [Index(0), Index(0)],
      );
      final shared = [1];
      expect(schema.parse([shared, shared]), [
        [1],
        [1],
      ]);
      final cycle = <Object?>[];
      cycle.add(cycle);
      expect(issues(schema, cycle).single.path, [Index(0)]);
      final mapCycle = <String, Object?>{};
      mapCycle['self'] = mapCycle;
      expect(issues(schema, mapCycle).single.code, 'MAX_DEPTH');
      expect(
        issues(schema, [
          [
            [1],
          ],
        ]).single.message,
        'Payload must not exceed the maximum nesting depth',
      );
      expect(schema.parse([1]), [1]);
      expect(Val.any(maxDepth: 1).parse(1), 1);
      expect(Val.any(maxDepth: 1).parse([1]), [1]);
      expect(() => Val.any(maxDepth: -1), throwsArgumentError);
    });
    test('should deeply detach outputs and preserve intrinsic overrides', () {
      final input = <String, Object?>{
        'values': <Object?>[1, null],
      };
      final output = Val.any().parse(input) as Map<String, Object?>;
      (input['values']! as List<Object?>).add(2);
      expect(output, {
        'values': [1, null],
      });
      expect(output.clear, throwsUnsupportedError);
      expect(() => (output['values']! as List<Object?>).clear(), throwsUnsupportedError);
      expect(issues(Val.any(code: 'JSON', message: ''), Object()).single.code, 'JSON');
      expect(issues(Val.any(code: 'JSON', message: ''), Object()).single.message, '');
      expect(
        issues(Val.any(maxDepth: 1, code: 'JSON'), [
          [1],
        ]).single.code,
        'JSON',
      );
    });
  });
}
