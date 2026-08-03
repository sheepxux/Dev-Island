import XCTest
@testable import IslandCore

final class SourceAppResolverTests: XCTestCase {

    private let cursorBundle = "com.todesktop.230313mzl4w4u92"
    private let codexBundle = "com.openai.codex"

    func testCursorResolvesOnlyWhenCursorRuns() {
        XCTAssertEqual(
            SourceAppResolver.resolveBundleId(source: "cursor", running: [cursorBundle, "com.apple.Terminal"]),
            cursorBundle
        )
        XCTAssertNil(
            SourceAppResolver.resolveBundleId(source: "cursor", running: ["com.apple.Terminal"])
        )
    }

    func testCodexPrefersDesktopOverTerminal() {
        XCTAssertEqual(
            SourceAppResolver.resolveBundleId(source: "codex", running: [codexBundle, "com.apple.Terminal"]),
            codexBundle
        )
        // CLI-only user: falls through to their terminal.
        XCTAssertEqual(
            SourceAppResolver.resolveBundleId(source: "codex", running: ["com.apple.Terminal"]),
            "com.apple.Terminal"
        )
    }

    func testClaudeCodeResolvesRunningTerminal() {
        XCTAssertEqual(
            SourceAppResolver.resolveBundleId(source: "claude-code", running: ["com.mitchellh.ghostty"]),
            "com.mitchellh.ghostty"
        )
        XCTAssertNil(
            SourceAppResolver.resolveBundleId(source: "claude-code", running: [cursorBundle])
        )
    }

    func testManusAndUnknownSourcesNeverResolve() {
        // No local app to jump to — TaskStore falls back to openTaskInBrowser.
        XCTAssertNil(SourceAppResolver.resolveBundleId(source: "manus", running: [cursorBundle, codexBundle]))
        XCTAssertNil(SourceAppResolver.resolveBundleId(source: "debug", running: [cursorBundle]))
    }
}
