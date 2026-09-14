/// Functional values and effectful composition for Inframe.
library;

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

/// Package-wide setup for Conflux capabilities.
abstract final class Conflux {
  /// Loads the bundled IANA timezone database for named zones and Cron.
  ///
  /// Call once at application startup in each isolate that uses named zones.
  /// UTC and fixed-offset Moments do not require initialization.
  /// An already initialized database is retained, making repeated calls safe.
  /// On first initialization, timezone sets its default local zone to UTC.
  static void initialize() {
    if (timezone.timeZoneDatabase.isInitialized) return;

    timezone_data.initializeTimeZones();
  }
}
