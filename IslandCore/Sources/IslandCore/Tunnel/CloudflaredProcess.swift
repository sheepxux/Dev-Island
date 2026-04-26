import Foundation

actor CloudflaredProcess {
    private var process: Process?
    private let urlAcquisitionTimeout: TimeInterval = 30

    var isRunning: Bool {
        process?.isRunning ?? false
    }

    /// Start the cloudflared tunnel and return the public URL once it becomes available.
    func start() async throws -> URL {
        let binaryURL = try findCloudflaredBinary()
        try ensureExecutable(at: binaryURL)

        let proc = Process()
        proc.executableURL = binaryURL
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

    func stop() {
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

    private func findCloudflaredBinary() throws -> URL {
        guard let url = Bundle.module.url(forResource: "cloudflared", withExtension: nil) else {
            throw CloudflaredError.binaryNotFound
        }
        return url
    }

    private func ensureExecutable(at url: URL) throws {
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: url.path
        )
    }
}

enum CloudflaredError: Error {
    case binaryNotFound
    case urlAcquisitionTimeout
    case processExited(Int32)
}
