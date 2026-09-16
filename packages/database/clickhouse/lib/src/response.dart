import 'dart:convert';

import 'package:clickhouse/src/exception.dart';
import 'package:clickhouse/src/query_result.dart';

/// Interprets a buffered ClickHouse HTTP response.
final class ClickHouseResponse {
  /// Creates a response after bounded body collection has completed.
  const ClickHouseResponse({
    required this.statusCode,
    required this.body,
    this.queryId,
    this.clickHouseCode,
  });

  /// HTTP response status.
  final int statusCode;

  /// Decompressed response bytes.
  final List<int> body;

  /// Query identifier supplied by the server.
  final String? queryId;

  /// Error code supplied in the response header.
  final int? clickHouseCode;

  /// Decodes a complete query result or reports the response failure.
  ClickHouseQueryResult decodeQuery() {
    _ensureSuccess();
    try {
      return decodeQueryResult(utf8.decode(body));
    } on FormatException catch (error) {
      // Valid query data can contain "Code: ...". Recognize late server errors
      // only after parsing the complete result has failed.
      final text = utf8.decode(body, allowMalformed: true).trim();
      final code = _errorCode(text);
      if (code != null) {
        throw _serverException(text, code);
      }
      throw ClickHouseProtocolException(
        message: 'ClickHouse returned a malformed query result: $error',
        requestState: ClickHouseRequestState.mayHaveReachedServer,
        queryId: queryId,
      );
    }
  }

  /// Validates the empty acknowledgement for a command or insert.
  void expectEmpty(String operation) {
    _ensureSuccess();
    final text = utf8.decode(body, allowMalformed: true).trim();
    final code = _errorCode(text);
    if (code != null) {
      throw _serverException(text, code);
    }
    if (text.isNotEmpty) {
      throw ClickHouseProtocolException(
        message: 'ClickHouse returned unexpected output for a $operation.',
        requestState: ClickHouseRequestState.mayHaveReachedServer,
        queryId: queryId,
      );
    }
  }

  void _ensureSuccess() {
    if (statusCode == 200) {
      return;
    }
    final text = utf8.decode(body, allowMalformed: true).trim();
    throw _serverException(
      text.isEmpty ? 'ClickHouse rejected the request with HTTP $statusCode.' : text,
      clickHouseCode ?? _errorCode(text),
    );
  }

  ClickHouseServerException _serverException(String message, int? code) =>
      ClickHouseServerException(
        message: message,
        requestState: ClickHouseRequestState.mayHaveReachedServer,
        queryId: queryId,
        statusCode: statusCode,
        clickHouseCode: code,
      );
}

int? _errorCode(String message) {
  final match = RegExp(r'Code: (\d+)').firstMatch(message);
  return match == null ? null : int.tryParse(match.group(1)!);
}
