import Foundation

/// Vendor deep links that open the exact session inside the host app the
/// resolver already chose (contract J2, v7.1.0): app-level activation brings
/// the app forward, a deep link also navigates it to the conversation.
///
/// Every URL is assembled from identifiers Dev Island already holds and has
/// validated (a UUID-shaped session id, a directory the destination policy
/// accepted, a Claude Desktop session id read from the app's own index).
/// Nothing vendor-authored — task URLs, titles, payload text — reaches
/// Launch Services, and an unknown source/host pair yields no link, so the
/// caller falls back to plain activation.
enum SessionDeepLinkPolicy {
    static let codexDesktopBundleIdentifier = "com.openai.codex"
    static let claudeDesktopBundleIdentifier = "com.anthropic.claudefordesktop"
    static let cursorBundleIdentifier = "com.todesktop.230313mzl4w4u92"

    /// The link to open `task`'s session in `hostBundleIdentifier`, or `nil`
    /// when that app has no reviewed deep link for this source.
    ///
    /// - Codex Desktop (the ChatGPT app): `codex://threads/<thread id>`; the
    ///   session log's rollout id is the thread id. Internal to the app and
    ///   undocumented, so a later release may ignore it: the fallback is the
    ///   app-level activation the caller performs anyway.
    /// - Claude Desktop: `claude://claude.ai/epitaxy/<app session id>`, the
    ///   `link` the app itself hands out for a Code session, found through
    ///   the app's per-session index keyed by the CLI session id.
    /// - Cursor: `cursor://file/<project directory>`, which raises the
    ///   workspace window for that folder (VS Code's `file` route).
    static func deepLink(
        for task: AgentTask,
        hostBundleIdentifier: String,
        claudeSessionIndex: ClaudeDesktopSessionIndex = .standard,
        fileManager: FileManager = .default
    ) -> URL? {
        switch (task.source, hostBundleIdentifier) {
        case ("codex", codexDesktopBundleIdentifier):
            guard let thread = validatedUUIDIdentifier(task.id) else { return nil }
            return URL(string: "codex://threads/\(thread)")

        case ("claude-code", claudeDesktopBundleIdentifier):
            guard let cliSession = validatedUUIDIdentifier(task.id),
                  let appSession = claudeSessionIndex.appSessionIdentifier(forCLISessionId: cliSession)
            else { return nil }
            return URL(string: "claude://claude.ai/epitaxy/\(appSession)")

        case ("cursor", cursorBundleIdentifier):
            guard let directory = TaskDestinationPolicy.destination(for: task, fileManager: fileManager),
                  directory.isFileURL else { return nil }
            var components = URLComponents()
            components.scheme = "cursor"
            components.host = "file"
            components.path = directory.path
            return components.url

        default:
            return nil
        }
    }

    /// An 8-4-4-4-12 hex identifier (Codex thread ids, Claude Code session
    /// ids), normalized to lowercase. Anything else — paths, query strings,
    /// vendor text — is rejected, so it can never shape a URL.
    static func validatedUUIDIdentifier(_ raw: String) -> String? {
        guard UUID(uuidString: raw) != nil else { return nil }
        return raw.lowercased()
    }
}

/// Claude Desktop keeps one JSON file per Code session under its Application
/// Support directory, carrying the app's own session id (the one its deep
/// link takes) next to the CLI session id the hooks report. Dev Island reads
/// only those two keys, from a bounded number of bounded files, and keeps
/// nothing else.
struct ClaudeDesktopSessionIndex: Sendable {
    static let maximumFiles = 512
    static let maximumFileBytes = 256 * 1_024
    static let maximumDepth = 4

    static let standard = ClaudeDesktopSessionIndex(
        directory: FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Claude/claude-code-sessions", isDirectory: true)
    )

    let directory: URL

    private struct Entry: Decodable {
        let sessionId: String
        let cliSessionId: String
    }

    /// The app session id whose file names `cliSessionId`, validated to the
    /// `local_<uuid>` / `<uuid>` shapes the app uses.
    func appSessionIdentifier(forCLISessionId cliSessionId: String) -> String? {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return nil }

        var visited = 0
        let decoder = JSONDecoder()
        for case let url as URL in enumerator {
            if enumerator.level > Self.maximumDepth {
                enumerator.skipDescendants()
                continue
            }
            guard url.pathExtension == "json" else { continue }
            visited += 1
            if visited > Self.maximumFiles { return nil }
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true,
                  let size = values.fileSize, size <= Self.maximumFileBytes,
                  let data = try? Data(contentsOf: url),
                  let entry = try? decoder.decode(Entry.self, from: data),
                  entry.cliSessionId.lowercased() == cliSessionId.lowercased(),
                  let appSession = Self.validatedAppSessionIdentifier(entry.sessionId)
            else { continue }
            return appSession
        }
        return nil
    }

    static func validatedAppSessionIdentifier(_ raw: String) -> String? {
        let body = raw.hasPrefix("local_") ? String(raw.dropFirst("local_".count)) : raw
        guard UUID(uuidString: body) != nil else { return nil }
        return raw.hasPrefix("local_") ? "local_" + body.lowercased() : body.lowercased()
    }
}
