# Browser bundle

This build composes the pinned Turso npm modules into `web/turso_upstream.js`. The package-owned
`wasm_common_patch.mjs` adapter is selected for every `database-wasm-common` import so the database,
main WASM instance, and OPFS worker share one registration map and module instance.

The adapter is limited to persistent ATTACH. Turso `0.8.0-pre.10` registers OPFS files in its worker,
but a fresh ATTACH opens its registry miss synchronously from the main WASM instance. The adapter
returns the acknowledged worker handle and size during registration and proxies that bounded open
to the same worker. Registration mutations are serialized, close retains indexes until the access
handle is released, and protocol timeout or worker failure poisons future requests. It does not
modify Turso's Rust/WASM engine binary or create a helper database.

Rebuild with:

```sh
npm ci
npm test
npm run build
shasum -a 256 ../../web/turso_upstream.js
```

The checked-in lockfile pins `@tursodatabase/database-common`,
`@tursodatabase/database-wasm`, and `@tursodatabase/database-wasm-common` to `0.8.0-pre.10`, with
Vite `7.3.6`. The recorded build used Node `26.8.2` and npm `11.19.1`.

The original `database-wasm-common` distribution has SHA-256
`b0ca552513511aa21c28b672a44f2e8f452bf8731fa030259420b32a4447dc00`. Turso's MIT license is
installed with the generated bundle as `web/UPSTREAM_LICENSE.md`.
