import 'dart:convert';

import 'package:conflux/conflux.dart';
import 'package:dart_mappable/dart_mappable.dart';
import 'package:test/test.dart';

part 'mappers_serialization_test.mapper.dart';

@MappableClass(hook: OptionFieldsHook(['value']))
class Payload with PayloadMappable {
  const Payload(this.value);

  final Option<Moment?> value;
}

@MappableClass(hook: OptionFieldsHook(['renamed']), ignoreNull: true)
class Box<T> with BoxMappable<T> {
  const Box(this.item);

  @MappableField(key: 'renamed')
  final Option<T> item;
}

@MappableClass(discriminatorKey: 'kind', hook: OptionFieldsHook(['note']))
class Message with MessageMappable {
  const Message(this.note);
  final Option<String?> note;
}

@MappableClass(discriminatorValue: 'tagged')
class TaggedMessage extends Message with TaggedMessageMappable {
  const TaggedMessage(super.note, this.label);

  @MappableField(key: 'display_label', hook: UppercaseHook())
  final String label;
}

class UppercaseHook extends MappingHook {
  const UppercaseHook();

  @override
  Object? afterEncode(Object? value) => (value! as String).toUpperCase();
}

void main() {
  setUpAll(() {
    Conflux.initialize();
    PayloadMapper.ensureInitialized();
    BoxMapper.ensureInitialized();
    TaggedMessageMapper.ensureInitialized();
  });

  group('MomentMapper', () {
    test('should decode a named zone as its serialized fixed offset', () {
      final utc = (Moment.parse('2026-01-18T02:30:00Z') as Success<Moment, MomentError>).value;
      final zone = (TimeZone.named('Asia/Singapore') as Success<NamedTimeZone, MomentError>).value;
      final named = (utc.setZone(zone) as Success<ZonedMoment, MomentError>).value;
      final decoded = MapperContainer.globals.fromValue<Moment>(
        MapperContainer.globals.toValue(named),
      );
      expect(decoded.microsecondsSinceEpoch, named.microsecondsSinceEpoch);
      expect(decoded.offset, named.offset);
      expect((decoded as ZonedMoment).zone, isA<FixedTimeZone>());
    });

    test('should reject malformed timestamps and non-string inputs', () {
      for (final input in <Object>[42, '2026-02-30T00:00:00Z', '2026-01-18T00:00:00']) {
        expect(
          () => MapperContainer.globals.fromValue<Moment>(input),
          throwsA(isA<MapperException>()),
        );
      }
    });

    test('should round trip UTC and fixed offsets at microsecond precision', () {
      for (final text in [
        '2026-01-18T10:30:00.123456Z',
        '2026-01-18T10:30:00.123456+08:00',
        '2026-01-18T10:30:00.123456+00:00',
        '1900-01-18T10:30:00.123456-04:56:02',
      ]) {
        final moment = (Moment.parse(text) as Success<Moment, MomentError>).value;
        expect(MapperContainer.globals.toValue(moment), text);
        expect(MapperContainer.globals.fromValue<Moment>(text), moment);
      }
    });
  });

  group('OptionMapper', () {
    test('should remove markers only at configured dotted paths without mutating input', () {
      final marker = MapperContainer.globals.toValue<Option<int>>(const None());
      final input = <String, dynamic>{
        'profile': <String, dynamic>{'nickname': marker, 'age': 42},
        'untouched': marker,
      };
      final output =
          const OptionFieldsHook(['profile.nickname']).afterEncode(input)! as Map<String, dynamic>;
      expect(output['profile'], {'age': 42});
      expect(output['untouched'], same(marker));
      expect((input['profile'] as Map<String, dynamic>).containsKey('nickname'), isTrue);
      expect(const OptionFieldsHook(['missing.child']).afterEncode({}), isEmpty);
    });

    test('should distinguish missing and null at dotted paths during decoding', () {
      const hook = OptionFieldsHook(['profile.nickname']);
      for (final present in [false, true]) {
        final profile = <String, dynamic>{if (present) 'nickname': null};
        final output = hook.beforeDecode({'profile': profile})! as Map<String, dynamic>;
        final encoded = (output['profile'] as Map<String, dynamic>)['nickname'];
        final decoded = MapperContainer.globals.fromValue<Option<String?>>(encoded);
        if (present) {
          expect((decoded as Some<String?>).value, isNull);
        } else {
          expect(decoded, isA<None>());
        }
        expect(profile, <String, dynamic>{if (present) 'nickname': null});
      }
    });

    test('should preserve inherited discriminators and custom field hooks', () {
      const Message message = TaggedMessage(None(), 'hello');
      final encoded = MapperContainer.globals.toValue<Message>(message);
      expect(encoded, {'kind': 'tagged', 'display_label': 'HELLO'});
      final decoded = MessageMapper.fromMap(encoded as Map<String, dynamic>);
      expect(decoded, isA<TaggedMessage>());
      expect(decoded.note, isA<None>());
    });

    test('should retain explicit null with renamed keys and ignoreNull', () {
      expect(const Box<int?>(Some(null)).toMap(), {'renamed': null});
      expect(const Box<int?>(None()).toJson(), '{}');
      final input = <String, dynamic>{'renamed': null};
      final decoded = BoxMapper.fromMap<int?>(input);
      expect((decoded.item as Some<int?>).value, isNull);
      expect(input, {'renamed': null});
      expect(BoxMapper.fromMap<int>({}).item, isA<None>());
      expect(() => BoxMapper.fromMap<int>({'renamed': null}), throwsA(isA<MapperException>()));
    });

    test('should recursively map nested models and collections', () {
      const nested = Box<List<Payload>>(Some([Payload(None()), Payload(Some(null))]));
      expect(nested.toMap(), {
        'renamed': [
          <String, Object?>{},
          {'value': null},
        ],
      });
      final decoded = BoxMapper.fromJson<List<Payload>>(nested.toJson());
      final values = (decoded.item as Some<List<Payload>>).value;
      expect(values.first.value, isA<None>());
      expect(values.last.value, isA<Some<Moment?>>());
    });

    test('should serialize standalone Some and reject nested absence', () {
      expect(MapperContainer.globals.toValue<Option<int>>(const Some(3)), 3);
      expect(MapperContainer.globals.toValue<Option<int?>>(const Some(null)), isNull);
      expect(
        () => MapperContainer.globals.toValue<Option<Option<int>>>(const Some(None())),
        throwsA(isA<MapperException>()),
      );
      expect(
        () => const Box<List<Option<int>>>(Some([None()])).toJson(),
        throwsA(isA<JsonUnsupportedObjectError>()),
      );
    });

    test('should omit None and retain Some(null) as explicit null', () {
      expect(const Payload(None()).toMap(), isEmpty);
      expect(const Payload(Some(null)).toMap(), {'value': null});
      expect(PayloadMapper.fromMap({}).value, isA<None>());
      expect(PayloadMapper.fromMap({'value': null}).value, isA<Some<Moment?>>());
      expect((PayloadMapper.fromMap({'value': null}).value as Some<Moment?>).value, isNull);
    });

    test('should recursively map a present Moment', () {
      const text = '2026-01-18T10:30:00.123456+08:00';
      final moment = (Moment.parse(text) as Success<Moment, MomentError>).value;
      final payload = Payload(Some(moment));
      expect(payload.toMap(), {'value': text});
      expect((PayloadMapper.fromJson(payload.toJson()).value as Some<Moment?>).value, moment);
    });

    test('should reject unremoved None markers when encoding JSON', () {
      expect(
        () => MapperContainer.globals.toJson<Option<int>>(const None()),
        throwsA(isA<JsonUnsupportedObjectError>()),
      );
      expect(
        () => MapperContainer.globals.toJson<List<Option<int>>>([const None()]),
        throwsA(isA<JsonUnsupportedObjectError>()),
      );
    });
  });
}
