import 'package:dart_mappable/dart_mappable.dart';
import 'package:dart_mappable_conflux/src/moment_mapper.dart';
import 'package:dart_mappable_conflux/src/option_mapper.dart';

/// Registers Conflux serialization support with dart_mappable.
abstract final class ConfluxMappers {
  /// Registers Moment and Option mappers globally; safe to call more than once.
  ///
  /// Option model fields still require OptionFieldsHook.
  static void initialize() {
    MapperContainer.globals
      ..use(const MomentMapper())
      ..use(const OptionMapper());
  }
}
