import Foundation

/// Dependency-free OpenCode global plugin pinned to OpenCode 1.18.23 / plugin
/// interface commit 13c27598d35f6f91fa4763a0b61a220ab7fcb263.
///
/// The plugin filters vendor events before loopback transit. Prompts, titles,
/// messages, tool arguments, permission metadata and raw errors never enter
/// the envelope. Delivery is fire-and-forget with a one-second abort, so a
/// stopped Dev Island cannot delay or fail an OpenCode turn.
enum OpenCodePlugin {
    static let schemaVersion = OpenCodeEvent.currentSchemaVersion
    static let managedMarker = "Dev Island managed local plugin: opencode"
    static let pinnedVersion = "1.18.23"
    static let pinnedCommit = "13c27598d35f6f91fa4763a0b61a220ab7fcb263"

    static func render(port: Int) -> Data {
        precondition((1...65_535).contains(port), "OpenCode plugin port is invalid")
        return Data(
            """
            // \(managedMarker) v2
            // OpenCode \(pinnedVersion), interface \(pinnedCommit)
            const endpoint = "http://127.0.0.1:\(port)/hooks/opencode"
            const authorizationPath = process.env.HOME
              ? process.env.HOME + "/\(LocalHookAuthorizationStore.relativeHeaderFilePath)"
              : undefined

            const authorization = async () => {
              if (!authorizationPath) return undefined
              try {
                const file = Bun.file(authorizationPath)
                if (file.size < 1 || file.size > \(LocalHookAuthorizationStore.maximumHeaderFileBytes)) return undefined
                let text = await file.slice(0, \(LocalHookAuthorizationStore.maximumHeaderFileBytes + 1)).text()
                if (new TextEncoder().encode(text).length > \(LocalHookAuthorizationStore.maximumHeaderFileBytes)) return undefined
                if (text.endsWith("\\n")) text = text.slice(0, -1)
                if (text.includes("\\n") || text.includes("\\r")) return undefined
                const prefix = "\(LocalHookAuthorization.headerName): \(LocalHookAuthorization.versionPrefix)"
                if (!text.startsWith(prefix)) return undefined
                const value = text.slice("\(LocalHookAuthorization.headerName): ".length)
                if (value.length !== \(LocalHookAuthorization.encodedValueByteCount)) return undefined
                const suffix = value.slice("\(LocalHookAuthorization.versionPrefix)".length)
                if (![...suffix].every((character) => "0123456789abcdef".includes(character))) return undefined
                return value
              } catch {
                return undefined
              }
            }

            const headers = async () => {
              const credential = await authorization()
              if (!credential) return undefined
              const result = {
                "Content-Type": "application/json",
                "\(LocalHooksInstaller.requestHeaderName)": "\(LocalHooksInstaller.requestHeaderValue)",
                "\(LocalHookAuthorization.headerName)": credential,
              }
              const add = (name, value) => {
                if (typeof value === "string" && value.length > 0 && value.length <= 512) result[name] = value
              }
              add("X-Dev-Island-Terminal-Bundle", process.env.__CFBundleIdentifier)
              add("X-Dev-Island-Terminal-Program", process.env.TERM_PROGRAM)
              add("X-Dev-Island-Tmux", process.env.TMUX)
              add("X-Dev-Island-Tmux-Pane", process.env.TMUX_PANE)
              return result
            }

            const emit = async (event, sessionID, cwd, status) => {
              if (typeof sessionID !== "string" || sessionID.trim().length === 0) return
              const requestHeaders = await headers()
              if (!requestHeaders) return
              const body = { schema_version: 1, event, session_id: sessionID }
              if (typeof cwd === "string" && cwd.trim().length > 0) body.cwd = cwd
              if (typeof status === "string") body.status = status

              const controller = new AbortController()
              const timeout = setTimeout(() => controller.abort(), 1000)
              void fetch(endpoint, {
                method: "POST",
                headers: requestHeaders,
                body: JSON.stringify(body),
                signal: controller.signal,
              }).catch(() => {}).finally(() => clearTimeout(timeout))
            }

            export const DevIslandPlugin = async ({ directory }) => ({
              event: async ({ event }) => {
                switch (event.type) {
                  case "session.created":
                    await emit("session.created", event.properties?.info?.id, event.properties?.info?.directory ?? directory)
                    break
                  case "session.status": {
                    const status = event.properties?.status?.type
                    if (status === "busy" || status === "idle" || status === "retry") {
                      await emit("session.status", event.properties?.sessionID, directory, status)
                    }
                    break
                  }
                  case "session.idle":
                    await emit("session.idle", event.properties?.sessionID, directory)
                    break
                  case "session.deleted":
                    await emit("session.deleted", event.properties?.info?.id, event.properties?.info?.directory ?? directory)
                    break
                  case "session.error":
                    await emit("session.error", event.properties?.sessionID, directory)
                    break
                  case "permission.updated":
                    await emit("permission.updated", event.properties?.sessionID, directory)
                    break
                  case "permission.replied":
                    await emit("permission.replied", event.properties?.sessionID, directory)
                    break
                }
              },
            })
            """.utf8
        )
    }
}
