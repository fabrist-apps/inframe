import 'package:turso/src/turso_location.dart';
import 'package:turso/src/turso_options.dart';

/// Rejects browser file inspection outside Flutter web.
Future<bool> browserFileExists(
  TursoBrowserLocation location, {
  required TursoWebOptions webOptions,
}) => throw UnsupportedError('Browser OPFS inspection is available only on Flutter web.');
