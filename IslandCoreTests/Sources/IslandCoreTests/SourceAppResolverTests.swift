import Darwin
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

    func testCapturedTerminalBeatsGenericCodexDesktopFallback() {
        XCTAssertEqual(
            SourceAppResolver.resolveBundleId(
                source: "codex",
                running: [codexBundle, "com.mitchellh.ghostty", "com.apple.Terminal"],
                preferredTerminalBundleIdentifier: "com.mitchellh.ghostty"
            ),
            "com.mitchellh.ghostty"
        )
    }

    func testNonTerminalSourceIgnoresInjectedTerminalPreference() {
        XCTAssertEqual(
            SourceAppResolver.resolveBundleId(
                source: "cursor",
                running: [cursorBundle, "com.apple.Terminal"],
                preferredTerminalBundleIdentifier: "com.apple.Terminal"
            ),
            cursorBundle
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

    func testSessionJumpContextNormalizesTerminalAndTmuxIdentity() throws {
        let context = try XCTUnwrap(SessionJumpContext(
            terminalProgram: "Apple_Terminal",
            tty: " ttys004 ",
            tmuxEnvironment: "/private/tmp/tmux-501/default,734,2",
            tmuxPane: "%12"
        ))

        XCTAssertEqual(context.terminalBundleIdentifier, "com.apple.Terminal")
        XCTAssertEqual(context.terminalProgram, "Apple_Terminal")
        XCTAssertEqual(context.tty, "ttys004")
        XCTAssertEqual(context.tmuxSocketPath, "/private/tmp/tmux-501/default")
        XCTAssertEqual(context.tmuxPane, "%12")
    }

    func testSessionJumpContextRejectsControlCharactersAndPartialTmuxTargets() throws {
        let context = try XCTUnwrap(SessionJumpContext(
            terminalBundleIdentifier: "com.apple.Terminal\nInjected: value",
            terminalProgram: "ghostty",
            tty: "??",
            tmuxEnvironment: "relative/socket,1,0",
            tmuxPane: "%not-a-number"
        ))

        XCTAssertEqual(context.terminalBundleIdentifier, "com.mitchellh.ghostty")
        XCTAssertNil(context.tty)
        XCTAssertNil(context.tmuxSocketPath)
        XCTAssertNil(context.tmuxPane)
        XCTAssertNil(SessionJumpContext(terminalBundleIdentifier: "not a bundle"))
    }

    func testTmuxNavigationUsesValidatedPaneAndWindowWithoutAShell() throws {
        let context = try XCTUnwrap(SessionJumpContext(
            terminalBundleIdentifier: "com.googlecode.iterm2",
            tmuxEnvironment: "/private/tmp/tmux,with-comma/default,55,1",
            tmuxPane: "%7"
        ))

        XCTAssertEqual(TmuxSessionNavigator.queryArguments(for: context), [
            "-S", "/private/tmp/tmux,with-comma/default",
            "display-message", "-p", "-t", "%7", "#{window_id}",
        ])
        XCTAssertEqual(
            TmuxSessionNavigator.selectionArguments(for: context, windowID: "@3"),
            [
                "-S", "/private/tmp/tmux,with-comma/default",
                "select-window", "-t", "@3",
                ";",
                "select-pane", "-t", "%7",
            ]
        )
        XCTAssertNil(TmuxSessionNavigator.selectionArguments(
            for: context,
            windowID: "@3; display-message owned"
        ))
        XCTAssertNil(TmuxSessionNavigator.selectionArguments(
            for: context,
            windowID: "@"
        ))
    }

    func testTmuxNavigatorRunsTheTwoExpectedArgumentOnlyCommands() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("dev-island-fake-tmux-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let executable = directory.appendingPathComponent("tmux")
        let trace = directory.appendingPathComponent("trace")
        let script = """
        #!/bin/sh
        [ -z "${HOME+x}" ] || exit 9
        case " $* " in
          # Model a busy Mac where executable inspection/process startup is
          # slower than the tmux command itself. The navigation timeout must
          # stay bounded without killing a valid command before it starts.
          *" display-message "*) sleep 1; printf '@8\\n' ;;
        esac
        printf '%s\\n' "$@" >> '\(trace.path)'
        """
        try Data(script.utf8).write(to: executable)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: executable.path
        )
        let context = try XCTUnwrap(SessionJumpContext(
            terminalProgram: "ghostty",
            tmuxEnvironment: "/private/tmp/tmux-501/default,55,0",
            tmuxPane: "%3"
        ))

        XCTAssertTrue(TmuxSessionNavigator.selectOriginalPane(
            context,
            executableOverride: executable.path,
            // Ephemeral scripts can incur Gatekeeper/filesystem inspection
            // latency on a loaded CI Mac. Production keeps its 2 s bound;
            // this test isolates argument transport from host startup jitter.
            timeout: 10
        ))
        let arguments = try String(contentsOf: trace, encoding: .utf8)
            .split(separator: "\n")
            .map(String.init)
        XCTAssertEqual(arguments, [
            "-S", "/private/tmp/tmux-501/default",
            "display-message", "-p", "-t", "%3", "#{window_id}",
            "-S", "/private/tmp/tmux-501/default",
            "select-window", "-t", "@8", ";", "select-pane", "-t", "%3",
        ])
    }

    func testTmuxNavigatorKillsTermIgnoringChildAtDeadline() throws {
        let fixture = try TmuxProcessFixture()
        defer { fixture.cleanup() }
        let executable = try fixture.makeExecutable(
            """
            #!/bin/sh
            trap '' TERM
            while :; do :; done
            """
        )
        let context = try tmuxContext()
        let started = Date()

        XCTAssertFalse(TmuxSessionNavigator.selectOriginalPane(
            context,
            executableOverride: executable.path,
            timeout: 0.1
        ))
        XCTAssertLessThan(Date().timeIntervalSince(started), 1.5)
    }

    func testTmuxNavigatorRejectsUnboundedOutputWithoutDeadlock() throws {
        let fixture = try TmuxProcessFixture()
        defer { fixture.cleanup() }
        let executable = try fixture.makeExecutable(
            "#!/bin/sh\nexec /usr/bin/yes x\n"
        )
        let context = try tmuxContext()
        let started = Date()

        XCTAssertFalse(TmuxSessionNavigator.selectOriginalPane(
            context,
            executableOverride: executable.path,
            timeout: 5
        ))
        // This test owns pipe drainage and process-group termination, not the
        // loaded host's ability to schedule a fresh fixture within 1.5 s.
        XCTAssertLessThan(Date().timeIntervalSince(started), 5.5)
    }

    func testTmuxProductionTimeoutRemainsTwoSeconds() {
        XCTAssertEqual(TmuxSessionNavigator.defaultTimeout, 2)
    }

    func testTmuxNavigatorNeverLaunchesWritableExecutable() throws {
        let fixture = try TmuxProcessFixture()
        defer { fixture.cleanup() }
        let sentinel = fixture.directory.appendingPathComponent("launched")
        let executable = try fixture.makeExecutable(
            "#!/bin/sh\n/usr/bin/touch '\(sentinel.path)'\nprintf '@1\\n'\n"
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o722],
            ofItemAtPath: executable.path
        )

        XCTAssertFalse(TmuxSessionNavigator.selectOriginalPane(
            try tmuxContext(),
            executableOverride: executable.path,
            timeout: 1
        ))
        XCTAssertFalse(FileManager.default.fileExists(atPath: sentinel.path))
    }

    func testTmuxNavigatorKillsBackgroundDescendantAfterLeaderExits() throws {
        let fixture = try TmuxProcessFixture()
        defer { fixture.cleanup() }
        let childPIDFile = fixture.directory.appendingPathComponent("child-pid")
        let executable = try fixture.makeExecutable(
            """
            #!/bin/sh
            case " $* " in
              *" display-message "*)
                ( trap '' TERM; while :; do /bin/sleep 1; done ) &
                printf '%s\\n' "$!" > '\(childPIDFile.path)'
                printf '@8\\n'
                ;;
            esac
            """
        )

        XCTAssertTrue(TmuxSessionNavigator.selectOriginalPane(
            try tmuxContext(),
            executableOverride: executable.path,
            // Isolate descendant cleanup from scheduler pressure. The
            // production fallback remains locked to two seconds above.
            timeout: 5
        ))
        let childPID = try XCTUnwrap(Int32(
            String(contentsOf: childPIDFile, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        ))

        var childIsGone = false
        for _ in 0..<500 {
            if Darwin.kill(childPID, 0) != 0, errno == ESRCH {
                childIsGone = true
                break
            }
            Darwin.usleep(10_000)
        }
        XCTAssertTrue(childIsGone, "bounded runner left a background descendant alive")
    }

    private func tmuxContext() throws -> SessionJumpContext {
        try XCTUnwrap(SessionJumpContext(
            terminalProgram: "ghostty",
            tmuxEnvironment: "/private/tmp/tmux-501/default,55,0",
            tmuxPane: "%3"
        ))
    }
}

private final class TmuxProcessFixture {
    let directory: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("dev-island-tmux-process-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: false
        )
    }

    func makeExecutable(_ source: String) throws -> URL {
        let url = directory.appendingPathComponent("tmux")
        try Data(source.utf8).write(to: url)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: url.path
        )
        return url
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: directory)
    }
}
