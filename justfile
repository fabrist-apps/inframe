# Regenerate every derived Dart source file in the workspace.
generate: build-runner

# Run build_runner in each package that owns generated source.
build-runner: bindings
    cd packages/conflux/conflux && dart run build_runner build
    cd packages/chronicler/chronicler && dart run build_runner build
    cd packages/database/rivet && dart run build_runner build
    cd packages/database/rivet/test/fixtures/schema_package && dart run build_runner build
    cd packages/database/rivet/test/fixtures/app_package && dart run build_runner build
    cd packages/database/voxel && dart run build_runner build
    dart format .

# Regenerate native bindings produced by ffigen.
bindings:
    cd packages/database/turso && dart run ffigen --config ffigen.yaml
