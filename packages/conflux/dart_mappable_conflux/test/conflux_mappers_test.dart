import 'package:conflux/moment.dart';
import 'package:conflux/option.dart';
import 'package:dart_mappable/dart_mappable.dart';
import 'package:dart_mappable_conflux/dart_mappable_conflux.dart';
import 'package:test/test.dart';

void main() {
  group('ConfluxMappers', () {
    test('should register both mappers without generated model initialization', () {
      ConfluxMappers.initialize();
      ConfluxMappers.initialize();

      const timestamp = '2026-01-18T10:30:00.123456+08:00';
      final moment = MapperContainer.globals.fromValue<Moment>(timestamp);

      expect(MapperContainer.globals.toValue(moment), timestamp);
      expect(MapperContainer.globals.toValue<Option<Moment>>(Some(moment)), timestamp);
      expect(
        (MapperContainer.globals.fromValue<Option<Moment>>(timestamp) as Some<Moment>).value,
        moment,
      );
    });
  });
}
