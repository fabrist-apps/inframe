# Native artifacts

These libraries are built from unchanged upstream Turso source. Package users load the prebuilt
artifact and do not need Rust.

## macOS ARM64

| Property | Value |
| --- | --- |
| Upstream tag | `v0.8.0-pre.10` |
| Upstream commit | `342dfbe267ebdb9141c434c499ce31e10bb46f27` |
| Rust toolchain | `rustc 1.98.0 (88d9e12ae 2026-08-18)` |
| Cargo features | SDK defaults (`encryption`, `pure-rust-crypto`) plus `fts` |
| Minimum macOS recorded by Mach-O | 11.0 |
| Artifact | `macos/arm64/libturso_sdk_kit.dylib` |
| SHA-256 after stripping and setting the install name | `3fbb42e1e77acb7869615a5e5d5f18e5a13bbb167be22630f23d97b9e17a1c25` |

Build from the pinned source:

```sh
git clone --branch v0.8.0-pre.10 --depth 1 https://github.com/tursodatabase/turso.git
cd turso
cargo build --locked -p turso_sdk_kit --profile release-official --features fts
strip -x target/release-official/libturso_sdk_kit.dylib
install_name_tool -id @rpath/libturso_sdk_kit.dylib \
  target/release-official/libturso_sdk_kit.dylib
```
