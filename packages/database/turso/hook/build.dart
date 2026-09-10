import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';

void main(List<String> arguments) async {
  await build(arguments, (input, output) async {
    if (!input.config.buildCodeAssets) return;

    final code = input.config.code;
    final artifact = switch ((code.targetOS, code.targetArchitecture)) {
      (OS.macOS, Architecture.arm64) => 'native/macos/arm64/libturso_sdk_kit.dylib',
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
