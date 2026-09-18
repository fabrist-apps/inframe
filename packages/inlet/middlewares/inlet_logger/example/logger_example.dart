import 'package:inlet/inlet.dart';
import 'package:inlet_logger/inlet_logger.dart';
import 'package:inlet_request_id/inlet_request_id.dart';

/// Prints a request summary to stdout without starting a server or Chronicler.
Future<void> main() async {
  final app = Inlet()
    ..use(logger())
    ..use(requestId)
    ..get('/items/:id', (_, _) => Response.text('ok'));
  final request = Request(method: 'GET', uri: Uri.parse('/items/example'));
  try {
    final response = await app.handle(request);
    await response.close();
  } finally {
    await request.close();
  }
}
