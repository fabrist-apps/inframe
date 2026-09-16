/// Shared text inference values and public provider capability contracts.
@MappableLib(generateInitializerForScope: InitializerScope.package)
library;

import 'package:artificer_core/artificer_core.init.dart' as generated;
import 'package:conflux/conflux.dart' show Conflux;
import 'package:dart_mappable/dart_mappable.dart';

export 'artificer_core.init.dart';
export 'src/embeddings/embeddings.dart';
export 'src/errors.dart';
export 'src/generation/generation.dart';
export 'src/messages/messages.dart';
export 'src/models.dart';
export 'src/native.dart';
export 'src/settings.dart';
export 'src/tools/tools.dart';

/// Package-wide setup for Artificer Core serialization.
abstract final class ArtificerCore {
  /// Initializes Conflux and registers all core mappers in the current isolate.
  /// Call before serialization; repeated calls are safe and create no runtime.
  /// Loads Conflux's timezone database if it has not already been initialized.
  static void initialize() {
    Conflux.initialize();
    generated.initializeMappers();
  }
}
