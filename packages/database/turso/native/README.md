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

## Android

| Property | Value |
| --- | --- |
| Upstream tag | `v0.8.0-pre.10` |
| Upstream commit | `342dfbe267ebdb9141c434c499ce31e10bb46f27` |
| Rust toolchain | `rustc 1.88.0 (6b00bc388 2025-06-23)` |
| Android NDK | `28.2.13676358` |
| Cargo features | SDK defaults (`encryption`, `pure-rust-crypto`) plus `fts` |
| Minimum Android API | 24 |
| ARM64 artifact | `android/arm64/libturso_sdk_kit.so` |
| ARM64 SHA-256 | `37ca19e7752429b1df92e5370515689c5cdeb861dfc39954abd5e29d911bcbba` |
| x64 artifact | `android/x64/libturso_sdk_kit.so` |
| x64 SHA-256 | `be8eaf44e2072424512c920e981696a85dd078b8f1a7204f329a3802b1bed41a` |

Both artifacts are stripped ELF shared objects. Their load segments use 16 KiB alignment for
Android devices that use 16 KiB memory pages. They were cross-compiled on Ubuntu with the matching
NDK API 24 Clang linkers and the 16 KiB maximum-page-size flags in upstream's Cargo configuration:

```sh
cargo build --locked -p turso_sdk_kit --profile release-official --features fts \
  --target aarch64-linux-android
cargo build --locked -p turso_sdk_kit --profile release-official --features fts \
  --target x86_64-linux-android
```

Android ARM32 is not packaged in v1.

## iOS

| Property | Value |
| --- | --- |
| Upstream tag | `v0.8.0-pre.10` |
| Upstream commit | `342dfbe267ebdb9141c434c499ce31e10bb46f27` |
| Rust toolchain | `rustc 1.98.0 (88d9e12ae 2026-08-18)` |
| Cargo features | SDK defaults (`encryption`, `pure-rust-crypto`) plus `fts` |
| Supported iOS versions | 15 or newer |
| Device ARM64 artifact | `ios/device/arm64/libturso_sdk_kit.dylib` |
| Device ARM64 SHA-256 | `bafa6b5e291b3ee4b4a94a05a1e0a9e704cd19ca4a30f1afae6d52c6acbbded2` |
| Simulator ARM64 artifact | `ios/simulator/arm64/libturso_sdk_kit.dylib` |
| Simulator ARM64 SHA-256 | `1f63adf5b46b706c2845510faa544c3e980b391cd37033f07e2b122586b349ed` |
| Simulator x64 artifact | `ios/simulator/x64/libturso_sdk_kit.dylib` |
| Simulator x64 SHA-256 | `31b78f2cbd83c49f9b393c58d120dfe9ec14d8e67774d56c3898e677174f3910` |

The Mach-O artifacts were built with Xcode 26.6 and the iOS 26.5 SDK, stripped, and assigned the
install name `@rpath/libturso_sdk_kit.dylib`. The recorded deployment targets are 13.0 for the ARM64
device and x64 simulator libraries and 14.0 for the ARM64 simulator library. Flutter's supported iOS
floor is 15, which is the package's supported floor.

```sh
cargo build --locked -p turso_sdk_kit --profile release-official --features fts \
  --target aarch64-apple-ios
cargo build --locked -p turso_sdk_kit --profile release-official --features fts \
  --target aarch64-apple-ios-sim
cargo build --locked -p turso_sdk_kit --profile release-official --features fts \
  --target x86_64-apple-ios
```

All packaged libraries use the checked-in `include/turso.h` from the same upstream commit.
The package build hook selects the library by target OS and CPU and fails the application build when
a supported target's packaged file is missing. These SDK libraries are stored in this package; no
Rust toolchain or CLI executable is required by consumers.
