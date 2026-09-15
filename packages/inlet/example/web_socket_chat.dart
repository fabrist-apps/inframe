import 'dart:async';
import 'dart:io';

import 'package:inlet/inlet.dart';

Future<void> main() async {
  final sessions = <WebSocket>{};
  final application = Inlet()
    ..get('/chat', (_, _) {
      return Response.webSocket(
        selectProtocol: (offered) {
          if (offered.contains('chat.v1')) {
            return 'chat.v1';
          }

          throw const WebSocketException('chat.v1 is required.');
        },
        onConnect: (socket) async {
          sessions.add(socket);

          try {
            await for (final message in socket) {
              for (final session in sessions) {
                session.add(message);
              }
            }
          } finally {
            sessions.remove(socket);
          }
        },
      );
    });
  final server = await application.serve(port: 0);
  final uri = 'ws://${server.address.address}:${server.port}/chat';
  WebSocket? first;
  WebSocket? second;

  try {
    first = await WebSocket.connect(uri, protocols: ['chat.v1']);
    second = await WebSocket.connect(uri, protocols: ['chat.v1']);
    await _waitUntil(() => sessions.length == 2);

    final firstMessages = StreamIterator<Object?>(first);
    final secondMessages = StreamIterator<Object?>(second);
    first.add('hello');
    await firstMessages.moveNext();
    await secondMessages.moveNext();
    stdout
      ..writeln('${first.protocol}: ${firstMessages.current}')
      ..writeln('${second.protocol}: ${secondMessages.current}');

    // Closing the listener only stops admission. The application registry owns
    // coordinated shutdown for callback-owned WebSocket sessions.
    await server.close();
    final firstDone = firstMessages.moveNext();
    final secondDone = secondMessages.moveNext();
    final closingSessions = Future.wait(
      sessions.map(
        (socket) => socket.close(WebSocketStatus.goingAway, 'application shutdown'),
      ),
    );
    await Future.wait([firstDone, secondDone]);
    await closingSessions;
    await _waitUntil(() => sessions.isEmpty);
  } finally {
    await first?.close();
    await second?.close();
    await server.close(force: true);
  }
}

Future<void> _waitUntil(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 2));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('Chat sessions did not settle.');
    }

    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}
