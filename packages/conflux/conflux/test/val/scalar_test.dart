// Explicit numeric literals exercise VM numeric boundaries.
// ignore_for_file: prefer_int_literals

import 'package:conflux/val.dart';
import 'package:test/test.dart';

import 'schema_test.dart' show issues;

enum _Color { red, blue }

void main() {
  group('Val scalar schemas', () {
    test('should accept VM integers without coercing doubles', () {
      expect(Val.int().parse(3), 3);
      expect(issues(Val.int(), 3.0).single.code, 'INVALID_TYPE');
      expect(issues(Val.int(), '3').single.code, 'INVALID_TYPE');
      expect(Val.double().parse(3.0), 3.0);
      expect(issues(Val.double(), 3).single.code, 'INVALID_TYPE');
      expect(Val.number().parse(3), isA<int>());
      expect(Val.number().parse(3.5), isA<double>());
      expect(Val.boolean().parse(false), false);
      expect(issues(Val.boolean(), 0).single.code, 'INVALID_TYPE');
    });
    test('should skip all numeric checks after one non-finite issue', () {
      var calls = 0;
      final schema = Val.number(name: 'Amount', code: 'BAD').min(1).refine((_) {
        calls++;
        return false;
      });
      for (final value in [double.nan, double.infinity, double.negativeInfinity]) {
        final error = issues(schema, value).single;
        expect(
          (error.code, error.message),
          ('BAD', 'Amount must be a finite number'),
        );
        expect(issues(Val.double(), value).single.code, 'NOT_FINITE');
      }
      expect(calls, 0);
    });
    test('should enforce inclusive and exclusive numeric bounds and aliases', () {
      expect(Val.int().min(2).max(2).parse(2), 2);
      expect(issues(Val.int().greaterThan(2).lessThan(2), 2).single.code, 'GREATER_THAN');
      expect(Val.double().min(2.0).max(2.0).parse(2.0), 2.0);
      expect(Val.number().greaterThan(1).lessThan(3.5).parse(2.5), 2.5);
      expect(Val.int().positive().parse(1), 1);
      expect(Val.double().negative().parse(-1.0), -1.0);
      expect(issues(Val.int().positive(), 0).single.message, 'Must be greater than 0');
      expect(
        issues(Val.double().positive(), 0.0).single.message,
        issues(Val.double().greaterThan(0), 0.0).single.message,
      );
      expect(issues(Val.number().negative(), 0).single.code, 'LESS_THAN');
      expect(issues(Val.int().min(10).max(5), 7).single.code, 'MIN');
    });
    test('should check exact divisibility and safe-integer endpoints', () {
      expect(Val.int().multipleOf(3).parse(-6), -6);
      expect(Val.int().multipleOf(3).parse(0), 0);
      expect(issues(Val.int().multipleOf(3), 2).single.code, 'MULTIPLE_OF');
      for (final value in [-9007199254740991, 9007199254740991]) {
        expect(Val.int().safe().parse(value), value);
      }
      for (final value in [-9007199254740992, 9007199254740992]) {
        expect(issues(Val.int().safe(), value).single.code, 'SAFE_INTEGER');
      }
      for (final divisor in [0, -1]) {
        expect(() => Val.int().multipleOf(divisor), throwsArgumentError);
      }
    });
    test('should retain literal types despite cross-type numeric equality', () {
      expect(Val.literal(1).parse(1), isA<int>());
      expect(issues(Val.literal<int>(1), 1.0).single.code, 'INVALID_LITERAL');
      expect(Val.literal<num>(1).parse(1.0), isA<double>());
      expect(Val.literal(true).parse(true), true);
      expect(issues(Val.literal('a'), 1).single.code, 'INVALID_LITERAL');
      expect(issues(Val.literal('a'), null).single.code, 'NOT_NULL');
    });
    test('should copy enum membership and retain borrowed instances', () {
      final values = ['a', 'b'];
      final schema = Val.enumString(values);
      values.clear();
      expect(schema.parse('a'), 'a');
      expect(issues(schema, 'A').single.code, 'INVALID_ENUM');
      expect(Val.enumValues([_Color.red]).parse(_Color.red), _Color.red);
      expect(issues(Val.enumValues([_Color.red]), 'red').single.code, 'INVALID_ENUM');
      expect(issues(Val.enumValues([_Color.red]), _Color.blue).single.code, 'INVALID_ENUM');
      final borrowed = Object();
      expect(Val.instance<Object>().parse(borrowed), same(borrowed));
      expect(issues(Val.instance<_Color>(), 1).single.message, 'Must be an instance of _Color');
    });
  });
  group('StringFormats', () {
    final profiles = <(String, Schema<String>, List<String>, List<String>)>[
      (
        'email',
        Val.string().email(),
        ['a+b@example.com', 'a_b@example.co'],
        ['.a@example.com', 'a..b@example.com', 'a@example.com\n', 'a@b.c', ' a@b.co'],
      ),
      (
        'URI',
        Val.string().url(),
        ['https://example.com', 'ftp://example.com/file'],
        ['/relative', 'mailto:a@b.com', 'https://'],
      ),
      (
        'UUID',
        Val.string().uuid(),
        [
          '550e8400-e29b-41d4-a716-446655440000',
          '550E8400-E29B-81D4-A716-446655440000',
          '00000000-0000-0000-0000-000000000000',
          'FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF',
        ],
        [
          '550e8400-e29b-91d4-a716-446655440000',
          '550e8400-e29b-41d4-7716-446655440000',
          '550e8400-e29b-41d4-a716-446655440000\n',
        ],
      ),
      (
        'IPv4',
        Val.string().ipv4(),
        ['0.0.0.0', '255.255.255.255', '127.0.0.1'],
        ['01.2.3.4', '256.1.1.1', '+1.2.3.4', '1.2.3.4\n', '1.2.3'],
      ),
      (
        'IPv6',
        Val.string().ipv6(),
        ['::1', '2001:db8::1', '::ffff:192.0.2.1'],
        ['', '[::1]', 'fe80::1%eth0', ' ::1', '::1\n', 'garbage'],
      ),
    ];
    for (final (label, schema, valid, invalid) in profiles) {
      test('should enforce the $label format boundaries without normalization', () {
        for (final input in valid) {
          expect(schema.parse(input), input, reason: input);
        }
        for (final input in invalid) {
          expect(issues(schema, input).single.code, startsWith('INVALID_'), reason: input);
        }
      });
    }
    test('should use native regex and literal substring semantics', () {
      expect(Val.string().matches(RegExp('abc', caseSensitive: false)).parse('xABCy'), 'xABCy');
      expect(Val.string().startsWith('').endsWith('').contains('').parse('x'), 'x');
      expect(Val.string().startsWith('a').endsWith('c').contains('.').parse('a.c'), 'a.c');
      expect(issues(Val.string().contains('.'), 'abc').single.code, 'CONTAINS');
      expect(Val.string().ip().parse('::1'), '::1');
      expect(Val.string().ip().parse('127.0.0.1'), '127.0.0.1');
      expect(issues(Val.string().ip(), 'x').single.code, 'INVALID_IP');
      expect(() => Val.string().ip(version: 5), throwsArgumentError);
    });
    test('should report the signup example errors in order without running refinement', () {
      final signup =
          Val.object({
            'email': Val.string(code: 'EMAIL_INVALID_TYPE', message: 'Email must be text')
                .email(code: 'EMAIL_INVALID', message: 'Enter a valid email address')
                .required(code: 'EMAIL_REQUIRED', message: 'Email is required'),
            'password': Val.string().minLength(
              8,
              code: 'PASSWORD_TOO_SHORT',
              message: 'Use at least 8 characters',
            ),
            'confirmPassword': Val.string(),
          }).refine(
            (data) => data['password'] == data['confirmPassword'],
            code: 'PASSWORD_MISMATCH',
            message: 'Passwords do not match',
            path: [const FieldSegment('confirmPassword')],
          );
      expect(
        issues(signup, {
          'email': 'invalid',
          'password': 'short',
          'confirmPassword': 'short',
        }).map((e) => e.code),
        ['EMAIL_INVALID', 'PASSWORD_TOO_SHORT'],
      );
    });
  });
}
