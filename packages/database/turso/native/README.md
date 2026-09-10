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

## Linux x64

| Property | Value |
| --- | --- |
| Upstream tag | `v0.8.0-pre.10` |
| Upstream commit | `342dfbe267ebdb9141c434c499ce31e10bb46f27` |
| Rust toolchain | `rustc 1.88.0 (6b00bc388 2025-06-23)` |
| Cargo features | SDK defaults (`encryption`, `pure-rust-crypto`) plus `fts` |
| Artifact | `linux/x64/libturso_sdk_kit.so` |
| Format | Stripped ELF x86-64 shared object |
| Required glibc symbol floor | 2.35 |
| SHA-256 | `c61e84f96d41c2b58f7f016e3d5496b501581719092fcf0d942699e725736d47` |

The packaged artifact supports Ubuntu 22.04 LTS or newer and Debian 12 or newer on x64. Linux ARM64
is not packaged in v1. It was built on GitHub's native Ubuntu runner with:

```sh
cargo build --locked -p turso_sdk_kit --profile release-official --features fts
strip --strip-unneeded target/release-official/libturso_sdk_kit.so
```

## Windows x64

| Property | Value |
| --- | --- |
| Upstream tag | `v0.8.0-pre.10` |
| Upstream commit | `342dfbe267ebdb9141c434c499ce31e10bb46f27` |
| Rust toolchain | `rustc 1.88.0 (6b00bc388 2025-06-23)` |
| Cargo features | SDK defaults (`encryption`, `pure-rust-crypto`) plus `fts` |
| Artifact | `windows/x64/turso_sdk_kit.dll` |
| Format | PE32+ x86-64 DLL |
| Supported Windows versions | Windows 10 and 11 |
| SHA-256 | `d98951e2cc584ac98a2ada9f839a5901267c6fc0ee23eceed27b22393e51a60d` |

Windows ARM64 is not packaged in v1. The DLL was built on GitHub's native Windows runner with:

```powershell
cargo build --locked -p turso_sdk_kit --profile release-official --features fts
```

All three desktop libraries use the checked-in `include/turso.h` from the same upstream commit.
The package build hook selects the library by target OS and CPU and fails the application build when
a supported target's packaged file is missing. These SDK libraries are stored in this package; no
Rust toolchain or CLI executable is required by consumers.
