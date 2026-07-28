<div align="center">

<img src="docs/media/logo-256.png" width="160" alt="Dev Island app icon">

# Dev Island

**A live status bar for the AI agents working in the background.**

<p>
  <a href="https://devisland.app"><img alt="Website" src="https://img.shields.io/badge/website-devisland.app-7DF0B0?style=for-the-badge"></a>
  <a href="https://github.com/sheepxux/Dev-Island/releases/latest"><img alt="Latest release" src="https://img.shields.io/github/v/release/sheepxux/Dev-Island?style=for-the-badge&label=download&color=8B5CF6"></a>
  <a href="https://github.com/sheepxux/Dev-Island/stargazers"><img alt="GitHub stars" src="https://img.shields.io/github/stars/sheepxux/Dev-Island?style=for-the-badge&logo=github&color=FACC15"></a>
  <img alt="macOS 14+" src="https://img.shields.io/badge/macOS-14%2B-111111?style=for-the-badge&logo=apple">
  <a href="LICENSE"><img alt="MIT License" src="https://img.shields.io/badge/license-MIT-34D399?style=for-the-badge"></a>
</p>

<img src="docs/media/dev-island-hero.svg" alt="Dev Island macOS preview" width="900">

</div>

## Why this exists

AI agents are useful because they keep working after you switch tabs. That's also
why they're easy to forget about — by the time the result is ready, you've
already moved on three times.

Dev Island gives that background work a small, persistent home on macOS.
A capsule sits in your menu bar (or curls around the notch on a 14"/16" MacBook
Pro), showing how many tasks are in flight and what state they're in. Click it
and the full task list slides down. A task starts asking for input? The bar
turns yellow. Something failed? Red. Everything done? Green. Silence? Gray.

It's a Dynamic Island for the agentic stuff happening on the other side of the
internet.

## What it looks like

<p align="center">
  <img src="docs/media/status-priority-demo.gif" alt="Dev Island state transitions" width="640">
</p>

The bar carries five states, ordered by priority — the highest one wins:

| Color | State | Meaning |
| :---: | --- | --- |
| 🟡 | **Waiting** | An agent paused and is asking for input |
| 🔴 | **Failed** | At least one task errored out and you should look |
| 🟢 | **Running** | Work is in flight |
| 🟦 | **Completed** | Done, nothing to do |
| ⚪ | **Idle** | No tasks, or sync is paused |

Hover the bar and it widens to show the current task title. Click it and the
panel expands into a scrollable task list with one-click open-in-browser. Click
outside or press <kbd>Esc</kbd> to collapse it back.

## Install

### From the website ← *recommended*

Go to **[devisland.app](https://devisland.app)** → click **Download for Mac** →
unzip → drag **Dev Island.app** to **Applications**.

The app is signed with a Developer ID and notarized by Apple, so it opens with
zero Gatekeeper warnings on first launch.

### Homebrew Cask

*Coming soon.* Once the public tap is published:

```sh
brew tap sheepxux/dev-island
brew install --cask dev-island
```

The Cask will declare `depends_on cask: "cloudflared"` so realtime webhook
updates work out of the box.

### From source

Requires macOS 14+ and a Swift 6 toolchain (Xcode 16 ships one):

```sh
git clone https://github.com/sheepxux/Dev-Island.git
cd Dev-Island
swift run IslandApp           # dev launch
./scripts/build-app.sh        # produces build/Dev Island.app (ad-hoc signed)
```

## First-run setup

1. Click the gear icon in the expanded panel (or pick *Settings* from the menu)
2. Paste your Manus API key (`sk-…`) and hit **Connect**
3. The status dot turns green. That's it — your live tasks start syncing.

Keys are stored in the macOS Keychain. Disconnect at any time from the same
settings pane. Optional **Launch at Login** hooks up via `SMAppService`, no
LaunchAgent files dropped on disk.

## How sync works

Dev Island prefers a **realtime webhook** path. When `cloudflared` is on your
`$PATH` (or installed via the Homebrew Cask), the app spins up a tunnel,
registers a webhook with Manus, and receives task transitions as they happen.

If `cloudflared` is missing, broken, or your network blocks the tunnel, the app
falls back to **60-second polling** automatically. You don't lose any state, you
just see updates within a minute instead of a few hundred milliseconds. The app
prints a small "degraded" reason in the status dot tooltip so you know which
mode you're in.

## Sources

| Source | Status |
| --- | --- |
| Manus | ✅ Available |
| Claude Code | 🚧 Next up (local hooks, no tunnel needed) |
| Codex CLI | 🚧 Next up (local notify hook) |
| Cursor | 📋 Planned |

The connector layer is intentionally pluggable — `IslandCore` exposes an
`AgentConnector` protocol, and adding a new source is a matter of writing
`fetchTasks()` + (optionally) a webhook handler that emits `WebhookPayload`.

## Architecture

SPM-native, four targets, single shared contract:

| Target | Role |
| --- | --- |
| `IslandApp` | Tiny `@main` shim + `AppDelegate` |
| `IslandAppLib` | SwiftUI views, windows, animations, settings, notifications |
| `IslandCore` | Connectors, persistence (SQLite + Keychain), webhook server, tunnel |
| `IslandCoreCLI` | Headless integration test harness |

UI ↔ core boundary is the public `TaskStore` surface. Both sides ship in the
same repo because the shared contract evolves together; cross-side breaking
changes go through [`docs/INTERFACE_CONTRACT.md`](docs/INTERFACE_CONTRACT.md).

```
┌────────────────────────────┐    ┌─────────────────────────────────┐
│        IslandAppLib        │    │           IslandCore            │
│                            │    │                                 │
│   IslandRootView   ────────┼───→│   TaskStore.shared              │
│   NotchPanelView           │    │     ├─ ManusAPIClient           │
│   SettingsView             │    │     ├─ TunnelManager (cf'ed)    │
│   StatusDot                │    │     ├─ PollingFallback (60s)    │
│                            │    │     ├─ WebhookServer            │
└────────────────────────────┘    │     └─ SQLiteStore + Keychain   │
                                  └─────────────────────────────────┘
```

## Status

| Area | State |
| --- | --- |
| macOS island UI (notched + non-notched) | ✅ Shipping |
| Manus task sync (polling, webhook fallback path) | ✅ Shipping |
| Settings + Launch at Login + banner notifications | ✅ Shipping |
| Signed + notarized public release | ✅ v0.1.1 on [Releases](https://github.com/sheepxux/Dev-Island/releases) |
| Homebrew Cask tap | 🚧 Draft in `dist/homebrew-island/` |
| Claude Code / Codex connectors | 📋 Next up |

## Contributing

Ideas, bug reports, and connector PRs welcome. If you're adding a new agent
source, the cleanest entry point is `IslandCore/Sources/IslandCore/Connectors/`
— start by reading `ManusConnector.swift` and the surrounding webhook +
polling glue.

For interface-contract changes (anything touching `TaskStore`'s public API),
see [`docs/INTERFACE_CONTRACT.md`](docs/INTERFACE_CONTRACT.md) first.

## License

[MIT](LICENSE). Use it, fork it, ship your own version with a new icon, send
weird agent task notifications to your friends. Just keep the copyright notice
intact.

---

<div align="center">
  <sub>
    Built with SwiftUI, Hummingbird, SQLite.swift, and a healthy distrust
    of ⌘-Tab.<br>
    <a href="https://devisland.app">devisland.app</a> ·
    <a href="https://github.com/sheepxux/Dev-Island/issues">Issues</a> ·
    <a href="https://github.com/sheepxux/Dev-Island/releases">Releases</a>
  </sub>
</div>
