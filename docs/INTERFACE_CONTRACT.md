# Interface Contract

> Owners: shared (C + S). Changes require PR review from both.
> Contract version: **v1**
> Last updated: 2026-04-24

This document is the only coupling between the two Claude Code instances:

- **C** owns `IslandApp/` (UI layer)
- **S** owns `IslandCore/` (data layer) except the public surface defined below

C imports `IslandCore` and consumes only what is declared here. S implements
this surface. Anything else in `IslandCore/` is free to evolve without notice.

---

## 1. Module boundary

| Layer        | Path                                        | Owner |
| ------------ | ------------------------------------------- | ----- |
| UI           | `IslandApp/`                                | C     |
| Data / IO    | `IslandCore/Sources/IslandCore/` (private)  | S     |
| **Contract** | `IslandCore/Sources/IslandCore/TaskStore.swift` (public symbols) + `Models/*.swift` | shared |

C MUST NOT import any IslandCore symbol outside the contract.
S MUST NOT widen or break the contract without a CR.

---

## 2. Change request (CR)

To modify any public symbol below:

1. Open a PR that updates **this doc + the Swift source together**.
2. Tag both owners as reviewers.
3. Merge only after both approve.
4. Bump the contract version at the top of this file.

In-place additions (new public methods, new optional fields with defaults) are
non-breaking and can land via the same CR flow but without a version bump.

---

## 3. Public surface

### 3.1 `TaskStore`

```swift
@Observable
public final class TaskStore {
    public static let shared: TaskStore

    public private(set) var tasks: [AgentTask]
    public private(set) var connectionStatus: ConnectionStatus
    public private(set) var apiKeyStatus: APIKeyStatus

    public func configureAPIKey(_ key: String) async throws
    public func clearAPIKey()
    public func openTaskInBrowser(id: String)
    public func stopTask(id: String) async throws
}
```

### 3.2 Models

```swift
public struct AgentTask: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let source: String          // "manus" (future: "claude-code", "cursor")
    public var title: String
    public var status: TaskStatus
    public var currentPhase: String?
    public let createdAt: Date
    public var updatedAt: Date
    public let taskURL: String
    public var waitingMessage: String?
}

public enum TaskStatus: String, Codable, Sendable {
    case running, waiting, completed, failed
}

public enum ConnectionStatus: Equatable, Sendable {
    case connected
    case disconnected
    case reconnecting
    case degraded(reason: String)
}

public enum APIKeyStatus: Equatable, Sendable {
    case notConfigured
    case valid
    case invalid
}
```

---

## 4. Behavior guarantees

- **Threading**: All `@Observable` mutations happen on `MainActor`. SwiftUI
  views consuming `TaskStore.shared` re-render automatically.
- **`openTaskInBrowser`**: fire-and-forget. Must not block or throw. If the
  task or URL is invalid, fail silently (log internally).
- **`configureAPIKey`**: validates the key against Manus before persisting.
  - On success: `apiKeyStatus = .valid`, key written to Keychain.
  - On invalid key: `apiKeyStatus = .invalid`, throws.
  - On network failure: state unchanged, throws.
- **`stopTask`**: throws if the task is unknown or cannot be cancelled.
  Must update `tasks` to reflect the new status on success.
- **`connectionStatus`**: reflects long-poll / webhook health. C uses it to
  show a degraded state on the bar (gray) when not `.connected`.

---

## 5. Status priority (UI)

When multiple tasks coexist, the Notch Bar color is driven by the highest
priority status present:

```
Waiting > Failed > Running > Completed > Idle (tasks empty)
```

This rule is owned by C and may evolve without a CR — S does not need to
expose anything new.

---

## 6. Stub policy

Until S replaces the stubs in `TaskStore.swift`:

- All async/throwing methods throw a `StubError.notImplemented`.
- `tasks` stays empty unless populated via `TaskStore.mock(...)` (DEBUG only).
- The `#if DEBUG extension TaskStore { static func mock(...) }` block is
  C-owned for Previews + Debug Sandbox. **S, please preserve it** when
  swapping the production implementation in.
