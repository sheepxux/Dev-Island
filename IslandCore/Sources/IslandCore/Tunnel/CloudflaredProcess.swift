import Darwin
import Dispatch
import Foundation

public actor CloudflaredProcess {  // [C→S] public so the CLI target can use it
    static let maximumStartupOutputBytes = 1 * 1_024 * 1_024

    private static let defaultURLAcquisitionTimeout: TimeInterval = 30
    private static let terminationGraceMicroseconds: useconds_t = 100_000
    private static let quickTunnelPattern =
        #"https://[a-z0-9-]{1,63}\.trycloudflare\.com(?![a-z0-9.-])"#

    private let executableOverride: URL?
    private let urlAcquisitionTimeout: TimeInterval
    private var process: Process?
    private var stderrHandle: FileHandle?
    private var startupCollector: CloudflaredURLCollector?
    private var terminationObserver: CloudflaredTerminationObserver?
    private var stderrReaderObserver: CloudflaredReaderObserver?

    public init() {
        executableOverride = nil
        urlAcquisitionTimeout = Self.defaultURLAcquisitionTimeout
    }

    /// Internal injection keeps production discovery fixed while allowing
    /// deterministic timeout, output, and process-lifecycle regressions.
    init(executableURL: URL, urlAcquisitionTimeout: TimeInterval) {
        executableOverride = executableURL
        self.urlAcquisitionTimeout = urlAcquisitionTimeout
    }

    public var isRunning: Bool {
        process?.isRunning ?? false
    }

    /// Start a Cloudflare quick tunnel and return its validated public origin.
    ///
    /// Startup stderr is consumed through a one-shot, byte-bounded collector.
    /// A timer or task cancellation resolves the continuation directly, so a
    /// silent child cannot keep a structured task group alive past the stated
    /// deadline. After the URL is found, stderr is continuously drained and
    /// discarded so a long-running tunnel cannot block on a full pipe.
    public func start() async throws -> URL {
        guard urlAcquisitionTimeout.isFinite,
              urlAcquisitionTimeout > 0,
              urlAcquisitionTimeout <= Self.defaultURLAcquisitionTimeout else {
            throw CloudflaredError.invalidConfiguration
        }
        guard process == nil else { throw CloudflaredError.alreadyRunning }

        let resolved: ResolvedBinary
        if let executableOverride {
            guard let url = Self.validatedExecutable(at: executableOverride) else {
                throw CloudflaredError.binaryNotFound
            }
            resolved = ResolvedBinary(url: url, source: "test")
        } else {
            resolved = try findCloudflaredBinary()
        }
        IslandLogger.tunnel.info(
            "cloudflared executable resolved (source: \(resolved.source, privacy: .public))"
        )

        let proc = Process()
        proc.executableURL = resolved.url
        proc.arguments = ["tunnel", "--url", "http://127.0.0.1:7823", "--no-autoupdate"]
        proc.environment = Self.childEnvironment(
            from: ProcessInfo.processInfo.environment
        )
        proc.standardInput = FileHandle.nullDevice
        proc.standardOutput = FileHandle.nullDevice

        let stderrPipe = Pipe()
        let handle = stderrPipe.fileHandleForReading
        let collector = CloudflaredURLCollector(
            maximumBytes: Self.maximumStartupOutputBytes
        )
        let terminationObserver = CloudflaredTerminationObserver()
        let readerObserver = CloudflaredReaderObserver()
        proc.standardError = stderrPipe
        proc.terminationHandler = { process in
            terminationObserver.record(status: process.terminationStatus)
        }

        do {
            try proc.run()
        } catch {
            try? stderrPipe.fileHandleForWriting.close()
            try? handle.close()
            collector.finish(.cancelled)
            throw CloudflaredError.launchFailed
        }
        // Close the parent's duplicate writer immediately. The dedicated
        // reader can now observe a real EOF when the child exits.
        try? stderrPipe.fileHandleForWriting.close()
        Self.startStderrReader(
            handle: handle,
            collector: collector,
            observer: readerObserver
        )

        process = proc
        stderrHandle = handle
        startupCollector = collector
        self.terminationObserver = terminationObserver
        stderrReaderObserver = readerObserver
        IslandLogger.tunnel.info("cloudflared launched")

        let result = await withTaskCancellationHandler {
            await collector.wait(timeout: urlAcquisitionTimeout)
        } onCancel: {
            collector.finish(.cancelled)
        }

        guard process.map({ $0 === proc }) == true else {
            throw CloudflaredError.startupCancelled
        }
        startupCollector = nil

        switch result {
        case .url(let url) where !Task.isCancelled:
            if let status = terminationObserver.status {
                stop()
                throw CloudflaredError.processExited(status)
            }
            // The dedicated reader remains alive and discards later bytes
            // after the one-shot collector has completed.
            return url

        case .streamClosed:
            let status = terminationObserver.status ?? -1
            stop()
            throw CloudflaredError.processExited(status)

        case .outputLimitExceeded:
            stop()
            throw CloudflaredError.outputLimitExceeded

        case .timedOut:
            stop()
            throw CloudflaredError.urlAcquisitionTimeout

        case .cancelled, .url:
            stop()
            throw CloudflaredError.startupCancelled
        }
    }

    /// Stop the exact child owned by this instance. SIGTERM gets a short grace
    /// period, then SIGKILL closes the lifecycle even when a broken binary
    /// ignores termination. Cleanup is bounded and never waits on pipe output.
    public func stop() {
        startupCollector?.finish(.cancelled)
        startupCollector = nil

        let proc = process
        process = nil
        let handle = stderrHandle
        stderrHandle = nil
        let observer = terminationObserver
        terminationObserver = nil
        let readerObserver = stderrReaderObserver
        stderrReaderObserver = nil

        if let proc, proc.isRunning {
            proc.terminate()
            Darwin.usleep(Self.terminationGraceMicroseconds)
            if observer?.status == nil, proc.isRunning {
                _ = Darwin.kill(proc.processIdentifier, SIGKILL)
            }
        }
        // The reader owns and closes the handle after EOF. Waiting on this
        // dedicated thread does not depend on a main-run-loop callback.
        if readerObserver?.wait(timeout: 0.25) != true {
            _ = handle  // retained by the reader until its bounded read ends
        }
        IslandLogger.tunnel.info("cloudflared terminated")
    }

    // MARK: - URL and executable trust

    nonisolated static func quickTunnelURL(in data: Data) -> URL? {
        guard !data.isEmpty, data.count <= maximumStartupOutputBytes else { return nil }
        let text = String(decoding: data, as: UTF8.self)
        guard let range = text.range(
            of: quickTunnelPattern,
            options: .regularExpression
        ) else { return nil }

        let candidate = String(text[range])
        guard let components = URLComponents(string: candidate),
              components.scheme == "https",
              components.user == nil,
              components.password == nil,
              components.port == nil,
              components.path.isEmpty,
              components.query == nil,
              components.fragment == nil,
              let host = components.host,
              host == host.lowercased() else { return nil }

        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count == 3,
              labels[1] == "trycloudflare",
              labels[2] == "com",
              let first = labels[0].first,
              let last = labels[0].last,
              first.isASCII, first.isLetter || first.isNumber,
              last.isASCII, last.isLetter || last.isNumber else { return nil }
        return components.url
    }

    /// Locate a usable executable. Conventional package-manager paths lead;
    /// PATH fallback is resolved in-process rather than by executing `which`.
    /// This removes an unbounded helper process and rejects empty/relative PATH
    /// entries, unsafe file modes, and executables owned by another account.
    private func findCloudflaredBinary() throws -> ResolvedBinary {
        for candidate in [
            "/opt/homebrew/bin/cloudflared",
            "/usr/local/bin/cloudflared",
            "/opt/local/bin/cloudflared",
        ] {
            if let url = Self.validatedExecutable(
                at: URL(fileURLWithPath: candidate)
            ) {
                return ResolvedBinary(url: url, source: "package-manager")
            }
        }

        let environment = Self.childEnvironment(
            from: ProcessInfo.processInfo.environment
        )
        if let url = Self.lookupOnPath("cloudflared", path: environment["PATH"]) {
            return ResolvedBinary(url: url, source: "PATH")
        }
        throw CloudflaredError.binaryNotFound
    }

    nonisolated static func lookupOnPath(_ name: String, path: String?) -> URL? {
        guard !name.isEmpty,
              !name.contains("/"),
              name.utf8.count <= 128,
              name.unicodeScalars.allSatisfy({
                  $0.isASCII
                      && (CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_")
              }),
              let path = safeEnvironmentValue(path) else { return nil }

        let entries = path.split(separator: ":", omittingEmptySubsequences: false)
        guard entries.count <= 128 else { return nil }
        for entry in entries {
            guard !entry.isEmpty,
                  entry.first == "/",
                  entry.utf8.count <= 1_024 else { continue }
            let candidate = URL(fileURLWithPath: String(entry), isDirectory: true)
                .appendingPathComponent(name, isDirectory: false)
            if let executable = validatedExecutable(at: candidate) {
                return executable
            }
        }
        return nil
    }

    private nonisolated static func validatedExecutable(at url: URL) -> URL? {
        guard url.isFileURL else { return nil }
        let concrete = url.standardizedFileURL.resolvingSymlinksInPath()
        guard concrete.path.hasPrefix("/") else { return nil }

        var information = stat()
        let result = concrete.path.withCString { path in
            Darwin.lstat(path, &information)
        }
        guard result == 0,
              (information.st_mode & S_IFMT) == S_IFREG,
              information.st_uid == 0 || information.st_uid == geteuid(),
              (information.st_mode & 0o022) == 0,
              (information.st_mode & 0o111) != 0 else { return nil }
        return concrete
    }

    // MARK: - Child environment and bounded termination

    /// `Process` inherits the complete parent environment by default. Keep
    /// only settings required to resolve and run the selected binary; omit
    /// HOME so a quick tunnel cannot silently load account configuration.
    static func childEnvironment(from parent: [String: String]) -> [String: String] {
        let fallbackPath = "/usr/bin:/bin:/usr/sbin:/sbin"
        let path = safeEnvironmentValue(parent["PATH"]) ?? fallbackPath
        let temporaryDirectory = safeEnvironmentValue(parent["TMPDIR"])
            ?? FileManager.default.temporaryDirectory.path

        var result = [
            "PATH": path,
            "TMPDIR": temporaryDirectory,
        ]
        if let language = safeEnvironmentValue(parent["LANG"]) {
            result["LANG"] = language
        }
        if let locale = safeEnvironmentValue(parent["LC_ALL"]) {
            result["LC_ALL"] = locale
        }
        return result
    }

    private nonisolated static func safeEnvironmentValue(_ value: String?) -> String? {
        guard let value, !value.isEmpty,
              !value.contains("\n"), !value.contains("\r"),
              value.utf8.count <= 4_096 else { return nil }
        return value
    }

    private nonisolated static func startStderrReader(
        handle: FileHandle,
        collector: CloudflaredURLCollector,
        observer: CloudflaredReaderObserver
    ) {
        let thread = Thread {
            defer {
                try? handle.close()
                observer.finish()
            }
            let descriptor = handle.fileDescriptor
            var bytes = [UInt8](repeating: 0, count: 64 * 1_024)
            defer {
                bytes.withUnsafeMutableBytes { rawBuffer in
                    if let address = rawBuffer.baseAddress {
                        Darwin.memset(address, 0, rawBuffer.count)
                    }
                }
            }

            while true {
                let count = bytes.withUnsafeMutableBytes { rawBuffer in
                    Darwin.read(descriptor, rawBuffer.baseAddress, rawBuffer.count)
                }
                if count < 0, errno == EINTR { continue }
                guard count > 0 else {
                    collector.finish(.streamClosed)
                    return
                }

                var data = Data(bytes.prefix(count))
                collector.append(data)
                data.resetBytes(in: data.indices)
                bytes.withUnsafeMutableBytes { rawBuffer in
                    if let address = rawBuffer.baseAddress {
                        Darwin.memset(address, 0, count)
                    }
                }
            }
        }
        thread.name = "Dev Island cloudflared stderr drain"
        thread.qualityOfService = .utility
        thread.start()
    }

}

private enum CloudflaredStartupResult: @unchecked Sendable {
    case url(URL)
    case streamClosed
    case outputLimitExceeded
    case timedOut
    case cancelled
}

/// One waiter, one terminal result, and no provider-authored bytes leaving the
/// object. The lock is required because FileHandle and timeout callbacks run on
/// unrelated queues while the actor awaits the result.
private final class CloudflaredURLCollector: @unchecked Sendable {
    private let maximumBytes: Int
    private let lock = NSLock()
    private var buffer = Data()
    private var receivedBytes = 0
    private var result: CloudflaredStartupResult?
    private var waiter: CheckedContinuation<CloudflaredStartupResult, Never>?

    init(maximumBytes: Int) {
        self.maximumBytes = maximumBytes
    }

    func append(_ data: Data) {
        guard !data.isEmpty else { return }
        var terminal: CloudflaredStartupResult?

        lock.lock()
        if result == nil {
            if data.count > maximumBytes - receivedBytes {
                terminal = .outputLimitExceeded
            } else {
                receivedBytes += data.count
                buffer.append(data)
                if let url = CloudflaredProcess.quickTunnelURL(in: buffer) {
                    terminal = .url(url)
                }
            }
        }
        lock.unlock()

        if let terminal { finish(terminal) }
    }

    func wait(timeout: TimeInterval) async -> CloudflaredStartupResult {
        await withCheckedContinuation { continuation in
            lock.lock()
            if let result {
                lock.unlock()
                continuation.resume(returning: result)
                return
            }
            waiter = continuation
            lock.unlock()

            DispatchQueue.global(qos: .utility).asyncAfter(
                deadline: .now() + timeout
            ) { [weak self] in
                self?.finish(.timedOut)
            }
            if Task.isCancelled { finish(.cancelled) }
        }
    }

    func finish(_ terminal: CloudflaredStartupResult) {
        let continuation: CheckedContinuation<CloudflaredStartupResult, Never>?
        lock.lock()
        guard result == nil else {
            lock.unlock()
            return
        }
        result = terminal
        if !buffer.isEmpty {
            buffer.resetBytes(in: buffer.indices)
            buffer.removeAll(keepingCapacity: false)
        }
        continuation = waiter
        waiter = nil
        lock.unlock()
        continuation?.resume(returning: terminal)
    }
}

private final class CloudflaredTerminationObserver: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedStatus: Int32?

    var status: Int32? {
        lock.lock()
        defer { lock.unlock() }
        return recordedStatus
    }

    func record(status: Int32) {
        lock.lock()
        guard recordedStatus == nil else {
            lock.unlock()
            return
        }
        recordedStatus = status
        lock.unlock()
    }
}

private final class CloudflaredReaderObserver: @unchecked Sendable {
    private let lock = NSLock()
    private let signal = DispatchSemaphore(value: 0)
    private var didFinish = false

    func finish() {
        lock.lock()
        guard !didFinish else {
            lock.unlock()
            return
        }
        didFinish = true
        lock.unlock()
        signal.signal()
    }

    func wait(timeout: TimeInterval) -> Bool {
        lock.lock()
        let finished = didFinish
        lock.unlock()
        if finished { return true }
        _ = signal.wait(timeout: .now() + timeout)
        lock.lock()
        defer { lock.unlock() }
        return didFinish
    }
}

private struct ResolvedBinary {
    let url: URL
    let source: String
}

enum CloudflaredError: Error, Equatable {
    case binaryNotFound
    case invalidConfiguration
    case alreadyRunning
    case launchFailed
    case urlAcquisitionTimeout
    case outputLimitExceeded
    case startupCancelled
    case processExited(Int32)
}
