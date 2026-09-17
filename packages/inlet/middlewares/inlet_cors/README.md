# inlet_cors

Explicit CORS policy for Inlet. Register before middleware that can return early:

```dart
import 'package:inlet/inlet.dart';
import 'package:inlet_cors/inlet_cors.dart';

final cors = Cors(
  allowedOrigins: ['https://app.example.com'],
  allowedMethods: ['GET', 'HEAD', 'POST', 'PUT', 'DELETE'],
  allowedHeaders: ['authorization', 'content-type'],
  exposedHeaders: ['x-request-id'],
  allowCredentials: true,
  maxAge: Duration(minutes: 10),
);
final app = Inlet()..use(cors.call);
```

Origins must be exact serialized HTTP(S) origins without paths or trailing
slashes. An explicit `null` allows opaque origins; only enable it deliberately.
`*` allows any origin but cannot be combined with credentials. Methods are
case-sensitive. Header names are case-insensitive, and wildcard header or
method policies are rejected. Configuration is copied when constructed.

Allowed preflights return 204 without invoking the handler. Rejected preflights
and malformed or duplicate origins return 403 without CORS grants. Ordinary
requests with absent or disallowed origins continue to the handler without
grants: CORS is browser response access control, not authentication or CSRF
protection. Ordinary OPTIONS requests continue to routing.

The middleware owns `access-control-*` response headers and replaces downstream
values. It merges `Vary` without losing existing tokens or `*`. Its response
hook also decorates error-handler responses and HEAD responses without consuming
response streams. Middleware that returns before CORS is reached receives no
CORS policy.
