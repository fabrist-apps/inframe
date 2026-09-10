import 'package:turso/src/internal/backend.dart';
import 'package:turso/src/turso_exception.dart';
import 'package:turso/src/turso_location.dart';
import 'package:turso/src/turso_options.dart';

/// Opens the web backend selected by conditional import.
Future<TursoBackend> openBackend(
  TursoLocation location, {
  TursoEncryption? encryption,
  TursoWebOptions? web,
}) async {
  throw const TursoUnsupportedException('Flutter web support is implemented by FBR-27.');
}
