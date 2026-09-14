# Verification record

This file records the environments and evidence behind the package support claims. GitHub Actions
verifies the enabled matrix when this package changes. Artifact provenance and hashes are recorded
separately in [native/README.md](native/README.md) and [web/README.md](web/README.md).

## Runtime matrix

The 2026-09-10 verification used Dart 3.13.3 and Flutter stable. GitHub-hosted runner image releases
are printed in each job log so a later image update produces a new, attributable record.

| Runtime | Recorded environment | Executed evidence |
| --- | --- | --- |
| Android | Ubuntu 24.04 runner; API 35 x64 Pixel 7 Pro emulator | Flutter integration contract on the emulator; ARM64 release APK packaging and 16 KiB ELF/ZIP alignment checks |
| iOS | macOS 26 ARM64 runner; first available iPhone simulator; physical-device release build | Flutter integration contract on the simulator; ARM64 device-framework packaging check |
| macOS | macOS 26 ARM64 runner | Complete native Dart contract using the packaged dylib |
| Linux | Ubuntu 24.04 x64 runner | Complete native Dart contract and a release Flutter application under Xvfb |
| Windows | Blacksmith Windows Server 2025 x64 runner | Temporarily disabled: the native Dart contract passes, but the Server Core image cannot load `OPENGL32.dll`, which prevents the Flutter engine from starting |
| Web | Ubuntu 24.04 for Chrome and Firefox; macOS 26 ARM64 for Safari | Compiled Dart application through Selenium and each browser's native WebDriver |

The recorded stable desktop browsers are:

| Browser | Version | Runner and driver |
| --- | --- | --- |
| Chrome | 144.0.7559.96 | Ubuntu 24.04, headless Chrome through ChromeDriver |
| Firefox | 147.0.1 | Ubuntu 24.04, headless Firefox through GeckoDriver |
| Safari | 26.6.2 (21624.5.1.11.3) | macOS 26 ARM64, actual Safari through the bundled `safaridriver` |

Safari's own WebDriver is used. A generic WebKit engine does not stand in for the Safari check.
Mobile browsers are excluded; Android and iOS use their native Flutter targets.

## Contract trace

| Contract | Evidence |
| --- | --- |
| Native migration-lock exclusion, persistent sidecars, release, and process termination | `test/native_migration_lock_test.dart` on enabled desktop native targets (with the same Windows path ready for the recorded disabled job); independent-handle contention in `tool/flutter_native_runtime_test.dart.template` on Android and iOS |
| Native values, bindings, persistence, memory opening, encryption failures, and lifecycle | `test/native_database_test.dart` on macOS and Linux, with Windows verified before its temporary CI disablement; `tool/flutter_native_runtime_test.dart.template` on Android and iOS |
| Transactions, serialization, submitted-work draining, rollback/commit failure, and retirement | `test/transaction_test.dart` on desktop native targets; the representative transaction and lifecycle cases in the mobile integration suite |
| Native encryption, FTS rollback/reopen, and vector functions | `test/feature_test.dart` on desktop native targets and both ciphers in the mobile integration suite |
| Native ATTACH, caller-controlled foreign keys, detach/re-attach persistence, and file release | `test/native_database_test.dart` on desktop native targets and the attachment scenario in `tool/flutter_native_runtime_test.dart.template` on Android and iOS; Windows Flutter CI remains disabled as recorded above |
| Flutter native artifact loading | Release Flutter application on Linux, Android emulator plus ARM64 APK, and iOS simulator plus device build; Windows is temporarily disabled as described above |
| Browser persistence/reload, storage lock release, failed-open cleanup, and memory opening | `example/web/main.dart` in Chrome, Firefox, and Safari |
| Browser bindings, exact integers, immutable results, transactions, lifecycle, encryption, and vectors | `example/web/main.dart` in Chrome, Firefox, and Safari |
| Browser memory ATTACH/DETACH, explicit foreign-key policy, attached-schema rollback, and encrypted connections | The memory attachment scenarios in `example/web/main.dart` through the installed bridge in Chrome, Firefox, and Safari |
| Browser persistent ATTACH/DETACH, bound-parameter snapshots, encrypted and percent-encoded file URIs, OPFS ownership/contention, injected registration/finalization failures, retirement, explicit re-attach after reload, file release, and memory-main rejection | The persistent attachment scenarios in `example/web/main.dart` through the installed bridge in Chrome, Firefox, and Safari; focused registry boundary tests in `tool/web_bundle/attachment_registry.test.mjs` |
| Web FTS exclusion | The browser suite asserts `fts == false`; native suites execute FTS SQL |
| Artifact selection and integrity | Native asset build-hook tests plus SHA-256 checks in the platform jobs |
| Workspace integration | `dart pub get`, formatter, analyzer, and the repository's existing test jobs |

The browser suite also asserts a secure, cross-origin-isolated page before it accepts a pass. It
therefore exercises the required worker, WASM, OPFS, COOP, and COEP setup rather than running the SQL
contract against a substitute backend.

A local macOS Chromium 152.0.7977.65 run passed the installed-asset persistent attachment, reload,
bound/encrypted URI, multiple-alias, main-file, failed ATTACH/DETACH, cross-worker contention,
close-drain, injected WAL-registration/finalization, retirement, rollback-failure, file-reuse, and
memory-main rejection scenarios on 2026-09-11.

## Representative memory observations

The browser workload inserts 2,000 rows and reads a bounded 25-row result. Chrome records its Dart
page JavaScript heap after the workload. The upstream loader separately reserves 250 MiB of logical
shared WASM memory; this reservation is not the same measurement as JavaScript heap or process
resident memory. A local Chrome 153.0.8010.36 run used 4,686,548 bytes of JavaScript heap out of a
7,340,032-byte allocated JavaScript heap after the workload.

The mobile workload builds an encrypted 2,000-document FTS index for each cipher, rolls back an
additional document, closes and reopens the database, counts the 2,000 matches, and executes a vector
distance query. It records the Flutter process resident set before and after each cipher workload.
The observed byte counts are retained in the CI logs because runner and OS allocation behavior makes
them environment-specific. A local iOS 26.5 simulator run observed 311,066,624 to 324,435,968 bytes
for AEGIS-256 and 325,009,408 to 326,123,520 bytes for AES-256-GCM.

These snapshots demonstrate a representative bounded workload on the supported runtime. They are
not a heap limit, a leak test, or a promise that larger result sets remain bounded. Query results are
fully buffered, so applications must bound queries whose result size can grow.

## V1 boundaries

The package uses the unchanged upstream Turso engine and bindings. Its browser bundle wraps the
pinned JavaScript storage glue to register attachment files, without changing encryption or storage
behavior. Native temporary query files can bypass page encryption with upstream's file-based
temporary storage, and `VACUUM INTO` can produce a plaintext destination. The package does not force
`temp_store`, rewrite SQL, or block exports.

Cloud sync, watch queries, migrations, ORM integration, SQL builders, code generation, public
prepared statements, streaming results, execution timeouts, cancellation, publication, a standalone
repository, and mobile-browser support remain outside v1.
