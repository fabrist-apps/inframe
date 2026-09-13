import 'dart:convert';

// Shared by offline checking and resealing.
// ignore_for_file: public_member_api_docs

List<Map<String, int>> parseRivetSqlStatements(String sql) {
  final ranges = <Map<String, int>>[];
  var statementStart = _skipWhitespace(sql, 0);
  var index = statementStart;
  var blockDepth = 0;
  var quote = 0;
  var backslashEscapes = false;
  String? dollarTag;
  while (index < sql.length) {
    if (dollarTag != null) {
      if (sql.startsWith(dollarTag, index)) {
        index += dollarTag.length;
        dollarTag = null;
      } else {
        index++;
      }
      continue;
    }
    if (blockDepth > 0) {
      if (sql.startsWith('/*', index)) {
        blockDepth++;
        index += 2;
      } else if (sql.startsWith('*/', index)) {
        blockDepth--;
        index += 2;
      } else {
        index++;
      }
      continue;
    }
    if (quote != 0) {
      if (backslashEscapes && sql.codeUnitAt(index) == 0x5c && index + 1 < sql.length) {
        index += 2;
      } else if (sql.codeUnitAt(index) == quote) {
        if (index + 1 < sql.length && sql.codeUnitAt(index + 1) == quote) {
          index += 2;
        } else {
          quote = 0;
          backslashEscapes = false;
          index++;
        }
      } else {
        index++;
      }
      continue;
    }
    if (sql.startsWith('--', index)) {
      final newline = sql.indexOf('\n', index + 2);
      index = newline < 0 ? sql.length : newline + 1;
      continue;
    }
    if (sql.startsWith('/*', index)) {
      blockDepth = 1;
      index += 2;
      continue;
    }
    final unit = sql.codeUnitAt(index);
    if (unit == 0x27 || unit == 0x22) {
      quote = unit;
      backslashEscapes =
          unit == 0x27 &&
          index > 0 &&
          (sql.codeUnitAt(index - 1) == 0x45 || sql.codeUnitAt(index - 1) == 0x65) &&
          (index < 2 || !RegExp(r'[A-Za-z0-9_$]').hasMatch(sql[index - 2]));
      index++;
      continue;
    }
    if (unit == 0x24) {
      final match = RegExp(r'^\$[A-Za-z_][A-Za-z0-9_]*\$|^\$\$').firstMatch(sql.substring(index));
      if (match != null) {
        dollarTag = match[0]!;
        index += dollarTag.length;
        continue;
      }
    }
    if (unit == 0x3b) {
      ranges.add({
        'startByte': utf8.encode(sql.substring(0, statementStart)).length,
        'endByte': utf8.encode(sql.substring(0, index + 1)).length,
      });
      statementStart = _skipWhitespace(sql, index + 1);
      index = statementStart;
      continue;
    }
    index++;
  }
  if (quote != 0 || dollarTag != null || blockDepth != 0) {
    throw const FormatException('Migration SQL contains an unterminated quote or comment.');
  }
  if (!_commentsAndWhitespaceOnly(sql.substring(statementStart))) {
    throw const FormatException('Migration SQL contains an incomplete statement.');
  }
  return ranges;
}

int _skipWhitespace(String value, int start) {
  var index = start;
  while (index < value.length && const {0x20, 0x09, 0x0a, 0x0d}.contains(value.codeUnitAt(index))) {
    index++;
  }
  return index;
}

bool _commentsAndWhitespaceOnly(String value) {
  final stripped = value
      .replaceAll(RegExp(r'--[^\n]*(\n|$)'), '')
      .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '');
  return stripped.trim().isEmpty;
}
