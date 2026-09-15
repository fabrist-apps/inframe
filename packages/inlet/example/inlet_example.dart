import 'dart:convert';
import 'dart:io';

import 'package:inlet/inlet.dart';

Future<void> main() async {
  final application = Inlet()
    ..post('/echo', (_, request) async {
      final document = await request.json(maxBytes: 64 * 1024);

      return Response.json(document);
    });

  await _runInProcess(application);
  await _runOverHttp(application);
}

Future<void> _runInProcess(Inlet application) async {
  final request = Request(
    method: 'POST',
    uri: Uri.parse('/echo'),
    body: Stream.value(utf8.encode('{"source":"in-process"}')),
  );
  Response? response;

  try {
    response = await application.handle(request);
    stdout.writeln(jsonEncode(await response.json()));
  } finally {
    try {
      await response?.close();
    } finally {
      await request.close();
    }
  }
}

Future<void> _runOverHttp(Inlet application) async {
  final server = await application.serve(port: 0);
  final client = HttpClient();

  try {
    final request = await client.post(
      server.address.address,
      server.port,
      '/echo',
    );
    request.add(utf8.encode('{"source":"http"}'));
    final response = await request.close();
    stdout.writeln(await utf8.decodeStream(response));
  } finally {
    try {
      client.close(force: true);
    } finally {
      await server.close();
    }
  }
}
