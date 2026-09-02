import Darwin
import Foundation
import IslandCore

/// Reads the checked-out git branch of a local session's project directory
/// so a task row can say *which* branch an agent is working on.
///
/// This is the only place the app opens a file inside a user's project. The
/// read is deliberately tiny and defensive: it walks at most
/// `maximumParentLevels` directories up from the session `cwd`, opens
/// `.git` and `HEAD` through no-follow descriptors owned by the current
/// user, reads at most `maximumBytes`, and returns nothing on any surprise.
/// The result is a bounded branch name or short commit prefix. It is never
/// logged, persisted, or transmitted.
enum ProjectBranchReader {
    static let maximumParentLevels = 8
    static let maximumBytes = 4_096
    static let maximumBranchCharacters = 64
    static let detachedPrefixLength = 7

    /// The branch (or short detached commit) for the project that owns
    /// `taskURL`, or `nil` when the task has no local project, the project is
    /// not a git checkout, or anything about the checkout looks unsafe.
    static func branch(forTaskURL taskURL: String) -> String? {
        guard let url = URL(string: taskURL), url.isFileURL else { return nil }
        let path = url.standardizedFileURL.path
        guard path.hasPrefix("/") else { return nil }
        return branch(forProjectPath: path)
    }

    static func branch(forProjectPath path: String) -> String? {
        var directory = URL(fileURLWithPath: path, isDirectory: true)
        for _ in 0...maximumParentLevels {
            if let gitDirectory = gitDirectory(in: directory) {
                return branch(inGitDirectory: gitDirectory)
            }
            let parent = directory.deletingLastPathComponent()
            guard parent.path != directory.path else { return nil }
            directory = parent
        }
        return nil
    }

    // MARK: - Resolution

    /// `<dir>/.git` is either the repository directory or, for worktrees and
    /// submodules, a small file containing `gitdir: <path>`.
    private static func gitDirectory(in directory: URL) -> URL? {
        let candidate = directory.appendingPathComponent(".git", isDirectory: false)
        var information = stat()
        guard candidate.path.withCString({ lstat($0, &information) }) == 0,
              information.st_uid == geteuid() else { return nil }
        switch information.st_mode & S_IFMT {
        case S_IFDIR:
            return URL(fileURLWithPath: candidate.path, isDirectory: true)
        case S_IFREG:
            guard let contents = boundedContents(of: candidate),
                  contents.hasPrefix("gitdir:") else { return nil }
            let target = contents.dropFirst("gitdir:".count)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !target.isEmpty, !target.contains("\0") else { return nil }
            if target.hasPrefix("/") {
                return URL(fileURLWithPath: target, isDirectory: true)
            }
            return directory.appendingPathComponent(target, isDirectory: true)
                .standardizedFileURL
        default:
            return nil
        }
    }

    private static func branch(inGitDirectory gitDirectory: URL) -> String? {
        let head = gitDirectory.appendingPathComponent("HEAD", isDirectory: false)
        guard let contents = boundedContents(of: head) else { return nil }
        return parseHead(contents)
    }

    /// `ref: refs/heads/<name>` → `<name>`; a bare object ID → its short
    /// prefix; anything else → nil.
    static func parseHead(_ contents: String) -> String? {
        let line = contents.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
            .first.map(String.init) ?? ""
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("ref: refs/heads/") {
            let name = String(trimmed.dropFirst("ref: refs/heads/".count))
            return boundedBranchName(name)
        }
        let isObjectID = (trimmed.count == 40 || trimmed.count == 64)
            && trimmed.allSatisfy(\.isHexDigit)
        guard isObjectID else { return nil }
        return String(trimmed.prefix(detachedPrefixLength))
    }

    private static func boundedBranchName(_ name: String) -> String? {
        guard !name.isEmpty,
              name.unicodeScalars.allSatisfy({ scalar in
                  !CharacterSet.controlCharacters.contains(scalar)
              }) else { return nil }
        guard name.count <= maximumBranchCharacters else {
            return String(name.prefix(maximumBranchCharacters - 1)) + "…"
        }
        return name
    }

    /// Open the final path component without following a symlink, require a
    /// current-user regular file, and read at most `maximumBytes`.
    private static func boundedContents(of url: URL) -> String? {
        let descriptor = url.path.withCString { path in
            Darwin.open(path, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
        }
        guard descriptor >= 0 else { return nil }
        defer { Darwin.close(descriptor) }

        var information = stat()
        guard Darwin.fstat(descriptor, &information) == 0,
              (information.st_mode & S_IFMT) == S_IFREG,
              information.st_uid == geteuid(),
              information.st_size >= 0,
              information.st_size <= off_t(maximumBytes) else { return nil }

        var bytes = [UInt8](repeating: 0, count: Int(information.st_size))
        var total = 0
        while total < bytes.count {
            let count = bytes.withUnsafeMutableBytes { buffer in
                Darwin.pread(
                    descriptor,
                    buffer.baseAddress?.advanced(by: total),
                    buffer.count - total,
                    off_t(total)
                )
            }
            if count <= 0 { return nil }
            total += count
        }
        return String(decoding: bytes, as: UTF8.self)
    }
}

/// Main-actor cache that resolves branches off the main thread and keeps
/// them fresh enough for a live panel. Rows read the cache synchronously;
/// misses and stale entries schedule one bounded resolution each.
@MainActor
@Observable
public final class ProjectBranchCache {
    public static let shared = ProjectBranchCache()

    /// A branch checkout is rare compared to session heartbeats, so a
    /// half-minute of staleness is invisible in practice and keeps the file
    /// reads far below one per row per second.
    static let refreshInterval: TimeInterval = 30

    private struct Entry {
        var branch: String?
        var resolvedAt: Date
    }

    private var entries: [String: Entry] = [:]
    private var inFlight: Set<String> = []
    private let resolver: @Sendable (String) -> String?
    private let now: () -> Date

    init(
        resolver: @escaping @Sendable (String) -> String? = ProjectBranchReader.branch(forTaskURL:),
        now: @escaping () -> Date = { .now }
    ) {
        self.resolver = resolver
        self.now = now
    }

    /// The last known branch for `taskURL`, refreshing in the background
    /// when the entry is missing or older than `refreshInterval`.
    public func branch(forTaskURL taskURL: String) -> String? {
        guard taskURL.hasPrefix("file://") else { return nil }
        let entry = entries[taskURL]
        if let entry, now().timeIntervalSince(entry.resolvedAt) < Self.refreshInterval {
            return entry.branch
        }
        scheduleResolution(for: taskURL)
        return entry?.branch
    }

    /// Drop everything, for tests and for a user-initiated history wipe.
    public func reset() {
        entries.removeAll()
        inFlight.removeAll()
    }

    private func scheduleResolution(for taskURL: String) {
        guard !inFlight.contains(taskURL) else { return }
        inFlight.insert(taskURL)
        let resolver = self.resolver
        Task.detached(priority: .utility) { [weak self] in
            let branch = resolver(taskURL)
            await self?.store(branch, for: taskURL)
        }
    }

    private func store(_ branch: String?, for taskURL: String) {
        inFlight.remove(taskURL)
        entries[taskURL] = Entry(branch: branch, resolvedAt: now())
    }
}
