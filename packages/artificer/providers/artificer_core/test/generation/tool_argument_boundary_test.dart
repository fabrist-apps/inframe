import 'package:artificer_core/artificer_core.dart';
import 'package:test/test.dart';

void main() {
  group('ToolArguments', () {
    test('should retain nonfinite generated argument text as malformed data', () {
      const original = '{"number":1e999}';
      final arguments = ToolArguments.parse(original);
      expect(arguments, isA<MalformedToolArguments>());
      expect((arguments as MalformedToolArguments).original, original);
    });
  });
}
