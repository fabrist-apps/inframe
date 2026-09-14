# Browser assets

Applications copy this directory into their hosted web root with:

```sh
dart run tool/install_web.dart <application-web-directory>/turso
```

Pass the resulting bridge URI to `TursoWebOptions`, for example
`Uri.parse('turso/turso_bridge.js')`. Serve the application from a secure context with these
response headers on the page, worker, JavaScript and WASM resources:

```text
Cross-Origin-Opener-Policy: same-origin
Cross-Origin-Embedder-Policy: require-corp
```

The bridge, OPFS path adapter, upstream bundle, and SQL parser adapter execute in a dedicated application worker.
Upstream Turso creates its own worker for OPFS access.

ATTACH and DETACH are enabled by the bridge for ordinary and encrypted opens. In-memory attachments
need no additional browser files. From a persistent main database, the filename and alias may be
direct arguments or positional and named parameters. The bridge snapshots bindings before awaiting
OPFS registration and executes the original SQL and bindings without interpolation. Bound aliases
retain their supplied spelling, so callers should use a stable lowercase alias in later statements.
Computed attachment arguments are unsupported.

A persistent path may be a normalized relative path or a lowercase `file:` URI containing one
percent-encoded relative path, optional `mode=rwc`, and paired `cipher` and `hexkey` options. Supported
ciphers are `aegis256` and `aes256gcm`; the key must be exactly 64 hexadecimal characters.
Authorities, fragments, absolute or escaping paths, other modes, and other options are rejected before file
acquisition. Nested directories are created during open. The original URI reaches Turso unchanged while its decoded path identifies the
OPFS registration. URI keys remain scoped to the current operation and are redacted from bridge
errors. They are not inherited or restored after reload.

The bridge registers the attached database and its WAL with the existing Turso OPFS worker before
executing the original SQL. DETACH releases those registrations after the engine releases the alias;
closing the main database releases every remaining attachment. Reopening never restores aliases
automatically. A browser memory main supports memory attachments only.

The registry keeps one logical owner per alias and one OPFS registration per filename. Failed
attachment execution releases only registrations acquired for that attempt. Failed DETACH leaves
the existing alias and registration intact. Close drains accepted Dart operations, closes the Turso
engine, and then releases attachment registrations. An uncertain execution, finalization, or worker
protocol outcome retires the connection before cleanup, so queued and future operations fail.

Persistent attachments from an in-memory browser main are rejected before acquiring OPFS handles.
Browser attachment paths cannot contain backslashes, NUL, empty segments, or escape the OPFS root. An attachment database and its
`-wal` file must not overlap another database/WAL pair owned by the same connection. A competing
browser worker or tab that owns the same OPFS file causes an explicit open failure; the bridge does not steal the handle or
fall back to memory. Re-run the installer whenever these assets change.

The public existence inspection traverses directories and requests the final file with
`create: false`. It never creates a directory or file and never opens a database or synchronous
access handle. The bridge remains version checked for this operation.

## Provenance

| Asset | Source | SHA-256 |
| --- | --- | --- |
| `turso_attachment_registry.js` | Package-owned retryable alias and registration ownership state | `4572d1a01b09d9a6402bc8e3862630898da9af6baf282e2afb1e921de5374a14` |
| `turso_opfs_paths.js` | Package-owned normalized traversal and read-only inspection | `e3716ec5d1785360b2395997d15b87c87fde6660efeacfc5af54ae7ec1e4fd5e` |
| `turso_upstream.js` | `tool/web_bundle`: pinned npm modules plus the package-owned ATTACH IO adapter | `4efbb83f461463864d9a0ffb71f8b2b578ad007a96a7798640f00e3b5c192518` |
| `turso_sql_guard.wasm` | `tool/sql_guard`, using `turso_parser` at `342dfbe267ebdb9141c434c499ce31e10bb46f27` | `53befd5b351189a382af748f7148525d39ed0681d636d4664c8d1775dae66297` |

The npm tarball integrity is
`sha512-jzfyctq86UEpciLq/oN+WaL/VJy/a1ChMHnc8mN3BmaXNFIEAwbtKAWYyTbTLAAedfdKPVzqVFO6YP2BHzcoXQ==`.
The bundle inputs and reproduction command are recorded in `tool/web_bundle/README.md`. The adapter
changes only the pinned JavaScript worker protocol: acknowledged OPFS registrations expose their
worker handles to the same main WASM instance, and the fresh ATTACH open uses a bounded synchronous
worker request. Registration mutations are serialized, access handles remain indexed until close
succeeds, and a timed-out, malformed, or failed worker session is poisoned. The Turso Rust/WASM
engine binary remains unchanged.

The parser adapter reports one-statement validation plus structured ATTACH/DETACH argument metadata
from the matching pinned parser. It does not change Turso engine behavior.
