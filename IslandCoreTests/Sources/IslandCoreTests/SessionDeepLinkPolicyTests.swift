import XCTest
@testable import IslandCore

final class SessionDeepLinkPolicyTests: XCTestCase {
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func task(source: String, id: String, url: String = "file:///tmp/") -> AgentTask {
        AgentTask(
            id: id,
            source: source,
            title: "Session",
            status: .running,
            currentPhase: nil,
            createdAt: now,
            updatedAt: now,
            taskURL: url
        )
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("deep-link-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func testCodexThreadLinkTakesOnlyAUUIDShapedThreadId() {
        let host = SessionDeepLinkPolicy.codexDesktopBundleIdentifier
        XCTAssertEqual(
            SessionDeepLinkPolicy.deepLink(
                for: task(source: "codex", id: "01A0C63C-B317-79B1-B011-F1125200A3E9"),
                hostBundleIdentifier: host
            )?.absoluteString,
            "codex://threads/01a0c63c-b317-79b1-b011-f1125200a3e9"
        )
        for bad in ["", "not-a-uuid", "01a0c63c-b317-79b1-b011-f1125200a3e9/../settings", "01a0c63c?x=1", " 01a0c63c-b317-79b1-b011-f1125200a3e9"] {
            XCTAssertNil(
                SessionDeepLinkPolicy.deepLink(for: task(source: "codex", id: bad), hostBundleIdentifier: host),
                bad
            )
        }
        // A Codex session hosted in a terminal keeps the terminal.
        XCTAssertNil(SessionDeepLinkPolicy.deepLink(
            for: task(source: "codex", id: "01a0c63c-b317-79b1-b011-f1125200a3e9"),
            hostBundleIdentifier: "com.apple.Terminal"
        ))
    }

    func testClaudeLinkComesFromTheDesktopAppsOwnSessionIndex() throws {
        let root = try temporaryDirectory()
        let nested = root.appendingPathComponent("org/project", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let cli = "2fcc46b3-f720-4d9b-a568-4c6967002268"
        try """
        {"sessionId":"local_EA452D6B-7603-47A6-A4D1-E1C9BE05765C","cliSessionId":"\(cli.uppercased())","title":"secret title","cwd":"/Users/me"}
        """.write(to: nested.appendingPathComponent("local_ea452d6b.json"), atomically: true, encoding: .utf8)
        try """
        {"sessionId":"local_00000000-0000-4000-8000-000000000000","cliSessionId":"11111111-1111-4111-8111-111111111111"}
        """.write(to: nested.appendingPathComponent("other.json"), atomically: true, encoding: .utf8)
        try "not json".write(to: nested.appendingPathComponent("broken.json"), atomically: true, encoding: .utf8)
        let index = ClaudeDesktopSessionIndex(directory: root)

        XCTAssertEqual(
            SessionDeepLinkPolicy.deepLink(
                for: task(source: "claude-code", id: cli),
                hostBundleIdentifier: SessionDeepLinkPolicy.claudeDesktopBundleIdentifier,
                claudeSessionIndex: index
            )?.absoluteString,
            "claude://claude.ai/epitaxy/local_ea452d6b-7603-47a6-a4d1-e1c9be05765c"
        )
        XCTAssertNil(
            SessionDeepLinkPolicy.deepLink(
                for: task(source: "claude-code", id: "33333333-3333-4333-8333-333333333333"),
                hostBundleIdentifier: SessionDeepLinkPolicy.claudeDesktopBundleIdentifier,
                claudeSessionIndex: index
            ),
            "a CLI session the app never hosted has no link"
        )
        XCTAssertNil(
            SessionDeepLinkPolicy.deepLink(
                for: task(source: "claude-code", id: cli),
                hostBundleIdentifier: "com.googlecode.iterm2",
                claudeSessionIndex: index
            ),
            "a terminal-hosted session keeps the terminal"
        )
    }

    func testClaudeIndexRejectsMalformedAppSessionIdsAndOversizedFiles() throws {
        let root = try temporaryDirectory()
        let cli = "2fcc46b3-f720-4d9b-a568-4c6967002268"
        try """
        {"sessionId":"local_../../etc","cliSessionId":"\(cli)"}
        """.write(to: root.appendingPathComponent("bad-id.json"), atomically: true, encoding: .utf8)
        let padding = String(repeating: " ", count: ClaudeDesktopSessionIndex.maximumFileBytes)
        try """
        {"sessionId":"local_ea452d6b-7603-47a6-a4d1-e1c9be05765c","cliSessionId":"\(cli)"}\(padding)
        """.write(to: root.appendingPathComponent("too-big.json"), atomically: true, encoding: .utf8)
        let index = ClaudeDesktopSessionIndex(directory: root)

        XCTAssertNil(index.appSessionIdentifier(forCLISessionId: cli))
        XCTAssertNil(ClaudeDesktopSessionIndex.validatedAppSessionIdentifier("local_"))
        XCTAssertNil(ClaudeDesktopSessionIndex.validatedAppSessionIdentifier("remote_ea452d6b-7603-47a6-a4d1-e1c9be05765c"))
        XCTAssertEqual(
            ClaudeDesktopSessionIndex.validatedAppSessionIdentifier("EA452D6B-7603-47A6-A4D1-E1C9BE05765C"),
            "ea452d6b-7603-47a6-a4d1-e1c9be05765c"
        )
    }

    func testMissingIndexDirectoryYieldsNoLink() {
        let index = ClaudeDesktopSessionIndex(
            directory: URL(fileURLWithPath: "/nonexistent/\(UUID().uuidString)", isDirectory: true)
        )
        XCTAssertNil(index.appSessionIdentifier(forCLISessionId: "2fcc46b3-f720-4d9b-a568-4c6967002268"))
    }

    func testCursorLinkRaisesTheWorkspaceForAnExistingProjectDirectory() throws {
        let project = try temporaryDirectory().appendingPathComponent("my project", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let resolved = project.standardizedFileURL.resolvingSymlinksInPath()

        let link = SessionDeepLinkPolicy.deepLink(
            for: task(source: "cursor", id: "s1", url: project.absoluteString),
            hostBundleIdentifier: SessionDeepLinkPolicy.cursorBundleIdentifier
        )
        XCTAssertEqual(link?.scheme, "cursor")
        XCTAssertEqual(link?.host, "file")
        XCTAssertEqual(link?.path, resolved.path)
        XCTAssertTrue(link?.absoluteString.contains("my%20project") == true, "the path is percent-encoded")

        XCTAssertNil(
            SessionDeepLinkPolicy.deepLink(
                for: task(source: "cursor", id: "s1", url: "file:///nonexistent/\(UUID().uuidString)/"),
                hostBundleIdentifier: SessionDeepLinkPolicy.cursorBundleIdentifier
            ),
            "a missing directory never becomes a link"
        )
        XCTAssertNil(
            SessionDeepLinkPolicy.deepLink(
                for: task(source: "cursor", id: "s1", url: "https://example.com/"),
                hostBundleIdentifier: SessionDeepLinkPolicy.cursorBundleIdentifier
            ),
            "only the reviewed local directory route feeds the link"
        )
    }

    func testOtherSourcesAndHostsNeverGetALink() {
        for (source, host) in [
            ("manus", SessionDeepLinkPolicy.codexDesktopBundleIdentifier),
            ("kimi-code", "com.apple.Terminal"),
            ("claude-code", SessionDeepLinkPolicy.codexDesktopBundleIdentifier),
            ("codex", SessionDeepLinkPolicy.claudeDesktopBundleIdentifier),
        ] {
            XCTAssertNil(
                SessionDeepLinkPolicy.deepLink(
                    for: task(source: source, id: "01a0c63c-b317-79b1-b011-f1125200a3e9"),
                    hostBundleIdentifier: host
                ),
                "\(source) in \(host)"
            )
        }
    }
}
