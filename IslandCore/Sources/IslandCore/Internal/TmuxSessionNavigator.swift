import Darwin
import Foundation

/// Selects the original tmux window and pane without a shell and without
/// Accessibility or Apple Events permission. It is intentionally internal:
/// callers pass only a validated `SessionJumpContext` created at loopback.
enum TmuxSessionNavigator {
    /// Process launch on a busy Mac can itself take close to a second (and
    /// macOS may inspect a newly created executable before its first byte is
    /// run). Keep the command bounded, but leave enough headroom that a valid
    /// local tmux jump is not mistaken for a hang before tmux even starts.
    static let defaultTimeout: TimeInterval = 2.0
    private static let maximumOutputBytes = 4 * 1_024

    private static let executableCandidates = [
        "/opt/homebrew/bin/tmux",
        "/usr/local/bin/tmux",
        "/opt/local/bin/tmux",
    ]

    static func queryArguments(for context: SessionJumpContext) -> [String]? {
        guard let socket = context.tmuxSocketPath,
              let pane = context.tmuxPane else { return nil }
        return ["-S", socket, "display-message", "-p", "-t", pane, "#{window_id}"]
    }

    static func selectionArguments(
        for context: SessionJumpContext,
        windowID: String
    ) -> [String]? {
        guard let socket = context.tmuxSocketPath,
              let pane = context.tmuxPane,
              windowID.first == "@",
              windowID.count > 1,
              windowID.dropFirst().allSatisfy(\.isNumber),
              windowID.dropFirst().allSatisfy({ $0.isASCII }) else { return nil }
        return [
            "-S", socket,
            "select-window", "-t", windowID,
            ";",
            "select-pane", "-t", pane,
        ]
    }

    static func selectOriginalPane(
        _ context: SessionJumpContext,
        executableOverride: String? = nil,
        timeout: TimeInterval = defaultTimeout
    ) -> Bool {
        guard context.hasPreciseTmuxTarget,
              timeout.isFinite,
              0.05...10 ~= timeout,
              let executable = executableOverride.flatMap(validatedExecutable(at:))
                ?? executableCandidates.lazy.compactMap(validatedExecutable(at:)).first,
              let query = queryArguments(for: context),
              let windowData = run(
                  executable: executable,
                  arguments: query,
                  timeout: timeout
              ),
              let windowID = String(data: windowData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              let selection = selectionArguments(for: context, windowID: windowID)
        else { return false }

        return run(
            executable: executable,
            arguments: selection,
            timeout: timeout
        ) != nil
    }

    /// Execute one argument-only tmux command through the shared POSIX runner.
    /// Stdout is drained while the process runs, limited to 4 KiB, and the
    /// whole process group is killed at the monotonic deadline. Socket, pane,
    /// and window values therefore cannot become shell source or hold a jump
    /// task forever by filling a pipe or ignoring SIGTERM.
    private static func run(
        executable: URL,
        arguments: [String],
        timeout: TimeInterval
    ) -> Data? {
        guard var result = BoundedChildProcess.run(
            executableURL: executable,
            arguments: arguments,
            environment: childEnvironment(),
            outputLimit: maximumOutputBytes,
            timeout: timeout
        ) else { return nil }
        guard !result.timedOut,
              !result.exceededOutputLimit,
              result.exitCode == 0 else {
            result.output.resetBytes(in: result.output.indices)
            return nil
        }
        return result.output
    }

    /// Homebrew and MacPorts commonly expose tmux through a symlink, so resolve
    /// it once and validate the concrete file. A helper owned by another user
    /// or writable by group/other is never launched.
    private static func validatedExecutable(at path: String) -> URL? {
        guard path.hasPrefix("/"), path.utf8.count <= 4_096 else { return nil }
        let concrete = URL(fileURLWithPath: path)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        var information = stat()
        let result = concrete.path.withCString { candidate in
            Darwin.lstat(candidate, &information)
        }
        guard result == 0,
              (information.st_mode & S_IFMT) == S_IFREG,
              information.st_uid == 0 || information.st_uid == geteuid(),
              (information.st_mode & 0o022) == 0,
              (information.st_mode & 0o111) != 0 else { return nil }
        return concrete
    }

    /// The command has an explicit executable and socket; it does not need the
    /// user's shell startup files or inherited secrets. Preserve only bounded
    /// locale/terminal values needed for a normal tmux client.
    private static func childEnvironment(
        parent: [String: String] = ProcessInfo.processInfo.environment
    ) -> [String: String] {
        var result = [
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
            "TMPDIR": FileManager.default.temporaryDirectory.path,
        ]
        for key in ["LANG", "LC_ALL", "LC_CTYPE", "TERM"] {
            guard let value = parent[key],
                  !value.isEmpty,
                  !value.contains("\0"),
                  !value.contains("\n"),
                  !value.contains("\r"),
                  value.utf8.count <= 1_024 else { continue }
            result[key] = value
        }
        return result
    }
}
