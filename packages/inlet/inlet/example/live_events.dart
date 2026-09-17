import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:inlet/inlet.dart';

Future<void> main() async {
  final application = Inlet()..get('/events', (_, _) => Response.sse(documentUpdates()));
  final server = await application.serve(port: 0);
  final client = HttpClient();

  try {
    final request = await client.get(
      server.address.address,
      server.port,
      '/events',
    );
    final response = await request.close();
    stdout.write(await utf8.decodeStream(response));
  } finally {
    try {
      client.close(force: true);
    } finally {
      await server.close();
    }
  }
}

Stream<SseEvent> documentUpdates() async* {
  final heartbeat = Completer<void>();
  final timer = Timer(
    const Duration(milliseconds: 10),
    heartbeat.complete,
  );

  try {
    yield SseEvent.json(
      {'title': 'Ready'},
      event: 'document',
      id: 'event-1',
    );
    await heartbeat.future;
    yield SseEvent.comment('keep-alive');
  } finally {
    timer.cancel();
  }
}
