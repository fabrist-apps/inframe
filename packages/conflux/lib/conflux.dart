/// Functional values and effectful composition for Inframe.
library;

import 'package:conflux/moment.dart';
import 'package:conflux/option.dart';
import 'package:conflux/src/val/path.dart';
import 'package:dart_mappable/dart_mappable.dart';
import 'package:timezone/data/latest.dart' as timezone_data;
import 'package:timezone/timezone.dart' as timezone;

export 'cache.dart';
export 'cron.dart';
export 'effect.dart';
export 'flow.dart';
export 'moment.dart';
export 'non_empty_list.dart';
export 'option.dart';
export 'pubsub.dart';
export 'queue.dart';
export 'result.dart';
export 'schedule.dart';
export 'val.dart';

/// Package-wide setup for Conflux capabilities.
abstract final class Conflux {
  /// Registers Conflux mappers and loads the bundled IANA timezone database.
  ///
  /// Call once at application startup in each isolate that uses generated
  /// serialization or named zones. An already initialized database is retained,
  /// making repeated calls safe.
  /// On first initialization, timezone sets its default local zone to UTC.
  static void initialize() {
    MapperContainer.globals
      ..use(const MomentMapper())
      ..use(const OptionMapper())
      ..use(const PathSegmentMapper());

    if (timezone.timeZoneDatabase.isInitialized) {
      return;
    }

    timezone_data.initializeTimeZones();
  }
}
