import Foundation

public actor CloudflaredProcess {  // [C→S] public so the CLI target can use it
    private var process: Process?
    private let urlAcquisitionTimeout: TimeInterval = 30

    public init() {}

    public var isRunning: Bool {
        process?.isRunning ?? false
    }

    /// Start the cloudflared tunnel and return the public URL once it becomes available.
    public func start() async throws -> URL {
        let resolved = try findCloudflaredBinary()
        if resolved.needsChmod {
            try ensureExecutable(at: resolved.url)
        }
        IslandLogger.tunnel.info("cloudflared resolved at \(resolved.url.path) (source: \(resolved.source))")

        let proc = Process()
        proc.executableURL = resolved.url
        proc.arguments = ["tunnel", "--url", "http://127.0.0.1:7823", "--no-autoupdate"]

        let stderrPipe = Pipe()
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = stderrPipe

        try proc.run()
        process = proc
        IslandLogger.tunnel.info("cloudflared launched (pid \(proc.processIdentifier))")

        return try await withThrowingTaskGroup(of: URL?.self) { group in
            // Task 1: scan stderr for the tunnel URL
            group.addTask {
                return try await self.scanForURL(pipe: stderrPipe)
            }
            // Task 2: timeout watchdog
            group.addTask {
                try await Task.sleep(for: .seconds(self.urlAcquisitionTimeout))
                return nil
            }

            for try await result in group {
                group.cancelAll()
                if let url = result {
                    return url
                }
                throw CloudflaredError.urlAcquisitionTimeout
            }
            throw CloudflaredError.urlAcquisitionTimeout
        }
    }

    public func stop() {
        guard let proc = process, proc.isRunning else { return }
        proc.terminate()
        process = nil
        IslandLogger.tunnel.info("cloudflared terminated")
    }

    // MARK: - Private

    private func scanForURL(pipe: Pipe) async throws -> URL? {
        let pattern = try NSRegularExpression(pattern: #"https://[a-z0-9\-]+\.trycloudflare\.com"#)
        let handle = pipe.fileHandleForReading
        // Read stderr line by line using AsyncStream
        let lines = AsyncStream<String> { continuation in
            handle.readabilityHandler = { fh in
                let data = fh.availableData
                guard !data.isEmpty else {
                    continuation.finish()
                    return
                }
                if let text = String(data: data, encoding: .utf8) {
                    for line in text.components(separatedBy: .newlines) where !line.isEmpty {
                        continuation.yield(line)
                    }
                }
            }
        }

        for await line in lines {
            IslandLogger.tunnel.debug("cloudflared: \(line)")
            let range = NSRange(line.startIndex..., in: line)
            if let match = pattern.firstMatch(in: line, range: range),
               let swiftRange = Range(match.range, in: line) {
                let urlString = String(line[swiftRange])
                if let url = URL(string: urlString) {
                    handle.readabilityHandler = nil
                    return url
                }
            }
        }
        return nil
    }

    /// Locate a usable `cloudflared` executable. We try, in order:
    ///
    /// 1. `/opt/homebrew/bin/cloudflared` — Apple Silicon Homebrew
    ///    (Cask `depends_on cask: "cloudflared"` lands here)
    /// 2. `/usr/local/bin/cloudflared` — Intel Homebrew, also some
    ///    manual installs
    /// 3. `cloudflared` on `$PATH` — `/usr/bin/env which` lookup so
    ///    unusual install locations (Nix, MacPorts, custom prefix)
    ///    still work
    ///
    /// All three failing → throw `binaryNotFound`. The caller (TaskStore
    /// via TunnelManager) catches this and switches to polling-only
    /// mode, so the app stays functional just with 60s sync latency
    /// instead of realtime webhooks.
    ///
    /// The Cask formula's `depends_on cask: "cloudflared"` makes step
    /// 1 the common path for `brew install --cask island` users.
    /// Source builds and offline installs land in step 3 (or fail
    /// over to polling).
    private func findCloudflaredBinary() throws -> ResolvedBinary {
        // 1-2. Conventional Homebrew locations
        for candidate in ["/opt/homebrew/bin/cloudflared", "/usr/local/bin/cloudflared"] {
            let url = URL(fileURLWithPath: candidate)
            if FileManager.default.isExecutableFile(atPath: url.path) {
                return ResolvedBinary(url: url, source: "homebrew", needsChmod: false)
            }
        }

        // 3. $PATH lookup. /usr/bin/env is more reliably present than
        //    /usr/bin/which (Apple has been quietly trimming the
        //    base /usr/bin set, and `env which` works inside sandboxed
        //    contexts where login-shell PATH machinery may not).
        if let pathURL = Self.lookupOnPath("cloudflared") {
            return ResolvedBinary(url: pathURL, source: "PATH", needsChmod: false)
        }

        throw CloudflaredError.binaryNotFound
    }

    private func ensureExecutable(at url: URL) throws {
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: url.path
        )
    }

    private static func lookupOnPath(_ name: String) -> URL? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        task.arguments = ["which", name]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
            task.waitUntilExit()
            guard task.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let path = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return path.isEmpty ? nil : URL(fileURLWithPath: path)
        } catch {
            return nil
        }
    }
}

/// What `findCloudflaredBinary()` returned, plus enough context to
/// decide whether we need to chmod it. Bundled binaries we own and may
/// chmod; system binaries (Homebrew, $PATH) we leave alone.
private struct ResolvedBinary {
    let url: URL
    let source: String
    let needsChmod: Bool
}

enum CloudflaredError: Error {
    case binaryNotFound
    case urlAcquisitionTimeout
    case processExited(Int32)
}
