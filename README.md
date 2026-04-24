# DevLand

macOS notch island app that surfaces agent tasks (Manus, future: Claude Code, Cursor) on the menu bar / notch area.

## Build

```bash
swift build
```

Requires macOS 14+, Swift 5.9+.

## Architecture

Two-module Swift package at the repo root:

- `IslandApp/` — SwiftUI UI layer (views, windows, animations, notifications, settings)
- `IslandCore/` — data layer (TaskStore, connectors, persistence, Keychain)

The only coupling between the two is the `TaskStore` public API, documented in [`docs/INTERFACE_CONTRACT.md`](docs/INTERFACE_CONTRACT.md). Breaking changes to that API require a cross-owner PR.

## Ownership

- `IslandApp/` — owned by C
- `IslandCore/` — owned by S (except `TaskStore.swift` public surface, which is shared contract)

See `docs/INTERFACE_CONTRACT.md` for the change-request process.
