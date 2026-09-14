import 'package:turso/src/internal/browser_file_inspection_unsupported.dart'
    if (dart.library.js_interop) 'package:turso/src/internal/backend_web.dart'
    as platform;
import 'package:turso/src/turso_location.dart';
import 'package:turso/src/turso_options.dart';

/// Dispatches browser file inspection to the selected platform implementation.
Future<bool> browserFileExists(
  TursoBrowserLocation location, {
  required TursoWebOptions web,
}) => platform.browserFileExists(location, webOptions: web);
