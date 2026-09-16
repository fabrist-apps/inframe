import 'package:chrono_id/chrono_id.dart';
import 'package:conflux/src/val/issue.dart';
import 'package:conflux/src/val/schema.dart';
import 'package:conflux/src/val/string_schema.dart';

/// Chrono ID checks reuse the independent core's complete format contract.
extension ChronoIdChecks on Schema<String> {
  /// Validates a Chrono ID using the configured [prefix] and body [size].
  StringSchema chronoId({String? prefix, int size = 24, String? code, String? message}) =>
      withCheck(
        (value) => ChronoID.isValid(value, prefix: prefix, size: size),
        IssueTemplate(
          code ?? 'INVALID_CHRONO_ID',
          (name) => message ?? '${name == null ? 'Must' : '$name must'} be a valid Chrono ID',
        ),
      );
}
