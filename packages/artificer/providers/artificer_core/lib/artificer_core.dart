/// Shared text inference values and public provider capability contracts.
@MappableLib(generateInitializerForScope: InitializerScope.package)
library;

import 'package:artificer_core/artificer_core.init.dart' as generated;
import 'package:dart_mappable/dart_mappable.dart';

export 'artificer_core.init.dart';
export 'src/embeddings/embeddings.dart';
export 'src/errors.dart';
export 'src/generation/generation.dart';
export 'src/messages/messages.dart';
export 'src/models.dart';
export 'src/native.dart';
export 'src/observations.dart';
export 'src/settings.dart';
export 'src/tools/tools.dart';

/// Registers all shipped core mappers for container-based decoding.
void initializeArtificerCoreMappers() => generated.initializeMappers();
