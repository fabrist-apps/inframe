import 'dart:convert';
import 'dart:io';

import 'package:conflux/conflux.dart';

void main() {
  Conflux.initialize();

  final profile =
      Val.object({
        'username': Val.string(name: 'Username').minLength(3),
        'email': Val.string(name: 'Email').email(),
        'age': Val.int(name: 'Age').min(18),
        'nickname': Val.string().nullable().optional(),
      }).strip().refine(
        (value) => value['nickname'] != value['username'],
        path: [const FieldSegment('nickname')],
        code: 'DUPLICATE_NAME',
        message: 'Nickname must differ from username',
      );

  final result = profile.safeParse({
    'username': 'Al',
    'email': 'invalid',
    'age': 16,
    'ignored': true,
  });

  switch (result) {
    case Success(:final value):
      stdout.writeln(jsonEncode(value));
    case Failure(:final error):
      stdout.writeln(jsonEncode(error.map((issue) => issue.toMap()).toList()));
  }
}
