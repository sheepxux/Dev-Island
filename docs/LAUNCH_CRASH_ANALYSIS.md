# Historical Launch Crash Analysis

This is a development-time analysis of macOS reports retained locally on the
test Mac. Dev Island does not read these reports at runtime, and no raw report
is copied into the repository, diagnostics export, QA artifact, or evidence
bundle.

## Confirmed failure clusters

### v0.3.0: missing Sparkle at launch

One retained report from 2026-08-26 terminated in `dyld` before application
code ran:

```text
Namespace: DYLD
Indicator: Library missing
Dependency: @rpath/Sparkle.framework/Versions/B/Sparkle
```

The affected bundle did not make the embedded framework reachable from the
executable. Current packaging now:

- copies `Sparkle.framework` to `Contents/Frameworks`;
- adds `@executable_path/../Frameworks` to the executable's runtime search
  paths;
- verifies the executable still links `@rpath/Sparkle.framework`;
- verifies both the app and Sparkle are `x86_64 arm64`; and
- signs and validates the complete nested bundle.

The build script now validates the full dependency closure of every Mach-O,
framework, XPC service, helper and bundle symlink before signing, rather than
special-casing Sparkle. Its eight negative fixtures cover missing, thin,
external, escaping and non-Mach-O dependencies. See
`APP_BUNDLE_DEPENDENCY_CLOSURE.md`. The current Universal QA app passes
`codesign --deep --strict` and survives a real Launch Services cold start.

### v0.2.2: sleeping task teardown in the root animation view

Eleven retained reports from 2026-08-19 and 2026-08-22 share the same triggered
stack:

```text
SIGABRT
swift_Concurrency_fatalError
swift_task_dealloc
Task.sleep
IslandRootView.synchronizePanelContent(with:)
```

The fault occurred while the root island view delayed panel-content reveal
inside a sleeping Swift task. That path now uses a main-dispatch callback plus
a UUID invalidation token. Stale callbacks become inert during rapid
open/close/open transitions and no Swift task needs to survive the animation.

A later completion-expiry feature briefly introduced another `Task.sleep` in
the same root view. It now uses the same main-queue token pattern. CI rejects
any future `Task.sleep` occurrence in `IslandRootView.swift` so this failure
class cannot silently return during motion work.

## Current protection layers

1. Artifact-boundary checks prevent any missing, unreachable, thin, external,
   non-Mach-O, or bundle-escaping dynamic dependency.
2. Root island timing uses cancellable main-queue callbacks, not sleeping Swift
   tasks.
3. Launch Health v2 distinguishes a ready process from a startup that ended
   inside its two-second stability window, with a bounded count and no crash
   claim.
4. The full XCTest suite and security aggregate run before a QA app is accepted.
5. Developer ID signing, notarization, and an installed old-to-new update remain
   mandatory external release gates.

## Privacy boundary

This diagnosis used only local, user-owned development reports. The shipping
app continues to store only its four bounded launch-health preference values.
It does not read `DiagnosticReports`, attach a crash SDK, log stacks, or upload
crash content.
