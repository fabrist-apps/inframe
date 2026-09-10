# Inframe OS

Inframe OS is a visual full-stack application builder. Builders compose Flutter interfaces and define frontend and backend logic through node-based flows.

## Product vocabulary

Use these terms consistently:

- **Builder:** A person who creates and manages Apps.
- **App:** The frontend, backend logic, and data created by a Builder.
- **App Client:** An App's Flutter frontend.
- **App Server:** An App's Dart backend, deployed in Kubernetes.
- **End User:** A person who uses an App.

Do not use "Builder App"; use "App".

## Product source and decision status

Read the `Inframe OS` Obsidian note before making product-wide or architectural decisions:

```sh
obsidian read vault=Inframe file="Inframe OS"
```

The note describes the target product and is currently a concept, not a description of implemented behavior. Treat choices marked proposed or provisional as open decisions. Code, implementation notes, and accepted decisions define current contracts.

When implementation would change an agreed product contract, report the conflict and the required note update. Do not edit the vault unless the task includes documentation changes.

## Repository guidance

This repository is a Dart pub workspace. Run workspace commands from the repository root:

```sh
dart pub get
dart format --output=none --set-exit-if-changed .
dart analyze
```

Run package tests by path so integration suites keep their explicit environment setup:

```sh
dart test packages/json_patch/test --chain-stack-traces
dart test packages/database/clickhouse/test --exclude-tags integration --chain-stack-traces
```

The ClickHouse integration suite and its disposable service setup are defined in
`.github/workflows/dart.yaml`. Do not point it at a live database.
