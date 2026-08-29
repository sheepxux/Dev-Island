import Darwin
import Foundation

/// Reads only provider-authored `token_count` events from a bounded suffix of
/// recent Codex rollout files. The feature is opt-in at the UI layer.
///
/// Non-usage content fields are never modeled, returned or logged. Reads are
/// local and read-only; this type has no network or credential dependency.
public struct CodexLocalUsageReader: Sendable {
    public static var defaultDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex", isDirectory: true)
    }

    private let codexDirectory: URL
    private let maximumTailBytes: Int
    private let maximumCandidateFiles: Int
    private let maximumEnumeratedEntries: Int
    private let beforeBoundedRead: (@Sendable (URL) -> Void)?

    public init(
        codexDirectory: URL = Self.defaultDirectory,
        maximumTailBytes: Int = 512 * 1_024,
        maximumCandidateFiles: Int = 24
    ) {
        self.init(
            codexDirectory: codexDirectory,
            maximumTailBytes: maximumTailBytes,
            maximumCandidateFiles: maximumCandidateFiles,
            maximumEnumeratedEntries: 8 * 1_024,
            beforeBoundedRead: nil
        )
    }

    /// Internal controls make concurrent-growth and enumeration-pressure
    /// attacks deterministic without weakening production limits.
    init(
        codexDirectory: URL,
        maximumTailBytes: Int,
        maximumCandidateFiles: Int,
        maximumEnumeratedEntries: Int,
        beforeBoundedRead: (@Sendable (URL) -> Void)? = nil
    ) {
        self.codexDirectory = codexDirectory
        self.maximumTailBytes = min(max(maximumTailBytes, 4 * 1_024), 2 * 1_024 * 1_024)
        self.maximumCandidateFiles = min(max(maximumCandidateFiles, 1), 128)
        self.maximumEnumeratedEntries = min(max(maximumEnumeratedEntries, 1), 8 * 1_024)
        self.beforeBoundedRead = beforeBoundedRead
    }

    /// Returns nil when Codex has not written a recent, valid rate-limit event.
    /// File-system and malformed-record failures remain isolated to this one
    /// optional insight; callers should keep the rest of Settings available.
    public func latestSnapshot() throws -> AgentUsageSnapshot? {
        var firstReadError: Error?
        for candidate in try candidateFiles() {
            do {
                if let snapshot = try snapshot(in: candidate.url) {
                    return snapshot
                }
            } catch {
                if firstReadError == nil { firstReadError = error }
            }
        }
        if let firstReadError { throw firstReadError }
        return nil
    }

    private struct Candidate {
        let url: URL
        let modifiedAt: Date
    }

    private func candidateFiles() throws -> [Candidate] {
        let manager = FileManager.default
        let keys: Set<URLResourceKey> = [
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .contentModificationDateKey,
        ]
        var files: [Candidate] = []
        var enumeratedEntries = 0

        for name in ["sessions", "archived_sessions"] {
            let root = codexDirectory.appendingPathComponent(name, isDirectory: true)
            guard let rootValues = try? root.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
                  rootValues.isDirectory == true,
                  rootValues.isSymbolicLink != true,
                  let enumerator = manager.enumerator(
                    at: root,
                    includingPropertiesForKeys: Array(keys),
                    options: [.skipsHiddenFiles, .skipsPackageDescendants]
                  ) else { continue }

            while let url = enumerator.nextObject() as? URL {
                enumeratedEntries += 1
                guard enumeratedEntries <= maximumEnumeratedEntries else {
                    throw CodexLocalUsageReaderError.enumerationLimitExceeded
                }
                guard let values = try? url.resourceValues(forKeys: keys) else { continue }
                if values.isSymbolicLink == true {
                    enumerator.skipDescendants()
                    continue
                }
                guard values.isRegularFile == true,
                      url.lastPathComponent.hasPrefix("rollout-"),
                      url.pathExtension == "jsonl" else { continue }
                insertCandidate(
                    Candidate(
                        url: url,
                        modifiedAt: values.contentModificationDate ?? .distantPast
                    ),
                    into: &files
                )
            }
        }

        return files
    }

    private func insertCandidate(_ candidate: Candidate, into files: inout [Candidate]) {
        files.append(candidate)
        files.sort(by: candidatePrecedes)
        if files.count > maximumCandidateFiles {
            files.removeLast(files.count - maximumCandidateFiles)
        }
    }

    private func candidatePrecedes(_ lhs: Candidate, _ rhs: Candidate) -> Bool {
        if lhs.modifiedAt != rhs.modifiedAt { return lhs.modifiedAt > rhs.modifiedAt }
        return lhs.url.path < rhs.url.path
    }

    private func snapshot(in url: URL) throws -> AgentUsageSnapshot? {
        let tail = try boundedTail(of: url)
        let data = tail.data
        guard !data.isEmpty else { return nil }

        var lines = data.split(separator: 0x0A, omittingEmptySubsequences: true)
        if tail.offset > 0, data.first != 0x0A, !lines.isEmpty {
            // The suffix may begin in a prompt or response record. Never try
            // to decode a partial JSON line as usage.
            lines.removeFirst()
        }

        let tokenCountNeedle = Data(#""token_count""#.utf8)
        let decoder = JSONDecoder()
        for line in lines.reversed() {
            guard line.count <= 256 * 1_024 else { continue }
            let record = Data(line)
            guard record.range(of: tokenCountNeedle) != nil,
                  let envelope = try? decoder.decode(CodexEnvelope.self, from: record),
                  envelope.type == "event_msg",
                  envelope.payload.type == "token_count",
                  let limits = envelope.payload.rateLimits else { continue }

            var windows: [AgentUsageWindow] = []
            if let primary = limits.primary?.window(kind: .primary) {
                windows.append(primary)
            }
            if let secondary = limits.secondary?.window(kind: .secondary) {
                windows.append(secondary)
            }
            guard !windows.isEmpty else { continue }

            return AgentUsageSnapshot(
                provider: .codex,
                observedAt: envelope.observedAt ?? tail.modifiedAt,
                windows: windows
            )
        }
        return nil
    }

    private struct BoundedTail {
        let data: Data
        let offset: off_t
        let modifiedAt: Date
    }

    /// Open the final component without following a symlink, validate the
    /// concrete descriptor, and read exactly the suffix measured by the first
    /// `fstat`. `pread` cannot run past that snapshot when Codex appends after
    /// the size check, unlike an unbounded read through the current EOF.
    private func boundedTail(of url: URL) throws -> BoundedTail {
        guard url.isFileURL, url.path.hasPrefix("/") else {
            throw CodexLocalUsageReaderError.unsafeCandidate
        }
        let descriptor = url.path.withCString { path in
            Darwin.open(path, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
        }
        guard descriptor >= 0 else {
            throw CodexLocalUsageReaderError.unsafeCandidate
        }
        defer { Darwin.close(descriptor) }

        var information = stat()
        guard Darwin.fstat(descriptor, &information) == 0,
              (information.st_mode & S_IFMT) == S_IFREG,
              information.st_uid == geteuid(),
              (information.st_mode & 0o022) == 0,
              information.st_size >= 0 else {
            throw CodexLocalUsageReaderError.unsafeCandidate
        }

        let length = information.st_size
        let readLength = min(off_t(maximumTailBytes), length)
        let offset = length - readLength
        let modifiedAt = Date(
            timeIntervalSince1970: TimeInterval(information.st_mtimespec.tv_sec)
                + TimeInterval(information.st_mtimespec.tv_nsec) / 1_000_000_000
        )
        guard readLength > 0 else {
            return BoundedTail(data: Data(), offset: 0, modifiedAt: modifiedAt)
        }

        beforeBoundedRead?(url)
        var bytes = [UInt8](repeating: 0, count: Int(readLength))
        defer {
            bytes.withUnsafeMutableBytes { rawBuffer in
                if let address = rawBuffer.baseAddress {
                    Darwin.memset(address, 0, rawBuffer.count)
                }
            }
        }
        var total = 0
        while total < bytes.count {
            let byteCount = bytes.withUnsafeMutableBytes { rawBuffer in
                Darwin.pread(
                    descriptor,
                    rawBuffer.baseAddress?.advanced(by: total),
                    rawBuffer.count - total,
                    offset + off_t(total)
                )
            }
            if byteCount > 0 {
                total += byteCount
                continue
            }
            if byteCount < 0, errno == EINTR { continue }
            throw CodexLocalUsageReaderError.readFailed
        }

        return BoundedTail(
            data: Data(bytes),
            offset: offset,
            modifiedAt: modifiedAt
        )
    }
}

enum CodexLocalUsageReaderError: Error, Equatable {
    case enumerationLimitExceeded
    case unsafeCandidate
    case readFailed
}

private struct CodexEnvelope: Decodable {
    let timestamp: String?
    let type: String
    let payload: Payload

    var observedAt: Date? {
        guard let timestamp else { return nil }
        return ISO8601DateFormatter().date(from: timestamp)
    }

    struct Payload: Decodable {
        let type: String
        let rateLimits: RateLimits?

        enum CodingKeys: String, CodingKey {
            case type
            case rateLimits = "rate_limits"
        }
    }

    struct RateLimits: Decodable {
        let primary: Window?
        let secondary: Window?
    }

    struct Window: Decodable {
        let usedPercent: Double
        let windowMinutes: Int
        let resetsAt: TimeInterval?

        enum CodingKeys: String, CodingKey {
            case usedPercent = "used_percent"
            case windowMinutes = "window_minutes"
            case resetsAt = "resets_at"
        }

        func window(kind: AgentUsageWindow.Kind) -> AgentUsageWindow? {
            let resetDate = resetsAt.flatMap { seconds -> Date? in
                guard seconds.isFinite, seconds > 0 else { return nil }
                return Date(timeIntervalSince1970: seconds)
            }
            return AgentUsageWindow(
                kind: kind,
                usedPercent: usedPercent,
                durationMinutes: windowMinutes,
                resetsAt: resetDate
            )
        }
    }
}
