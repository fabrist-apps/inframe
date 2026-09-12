# Runnel

Runnel is Inframe's internal pure Dart client for a standalone Redis or Valkey primary endpoint.
It supports TCP and trusted TLS, ACL credentials in the endpoint URL, RESP3 by default, and
explicit RESP2.

```dart
import 'package:runnel/runnel.dart';

final redis = await Runnel.connect('redis://localhost:6379');
try {
  await redis.set('user:42:name', 'Bhaswanth');
  final name = await redis.get('user:42:name');
  print(name);
} finally {
  await redis.close();
}
```

Runnel connects to one externally managed primary endpoint. It does not discover Cluster or
Sentinel topology and does not follow `MOVED` or `ASK` redirects. Keys and channels are preserved
exactly; callers own app scoping and authorization.

## Tested compatibility

The integration suite verifies TCP and TLS with RESP2 and RESP3 against:

- Redis 8.2.1, image index digest
  `sha256:5fa2edb1e408fa8235e6db8fab01d1afaaae96c9403ba67b70feceb8661e8621`.
- Valkey 8.1.3, image index digest
  `sha256:fea8b3e67b15729d4bb70589eb03367bab9ad1ee89c876f54327fc7c6e618571`.

Run unit tests with:

```sh
dart test packages/database/runnel/test --exclude-tags integration --chain-stack-traces
```

Run the disposable Docker integration environment with:

```sh
packages/database/runnel/tool/run_integration.sh
```
