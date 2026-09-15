import 'package:conflux/moment.dart';
import 'package:conflux/result.dart';
import 'package:conflux/val.dart';
import 'package:test/test.dart';

import 'schema_test.dart' show issues;

enum _Choice { first, second }

Moment _moment(String text) => Moment.parse(text).getOrThrowWith((e) => StateError(e.message));

void main() {
  group('Val default issue catalog', () {
    final bound = _moment('2026-01-01T00:00:00Z');
    final cases =
        <
          (
            Schema<Object?> Function(String? name, String? code, String? message),
            Object?,
            String,
            IssueKind,
            String,
            String,
          )
        >[
          (
            (name, code, message) => Val.string(name: name, code: code, message: message),
            Object(),
            'INVALID_TYPE',
            IssueKind.invalidType,
            'Must be a string',
            'Label must be a string',
          ),
          (
            (name, code, message) => Val.int(name: name, code: code, message: message),
            Object(),
            'INVALID_TYPE',
            IssueKind.invalidType,
            'Must be an integer',
            'Label must be an integer',
          ),
          (
            (name, code, message) => Val.double(name: name, code: code, message: message),
            Object(),
            'INVALID_TYPE',
            IssueKind.invalidType,
            'Must be a double',
            'Label must be a double',
          ),
          (
            (name, code, message) => Val.number(name: name, code: code, message: message),
            Object(),
            'INVALID_TYPE',
            IssueKind.invalidType,
            'Must be a number',
            'Label must be a number',
          ),
          (
            (name, code, message) => Val.boolean(name: name, code: code, message: message),
            Object(),
            'INVALID_TYPE',
            IssueKind.invalidType,
            'Must be a boolean',
            'Label must be a boolean',
          ),
          (
            (name, code, message) => Val.moment(name: name, code: code, message: message),
            Object(),
            'INVALID_TYPE',
            IssueKind.invalidType,
            'Must be a Moment',
            'Label must be a Moment',
          ),
          (
            (name, code, message) =>
                Val.list(Val.string(), name: name, code: code, message: message),
            Object(),
            'INVALID_TYPE',
            IssueKind.invalidType,
            'Must be a list',
            'Label must be a list',
          ),
          (
            (name, code, message) => Val.object({}, name: name, code: code, message: message),
            Object(),
            'INVALID_TYPE',
            IssueKind.invalidType,
            'Must be an object with string keys',
            'Label must be an object with string keys',
          ),
          (
            (name, code, message) =>
                Val.map(Val.string(), name: name, code: code, message: message),
            Object(),
            'INVALID_TYPE',
            IssueKind.invalidType,
            'Must be an object with string keys',
            'Label must be an object with string keys',
          ),
          (
            (name, code, message) =>
                Val.instance<_Choice>(name: name, code: code, message: message),
            Object(),
            'INVALID_TYPE',
            IssueKind.invalidType,
            'Must be an instance of _Choice',
            'Label must be an instance of _Choice',
          ),
          (
            (name, code, message) => Val.any(name: name, code: code, message: message),
            Object(),
            'INVALID_TYPE',
            IssueKind.invalidType,
            'Must be a JSON value',
            'Label must be a JSON value',
          ),
          (
            (name, code, message) =>
                Val.object({'x': Val.string(name: name).required(code: code, message: message)}),
            <String, Object?>{},
            'REQUIRED',
            IssueKind.missing,
            'Value is required',
            'Label is required',
          ),
          (
            (name, code, message) => Val.string(name: name, code: code, message: message),
            null,
            'NOT_NULL',
            IssueKind.invalidType,
            'Must not be null',
            'Label must not be null',
          ),
          (
            (name, code, message) => Val.number(name: name, code: code, message: message),
            double.nan,
            'NOT_FINITE',
            IssueKind.notFinite,
            'Must be a finite number',
            'Label must be a finite number',
          ),
          (
            (name, code, message) =>
                Val.string(name: name).minLength(2, code: code, message: message),
            '',
            'MIN_LENGTH',
            IssueKind.tooSmall,
            'Must contain at least 2 characters',
            'Label must contain at least 2 characters',
          ),
          (
            (name, code, message) =>
                Val.list(Val.string(), name: name).minLength(2, code: code, message: message),
            [],
            'MIN_LENGTH',
            IssueKind.tooSmall,
            'Must contain at least 2 items',
            'Label must contain at least 2 items',
          ),
          (
            (name, code, message) =>
                Val.string(name: name).maxLength(1, code: code, message: message),
            'ab',
            'MAX_LENGTH',
            IssueKind.tooBig,
            'Must contain at most 1 character',
            'Label must contain at most 1 character',
          ),
          (
            (name, code, message) =>
                Val.list(Val.string(), name: name).maxLength(1, code: code, message: message),
            ['a', 'b'],
            'MAX_LENGTH',
            IssueKind.tooBig,
            'Must contain at most 1 item',
            'Label must contain at most 1 item',
          ),
          (
            (name, code, message) => Val.string(name: name).length(1, code: code, message: message),
            '',
            'LENGTH',
            IssueKind.invalidLength,
            'Must contain exactly 1 character',
            'Label must contain exactly 1 character',
          ),
          (
            (name, code, message) =>
                Val.list(Val.string(), name: name).length(1, code: code, message: message),
            [],
            'LENGTH',
            IssueKind.invalidLength,
            'Must contain exactly 1 item',
            'Label must contain exactly 1 item',
          ),
          (
            (name, code, message) => Val.int(name: name).min(2, code: code, message: message),
            1,
            'MIN',
            IssueKind.tooSmall,
            'Must be at least 2',
            'Label must be at least 2',
          ),
          (
            (name, code, message) => Val.int(name: name).max(2, code: code, message: message),
            3,
            'MAX',
            IssueKind.tooBig,
            'Must be at most 2',
            'Label must be at most 2',
          ),
          (
            (name, code, message) =>
                Val.int(name: name).greaterThan(2, code: code, message: message),
            2,
            'GREATER_THAN',
            IssueKind.tooSmall,
            'Must be greater than 2',
            'Label must be greater than 2',
          ),
          (
            (name, code, message) => Val.int(name: name).lessThan(2, code: code, message: message),
            2,
            'LESS_THAN',
            IssueKind.tooBig,
            'Must be less than 2',
            'Label must be less than 2',
          ),
          (
            (name, code, message) =>
                Val.int(name: name).multipleOf(2, code: code, message: message),
            3,
            'MULTIPLE_OF',
            IssueKind.notMultipleOf,
            'Must be a multiple of 2',
            'Label must be a multiple of 2',
          ),
          (
            (name, code, message) => Val.int(name: name).safe(code: code, message: message),
            9007199254740992,
            'SAFE_INTEGER',
            IssueKind.unsafeInteger,
            'Must be between -9007199254740991 and 9007199254740991',
            'Label must be between -9007199254740991 and 9007199254740991',
          ),
          (
            (name, code, message) => Val.string(name: name).email(code: code, message: message),
            'bad',
            'INVALID_EMAIL',
            IssueKind.invalidFormat,
            'Must be a valid email address',
            'Label must be a valid email address',
          ),
          (
            (name, code, message) => Val.string(name: name).url(code: code, message: message),
            'bad',
            'INVALID_URL',
            IssueKind.invalidFormat,
            'Must be an absolute URI with a scheme and host',
            'Label must be an absolute URI with a scheme and host',
          ),
          (
            (name, code, message) => Val.string(name: name).uuid(code: code, message: message),
            'bad',
            'INVALID_UUID',
            IssueKind.invalidFormat,
            'Must be a valid UUID',
            'Label must be a valid UUID',
          ),
          (
            (name, code, message) => Val.string(name: name).ip(code: code, message: message),
            'bad',
            'INVALID_IP',
            IssueKind.invalidFormat,
            'Must be a valid IP address',
            'Label must be a valid IP address',
          ),
          (
            (name, code, message) => Val.string(name: name).ipv4(code: code, message: message),
            'bad',
            'INVALID_IPV4',
            IssueKind.invalidFormat,
            'Must be a valid IPv4 address',
            'Label must be a valid IPv4 address',
          ),
          (
            (name, code, message) => Val.string(name: name).ipv6(code: code, message: message),
            'bad',
            'INVALID_IPV6',
            IssueKind.invalidFormat,
            'Must be a valid IPv6 address',
            'Label must be a valid IPv6 address',
          ),
          (
            (name, code, message) => Val.string(name: name).datetime(code: code, message: message),
            'bad',
            'INVALID_MOMENT',
            IssueKind.invalidFormat,
            'Must be a valid timestamp',
            'Label must be a valid timestamp',
          ),
          (
            (name, code, message) => Val.string(name: name).moment(code: code, message: message),
            'bad',
            'INVALID_MOMENT',
            IssueKind.invalidFormat,
            'Must be a valid timestamp',
            'Label must be a valid timestamp',
          ),
          (
            (name, code, message) => Val.string(name: name).chronoId(code: code, message: message),
            'bad',
            'INVALID_CHRONO_ID',
            IssueKind.invalidFormat,
            'Must be a valid Chrono ID',
            'Label must be a valid Chrono ID',
          ),
          (
            (name, code, message) =>
                Val.string(name: name).startsWith('x', code: code, message: message),
            'bad',
            'STARTS_WITH',
            IssueKind.invalidFormat,
            'Must start with "x"',
            'Label must start with "x"',
          ),
          (
            (name, code, message) =>
                Val.string(name: name).endsWith('x', code: code, message: message),
            'bad',
            'ENDS_WITH',
            IssueKind.invalidFormat,
            'Must end with "x"',
            'Label must end with "x"',
          ),
          (
            (name, code, message) =>
                Val.string(name: name).contains('x', code: code, message: message),
            'bad',
            'CONTAINS',
            IssueKind.invalidFormat,
            'Must contain "x"',
            'Label must contain "x"',
          ),
          (
            (name, code, message) =>
                Val.string(name: name).matches(RegExp('x'), code: code, message: message),
            'bad',
            'PATTERN',
            IssueKind.invalidFormat,
            'Must match the required pattern',
            'Label must match the required pattern',
          ),
          (
            (name, code, message) =>
                Val.moment(name: name).min(bound, code: code, message: message),
            _moment('2025-01-01T00:00:00Z'),
            'MIN_MOMENT',
            IssueKind.tooSmall,
            'Must be at or after 2026-01-01T00:00:00.000000Z',
            'Label must be at or after 2026-01-01T00:00:00.000000Z',
          ),
          (
            (name, code, message) =>
                Val.moment(name: name).max(bound, code: code, message: message),
            _moment('2027-01-01T00:00:00Z'),
            'MAX_MOMENT',
            IssueKind.tooBig,
            'Must be at or before 2026-01-01T00:00:00.000000Z',
            'Label must be at or before 2026-01-01T00:00:00.000000Z',
          ),
          (
            (name, code, message) =>
                Val.list(Val.int(), name: name).unique(code: code, message: message),
            [1, 1],
            'UNIQUE',
            IssueKind.notUnique,
            'Must contain unique items',
            'Label must contain unique items',
          ),
          (
            (name, code, message) => Val.literal('x', name: name, code: code, message: message),
            'y',
            'INVALID_LITERAL',
            IssueKind.invalidValue,
            'Must equal the expected value',
            'Label must equal the expected value',
          ),
          (
            (name, code, message) =>
                Val.enumString(['x'], name: name, code: code, message: message),
            'y',
            'INVALID_ENUM',
            IssueKind.invalidValue,
            'Must be one of the allowed values',
            'Label must be one of the allowed values',
          ),
          (
            (name, code, message) =>
                Val.enumValues([_Choice.first], name: name, code: code, message: message),
            _Choice.second,
            'INVALID_ENUM',
            IssueKind.invalidValue,
            'Must be one of the allowed values',
            'Label must be one of the allowed values',
          ),
          (
            (name, code, message) =>
                Val.object({}, name: name).strict(code: code, message: message),
            {'extra': 1},
            'UNRECOGNIZED_KEY',
            IssueKind.unrecognizedKey,
            'Property is not allowed',
            'Property is not allowed in Label',
          ),
          (
            (name, code, message) => Val.anyOf<Object>(
              [Val.string(), Val.int()],
              name: name,
              code: code,
              message: message,
            ),
            false,
            'INVALID_UNION',
            IssueKind.invalidUnion,
            'Must match one of the allowed schemas',
            'Label must match one of the allowed schemas',
          ),
          (
            (name, code, message) => Val.discriminated(
              discriminatorKey: 'kind',
              schemas: {
                'x': Val.object({'kind': Val.literal('x')}),
              },
              name: name,
              code: code,
              message: message,
            ),
            {'kind': 'y'},
            'INVALID_DISCRIMINATOR',
            IssueKind.invalidDiscriminator,
            'Must contain a recognized discriminator',
            'Label must contain a recognized discriminator',
          ),
          (
            (name, code, message) => Val.any(maxDepth: 1, name: name, code: code, message: message),
            [<Object?>[]],
            'MAX_DEPTH',
            IssueKind.maxDepth,
            'Must not exceed the maximum nesting depth',
            'Label must not exceed the maximum nesting depth',
          ),
          (
            (name, code, message) =>
                Val.string(name: name).refine((_) => false, code: code, message: message),
            'x',
            'CUSTOM',
            IssueKind.custom,
            'Invalid value',
            'Label is invalid',
          ),
        ];
    for (var index = 0; index < cases.length; index++) {
      final (build, input, code, kind, text, named) = cases[index];
      test('should preserve defaults, names, and independent overrides for $code case $index', () {
        final unnamed = issues(build(null, null, null), input).single;
        expect((unnamed.code, unnamed.kind, unnamed.message), (code, kind, text));
        final labeled = issues(build(' Label ', null, null), input).single;
        expect((labeled.code, labeled.kind, labeled.message), (code, kind, named));
        expect(labeled.path, unnamed.path);
        expect(issues(build('   ', null, null), input).single.message, text);
        final customCode = issues(build('Label', '', null), input).single;
        expect((customCode.code, customCode.kind, customCode.message), ('', kind, named));
        final customMessage = issues(build('Label', null, ''), input).single;
        expect((customMessage.code, customMessage.kind, customMessage.message), (code, kind, ''));
        final custom = issues(build('Label', 'APP', '{name} literal'), input).single;
        expect((custom.code, custom.kind, custom.message), ('APP', kind, '{name} literal'));
      });
    }
  });
}
