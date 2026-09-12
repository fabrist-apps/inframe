import 'package:artificer_core/artificer_core.dart';
import 'package:test/test.dart';

void main() {
  group('Setting', () {
    test('should represent inheritance, replacement, and clearing', () {
      const inherited = Setting<String>.inherit();
      const replaced = Setting<String>.set('new');
      const cleared = Setting<String>.clear();

      expect(inherited.resolve('default'), 'default');
      expect(replaced.resolve('default'), 'new');
      expect(cleared.resolve('default'), isNull);
    });

    test('should let immutable provider options replace collections without mutation', () {
      final input = ['new'];
      final options = _FixtureOptions(stopSequences: Setting.set(List.unmodifiable(input)));
      input.add('later');

      final merged = options.merge(const _FixtureOptions.defaults());

      expect(merged.stopSequences.resolve(null), ['new']);
      expect(
        () => merged.stopSequences.resolve(null)?.add('changed'),
        throwsUnsupportedError,
      );
      expect(
        const _FixtureOptions(stopSequences: Setting.clear())
            .merge(const _FixtureOptions.defaults())
            .stopSequences
            .resolve(null),
        isNull,
      );
    });
  });
}

final class _FixtureOptions {
  const _FixtureOptions({this.stopSequences = const Setting.inherit()});

  const _FixtureOptions.defaults() : stopSequences = const Setting.set(['default']);

  final Setting<List<String>> stopSequences;

  _FixtureOptions merge(_FixtureOptions defaults) {
    final resolved = stopSequences.resolve(defaults.stopSequences.resolve(null));
    return _FixtureOptions(
      stopSequences: resolved == null
          ? const Setting.clear()
          : Setting.set(List.unmodifiable(resolved)),
    );
  }
}
