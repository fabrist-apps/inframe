// Package-internal validation shared by ordinary execution and batch builders.
// ignore_for_file: public_member_api_docs

import 'dart:convert';

import 'package:runnel/src/command.dart';

const _reservedCommands = {
  'AUTH',
  'HELLO',
  'SELECT',
  'MULTI',
  'EXEC',
  'DISCARD',
  'WATCH',
  'UNWATCH',
  'SUBSCRIBE',
  'PSUBSCRIBE',
  'SSUBSCRIBE',
  'UNSUBSCRIBE',
  'PUNSUBSCRIBE',
  'SUNSUBSCRIBE',
  'MONITOR',
  'RESET',
  'QUIT',
  'BLPOP',
  'BRPOP',
  'BLMOVE',
  'BRPOPLPUSH',
  'BZPOPMIN',
  'BZPOPMAX',
  'WAIT',
  'WAITAOF',
};

void validateOrdinaryCommand(RedisCommand<Object?> command) {
  final name = ascii.decode(command.arguments.first.bytes).toUpperCase();
  if (_reservedCommands.contains(name)) {
    throw ArgumentError.value(name, 'command', 'is reserved for a dedicated Runnel session');
  }
  final arguments = command.arguments;
  if (name == 'CLIENT' && arguments.length > 1 && _text(arguments[1]) == 'REPLY') {
    throw ArgumentError.value('CLIENT REPLY', 'command', 'can suppress reply alignment');
  }
  if ((name == 'XREAD' || name == 'XREADGROUP') &&
      arguments.skip(1).any((argument) => _text(argument) == 'BLOCK')) {
    throw ArgumentError.value(name, 'command', 'blocking forms require a BlockingSession');
  }
}

String _text(RedisArgument argument) => ascii.decode(argument.bytes).toUpperCase();
