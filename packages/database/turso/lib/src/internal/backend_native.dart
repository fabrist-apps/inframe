import 'package:turso/src/internal/backend.dart';
import 'package:turso/src/native/native_backend.dart';
import 'package:turso/src/turso_exception.dart';
import 'package:turso/src/turso_location.dart';
import 'package:turso/src/turso_options.dart';

/// Opens the native backend selected by conditional import.
Future<TursoBackend> openBackend(
  TursoLocation location, {
  TursoEncryption? encryption,
  TursoWebOptions? web,
}) {
  if (location is TursoBrowserLocation) {
    throw const TursoUnsupportedException('Browser locations require Flutter web.');
  }
  if (web != null) {
    throw ArgumentError.value(web, 'web', 'Native databases do not accept browser options.');
  }
  return NativeBackend.open(location, encryption: encryption);
}
