# Regenerate every derived Dart source file in the workspace.
generate: build-runner

# Run build_runner in each package that owns generated source.
build-runner:
    cd packages/conflux && dart run build_runner build
    cd packages/chronicler/chronicler && dart run build_runner build
    cd packages/artificer/providers/artificer_core && dart run build_runner build
    dart format .
