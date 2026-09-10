import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';

void main(List<String> arguments) async {
  await build(arguments, (input, output) async {
    if (!input.config.buildCodeAssets) return;

    final code = input.config.code;
    final artifact = switch ((code.targetOS, code.targetArchitecture)) {
      (OS.macOS, Architecture.arm64) => 'native/macos/arm64/libturso_sdk_kit.dylib',
      (OS.linux, Architecture.x64) => 'native/linux/x64/libturso_sdk_kit.so',
      (OS.windows, Architecture.x64) => 'native/windows/x64/turso_sdk_kit.dll',
      _ => null,
    };
    if (artifact == null) return;

    output.assets.code.add(
      CodeAsset(
        package: input.packageName,
        name: 'src/native/turso_bindings_generated.dart',
        linkMode: DynamicLoadingBundled(),
        file: input.packageRoot.resolve(artifact),
      ),
    );
  });
}
