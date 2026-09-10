import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:inlet/inlet.dart';

Future<void> main() async {
  final application = Inlet()
    ..post(
      '/transfer',
      (_, request) => Response.stream(
        request.body,
        contentType: 'text/plain; charset=utf-8',
      ),
    );
  final source = StreamController<List<int>>();
  final request = Request(
    method: 'POST',
    uri: Uri.parse('/transfer'),
    body: source.stream,
  );
  Response? response;

  try {
    response = await application.handle(request);
    final transferred = response.text();
    source
      ..add(utf8.encode('lazy '))
      ..add(utf8.encode('transfer'));
    await source.close();
    stdout.writeln(await transferred);
  } finally {
    await response?.close();
    await request.close();
    if (!source.isClosed) {
      await source.close();
    }
  }
}
