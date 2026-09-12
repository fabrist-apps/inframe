import 'dart:io';

Future<void> main(List<String> arguments) async {
  final port = arguments.isEmpty ? 8080 : int.parse(arguments.single);
  final packageRoot = File.fromUri(Platform.script).parent.parent;
  final webRoot = Directory('${packageRoot.path}/example/web');
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
  stdout.writeln('Serving ${webRoot.path} at http://localhost:$port');

  await for (final request in server) {
    request.response.headers
      ..set('Cross-Origin-Opener-Policy', 'same-origin')
      ..set('Cross-Origin-Embedder-Policy', 'require-corp')
      ..set('Cross-Origin-Resource-Policy', 'same-origin');
    final relativePath = request.uri.path == '/' ? 'index.html' : request.uri.path.substring(1);
    final file = File('${webRoot.path}/$relativePath');
    if (relativePath.contains('..') || !file.existsSync()) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      continue;
    }
    request.response.headers.contentType = _contentType(file.path);
    await request.response.addStream(file.openRead());
    await request.response.close();
  }
}

ContentType _contentType(String path) {
  if (path.endsWith('.html')) return ContentType.html;
  if (path.endsWith('.js')) return ContentType('text', 'javascript', charset: 'utf-8');
  if (path.endsWith('.wasm')) return ContentType('application', 'wasm');
  return ContentType.binary;
}
