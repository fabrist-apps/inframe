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
  if ((name == 'XREAD' || name == 'XREADGROUP') && _hasBlockingOption(arguments, name)) {
    throw ArgumentError.value(name, 'command', 'blocking forms require a BlockingSession');
  }
}

String _text(RedisArgument argument) => ascii.decode(argument.bytes).toUpperCase();

bool _hasBlockingOption(List<RedisArgument> arguments, String command) {
  var index = 1;
  if (command == 'XREADGROUP' && _option(arguments, index) == 'GROUP') {
    index += 3;
  }
  while (index < arguments.length) {
    switch (_option(arguments, index)) {
      case 'BLOCK':
        return true;
      case 'COUNT':
        index += 2;
      case 'NOACK':
        index++;
      case 'STREAMS':
        return false;
      default:
        return false;
    }
  }
  return false;
}

String? _option(List<RedisArgument> arguments, int index) {
  if (index >= arguments.length) return null;
  try {
    return _text(arguments[index]);
  } on FormatException {
    return null;
  }
}
