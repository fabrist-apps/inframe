// The expected canonical form is split at readable Unicode key boundaries.
// ignore_for_file: missing_whitespace_between_adjacent_strings, use_raw_strings

import 'package:test/test.dart';
import 'package:voxel_generator/voxel_generator.dart';

void main() {
  group('canonicalJson', () {
    test('should match RFC 8785 number serialization vectors', () {
      expect(
        canonicalJson([
          333333333.33333329,
          1E30,
          4.50,
          2e-3,
          0.000000000000000000000000001,
        ]),
        '[333333333.3333333,1e+30,4.5,0.002,1e-27]',
      );
    });

    test('should sort object keys by UTF-16 code units', () {
      expect(
        canonicalJson({
          '\u20ac': 'Euro Sign',
          '\r': 'Carriage Return',
          '\ufb33': 'Hebrew Letter Dalet With Dagesh',
          '1': 'One',
          '😀': 'Emoji: Grinning Face',
          '\u0080': 'Control',
          'ö': 'Latin Small Letter O With Diaeresis',
        }),
        '{"\\r":"Carriage Return","1":"One","":"Control",'
        '"ö":"Latin Small Letter O With Diaeresis","€":"Euro Sign",'
        '"😀":"Emoji: Grinning Face","דּ":"Hebrew Letter Dalet With Dagesh"}',
      );
    });
  });
}
