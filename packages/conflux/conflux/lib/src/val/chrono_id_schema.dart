import 'package:chrono_id/chrono_id.dart';
import 'package:conflux/src/val/issue.dart';
import 'package:conflux/src/val/schema.dart';
import 'package:conflux/src/val/string_schema.dart';

/// Chrono ID checks reuse the independent core's complete format contract.
extension ChronoIdChecks on Schema<String> {
  /// Validates [prefix] and body [size] eagerly, then retains valid strings.
  ///
  /// Omitted prefix requires an unprefixed ID. Configuration validation invokes
  /// the pure core validator with a dummy candidate; it never generates an ID.
  StringSchema chronoId({String? prefix, int size = 24, String? code, String? message}) {
    ChronoID.isValid('', prefix: prefix, size: size);
    return withCheck(
      (value) => ChronoID.isValid(value, prefix: prefix, size: size),
      IssueTemplate(
        'INVALID_CHRONO_ID',
        IssueKind.invalidFormat,
        'Must be a valid Chrono ID',
        customCode: code,
        customMessage: message,
      ),
    );
  }
}
