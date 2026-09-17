import 'package:inlet/inlet.dart';
import 'package:test/test.dart';

void main() {
  group('Headers', () {
    test('should preserve immutable case-insensitive multi-values', () {
      final originalValues = <String>['a=1'];
      final headers = Headers.from({
        'Set-Cookie': originalValues,
        'set-cookie': ['b=2'],
        'X-Trace': ['first', 'second'],
      });
      originalValues.add('changed=1');

      expect(headers['SET-cookie'], 'a=1');
      expect(headers.all('set-cookie'), ['a=1', 'b=2']);
      expect(headers.all('x-trace'), ['first', 'second']);
      expect(() => headers.all('x-trace').add('third'), throwsUnsupportedError);
      expect(() => headers.toMap()['new'] = ['value'], throwsUnsupportedError);
    });

    test('should return new values for set append and remove', () {
      const empty = Headers.empty();
      final first = empty.set('X-Trace', 'one');
      final second = first.append('x-trace', 'two');
      final removed = second.remove('X-TRACE');

      expect(empty.contains('x-trace'), isFalse);
      expect(first.all('x-trace'), ['one']);
      expect(second.all('x-trace'), ['one', 'two']);
      expect(removed.contains('x-trace'), isFalse);
    });

    test('should reject invalid names and values', () {
      expect(
        () => Headers.from({
          'bad name': ['value'],
        }),
        throwsArgumentError,
      );
      expect(
        () => Headers.from({
          'x-test': ['line\nbreak'],
        }),
        throwsArgumentError,
      );
      expect(
        () => Headers.from({
          'x-test': ['value\u007f'],
        }),
        throwsArgumentError,
      );
      expect(
        () => Headers.from({
          'x-test': ['café'],
        }),
        throwsArgumentError,
      );
    });
  });
}
