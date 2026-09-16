// Package-internal endpoint and handshake configuration.
import 'dart:io';

import 'package:runnel/src/command.dart';

/// Endpoint identity, TLS options, and ordered handshake commands.
final class ConnectionConfiguration {
  /// Creates connection details inherited by dedicated sessions.
  const ConnectionConfiguration({
    required this.host,
    required this.port,
    required this.tls,
    this.database = 0,
    this.username,
    this.password,
    this.securityContext,
  });

  /// Parses a Redis URL without exposing credentials in validation errors.
  factory ConnectionConfiguration.parse(
    String endpoint, {
    required SecurityContext? securityContext,
  }) {
    final uri = Uri.tryParse(endpoint);
    if (uri == null || (uri.scheme != 'redis' && uri.scheme != 'rediss') || uri.host.isEmpty) {
      throw ArgumentError.value(
        _redact(endpoint),
        'endpoint',
        'must be a redis:// or rediss:// URL',
      );
    }
    if (uri.hasQuery || uri.hasFragment) {
      throw ArgumentError.value(
        _redact(endpoint),
        'endpoint',
        'query and fragment are unsupported',
      );
    }
    final tls = uri.scheme == 'rediss';
    if (!tls && securityContext != null) {
      throw ArgumentError.value(securityContext, 'securityContext', 'requires rediss://');
    }
    final segments = uri.pathSegments.where((segment) => segment.isNotEmpty).toList();
    if (segments.length > 1 || (uri.path.isNotEmpty && uri.path != '/' && segments.isEmpty)) {
      throw ArgumentError.value(_redact(endpoint), 'endpoint', 'database path is malformed');
    }
    final database = segments.isEmpty ? 0 : int.tryParse(segments.single);
    if (database == null ||
        database < 0 ||
        (segments.isNotEmpty && '$database' != segments.single)) {
      throw ArgumentError.value(
        _redact(endpoint),
        'endpoint',
        'database must be a nonnegative decimal',
      );
    }
    String? username;
    String? password;
    if (uri.userInfo.isNotEmpty) {
      final separator = uri.userInfo.indexOf(':');
      if (separator < 0) {
        password = Uri.decodeComponent(uri.userInfo);
      } else {
        final rawUsername = uri.userInfo.substring(0, separator);
        username = rawUsername.isEmpty ? null : Uri.decodeComponent(rawUsername);
        password = Uri.decodeComponent(uri.userInfo.substring(separator + 1));
      }
    }
    return ConnectionConfiguration(
      host: uri.host,
      port: uri.hasPort ? uri.port : 6379,
      tls: tls,
      database: database,
      username: username,
      password: password,
      securityContext: securityContext,
    );
  }

  /// TLS trust and client certificates.
  final SecurityContext? securityContext;

  /// Negotiates RESP3, authenticates when configured, and selects the database.
  Iterable<RedisCommand<Object?>> get handshakeCommands sync* {
    yield RedisCommand<Object?>.internal([
      RedisArgument.text('HELLO'),
      RedisArgument.text('3'),
      if (password case final secret?) ...[
        RedisArgument.text('AUTH'),
        RedisArgument.text(username ?? 'default'),
        RedisArgument.text(secret),
      ],
    ], (reply) => reply);
    if (database != 0) {
      yield RedisCommand<Object?>.internal([
        RedisArgument.text('SELECT'),
        RedisArgument.text('$database'),
      ], (reply) => reply);
    }
  }

  /// Server hostname.
  final String host;

  /// Server port.
  final int port;

  /// Whether the connection uses TLS.
  final bool tls;

  /// Logical database index.
  final int database;

  /// ACL username, defaulting to the default user when omitted.
  final String? username;

  /// Optional authentication secret.
  final String? password;

  static String _redact(String endpoint) {
    final uri = Uri.tryParse(endpoint);
    if (uri == null || uri.userInfo.isEmpty) return endpoint;
    return uri.replace(userInfo: '').toString();
  }
}
