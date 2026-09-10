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

The bridge, upstream bundle, and SQL parser adapter execute in a dedicated application worker.
Upstream Turso creates its own worker for OPFS access.

## Provenance

| Asset | Source | SHA-256 |
| --- | --- | --- |
| `turso_upstream.js` | npm `@tursodatabase/database-wasm@0.8.0-pre.10`, `bundle/main.es.js` | `f24740d5d56b258ed8dd0117c66b46b5fff3f29b8bad325914749fe96bf3d51d` |
| `turso_sql_guard.wasm` | `tool/sql_guard`, using `turso_parser` at `342dfbe267ebdb9141c434c499ce31e10bb46f27` | `adbc57136a7760eec5487eb71803222fb01da0ef5ce88abb6ab57b65e92d59d8` |

The npm tarball integrity is
`sha512-jzfyctq86UEpciLq/oN+WaL/VJy/a1ChMHnc8mN3BmaXNFIEAwbtKAWYyTbTLAAedfdKPVzqVFO6YP2BHzcoXQ==`.
The parser adapter only reports whether the pinned upstream parser sees zero, one, or multiple SQL
statements. It does not change Turso engine behavior.

| Asset | SHA-256 |
| --- | --- |
| `turso_upstream.js` | `f24740d5d56b258ed8dd0117c66b46b5fff3f29b8bad325914749fe96bf3d51d` |
| `turso_sql_guard.wasm` | `b2bd0d893e36640f5710e9dbe637acc36062c8961e0f1c8fc12a0a1b5bea0218` |
