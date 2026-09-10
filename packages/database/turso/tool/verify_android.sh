#!/usr/bin/env bash

set -euo pipefail

app_directory="$RUNNER_TEMP/turso_mobile"
package_directory="$GITHUB_WORKSPACE/packages/database/turso"

flutter create --empty --platforms=android "$app_directory"
cd "$app_directory"
flutter pub add turso --path "$package_directory"
flutter pub add 'dev:integration_test@{"sdk":"flutter"}'
mkdir -p integration_test
cp "$package_directory/tool/flutter_native_runtime_test.dart.template" \
  integration_test/runtime_test.dart

flutter build apk --debug --target-platform android-arm64
arm64_apk=build/app/outputs/flutter-apk/app-debug.apk
unzip -l "$arm64_apk" | grep 'lib/arm64-v8a/libturso_sdk_kit.so'
zipalign="$(find "$ANDROID_HOME/build-tools" -name zipalign -type f | sort -V | tail -1)"
"$zipalign" -c -P 16 -v 4 "$arm64_apk"
flutter clean

flutter test integration_test/runtime_test.dart -d emulator-5554
x64_apk=build/app/outputs/flutter-apk/app-debug.apk
unzip -l "$x64_apk" | grep 'lib/x86_64/libturso_sdk_kit.so'
"$zipalign" -c -P 16 -v 4 "$x64_apk"
