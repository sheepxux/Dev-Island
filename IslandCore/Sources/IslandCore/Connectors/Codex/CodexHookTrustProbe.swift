import Darwin
import Foundation
import Security

enum CodexHookTrustProbeOutcome: String, Equatable, Sendable {
    case unavailable
    case launchFailed
    case timedOut
    case invalidResponse
    case verified
}

/// Read-only proof that Codex will actually run every Dev Island Hook.
///
/// A matching `~/.codex/hooks.json` is necessary but not sufficient: Codex
/// separately enables and trusts each non-managed definition by its current
/// hash. The official App Server `hooks/list` method is the only documented
/// source used here. Failure is conservative and returns `false`; this type
/// never writes config, trusts a Hook, starts a thread, or logs server output.
struct CodexHookTrustProbe: Sendable {
    static let requestID = 1
    static let responseLimitBytes = 2 * 1_024 * 1_024
    static let defaultTimeout: TimeInterval = 3

    private static let codexBundleIdentifier = "com.openai.codex"
    private static let openAITeamIdentifier = "2DC432GLL2"

    private let executableURL: URL?

    init() {
        executableURL = Self.verifiedCodexExecutable()
    }

    /// Injection is intentionally internal and bypasses bundle discovery only
    /// for deterministic protocol/process tests.
    init(executableURL: URL) {
        self.executableURL = executableURL
    }

    func verifiesCurrentInstall(
        descriptor: LocalAgentDescriptor = .codex,
        cwd: URL = FileManager.default.homeDirectoryForCurrentUser,
        timeout: TimeInterval = Self.defaultTimeout
    ) -> Bool {
        probeCurrentInstall(
            descriptor: descriptor,
            cwd: cwd,
            timeout: timeout
        ) == .verified
    }

    /// Low-cardinality outcome for deterministic tests. No command, path, Hook
    /// metadata, or App Server output leaves the process through this value.
    func probeCurrentInstall(
        descriptor: LocalAgentDescriptor = .codex,
        cwd: URL = FileManager.default.homeDirectoryForCurrentUser,
        timeout: TimeInterval = Self.defaultTimeout
    ) -> CodexHookTrustProbeOutcome {
        guard descriptor.source == "codex",
              timeout.isFinite,
              timeout > 0,
              timeout <= 10,
              cwd.isFileURL,
              cwd.path.hasPrefix("/"),
              let executableURL,
              FileManager.default.isExecutableFile(atPath: executableURL.path)
        else { return .unavailable }

        guard var request = try? requestBytes(cwd: cwd) else {
            return .launchFailed
        }
        defer { request.resetBytes(in: request.indices) }

        let collector = CodexAppServerResponseCollector(
            requestID: Self.requestID
        )
        defer { collector.erase() }

        guard let completion = BoundedStdioChildProcess.requestResponse(
            executableURL: executableURL,
            arguments: ["app-server", "--stdio"],
            environment: Self.childEnvironment(),
            currentDirectoryURL: cwd,
            input: request,
            outputLimit: Self.responseLimitBytes,
            timeout: timeout,
            responseFromChunk: { collector.append($0) }
        ) else { return .launchFailed }

        let responseData: Data
        switch completion {
        case .response(let response):
            responseData = response
        case .timedOut:
            return .timedOut
        case .exitedWithoutResponse, .exceededOutputLimit, .ioFailure:
            return .invalidResponse
        }

        var response = responseData
        defer { response.resetBytes(in: response.indices) }

        return Self.responseVerifiesExpectedHooks(
            response,
            descriptor: descriptor,
            configURL: descriptor.configURL
        ) ? .verified : .invalidResponse
    }

    static func responseVerifiesExpectedHooks(
        _ data: Data,
        descriptor: LocalAgentDescriptor = .codex,
        configURL: URL? = nil
    ) -> Bool {
        guard descriptor.source == "codex",
              data.count <= responseLimitBytes,
              let envelope = try? JSONDecoder().decode(HooksListEnvelope.self, from: data),
              envelope.id == requestID,
              let result = envelope.result,
              result.data.allSatisfy({ $0.errors.isEmpty })
        else { return false }

        let expectedPath = (configURL ?? descriptor.configURL).standardizedFileURL.path
        let installer = LocalHooksInstaller(descriptor)
        let allHooks = result.data.flatMap(\.hooks)

        for event in descriptor.hookEvents {
            let expectedEvent = protocolEventName(event)
            let expectedCommand = installer.hookCommand(for: event)
            let matches = allHooks.filter { hook in
                hook.handlerType == "command"
                    && hook.eventName == expectedEvent
                    && hook.command == expectedCommand
                    && URL(fileURLWithPath: hook.sourcePath).standardizedFileURL.path == expectedPath
            }
            guard !matches.isEmpty,
                  matches.allSatisfy({ hook in
                      hook.enabled && (hook.trustStatus == "trusted" || hook.trustStatus == "managed")
                  }) else { return false }
        }
        return true
    }

    private func requestBytes(cwd: URL) throws -> Data {
        let messages: [[String: Any]] = [
            [
                "method": "initialize",
                "id": 0,
                "params": [
                    "clientInfo": [
                        "name": "dev_island",
                        "title": "Dev Island",
                        "version": "0.3.0",
                    ],
                ],
            ],
            ["method": "initialized", "params": [:]],
            [
                "method": "hooks/list",
                "id": Self.requestID,
                "params": ["cwds": [cwd.standardizedFileURL.path]],
            ],
        ]
        var bytes = Data()
        for message in messages {
            bytes.append(try JSONSerialization.data(withJSONObject: message))
            bytes.append(0x0A)
        }
        return bytes
    }

    private static func protocolEventName(_ event: String) -> String {
        guard let first = event.first else { return event }
        return first.lowercased() + event.dropFirst()
    }

    /// Only execute the OpenAI-signed binary embedded in the official Codex
    /// application. PATH and user-writable package-manager shims are excluded
    /// from this automatic probe so config contents can never be sent to an
    /// arbitrary executable named `codex`.
    /// Shared with the explicit local-live-readiness CLI. Keeping discovery
    /// here ensures the version check and Hook trust check use the same
    /// OpenAI-signed executable rather than a PATH or package-manager shim.
    static func verifiedCodexExecutable() -> URL? {
        let applicationRoots = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Applications", isDirectory: true),
        ]
        for root in applicationRoots {
            for name in ["ChatGPT.app", "Codex.app"] {
                let bundleURL = root.appendingPathComponent(name, isDirectory: true)
                let executable = bundleURL.appendingPathComponent("Contents/Resources/codex")
                guard Bundle(url: bundleURL)?.bundleIdentifier == codexBundleIdentifier,
                      FileManager.default.isExecutableFile(atPath: executable.path),
                      hasExpectedSignature(bundleURL) else { continue }
                return executable
            }
        }
        return nil
    }

    private static func hasExpectedSignature(_ bundleURL: URL) -> Bool {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(bundleURL as CFURL, [], &code) == errSecSuccess,
              let code else { return false }

        let requirementText = #"anchor apple generic and identifier "\#(codexBundleIdentifier)" and certificate leaf[subject.OU] = "\#(openAITeamIdentifier)""#
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(
            requirementText as CFString,
            [],
            &requirement
        ) == errSecSuccess,
        let requirement else { return false }

        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures)
        return SecStaticCodeCheckValidity(code, flags, requirement) == errSecSuccess
    }

    private static func childEnvironment() -> [String: String] {
        var environment = [
            "HOME": FileManager.default.homeDirectoryForCurrentUser.path,
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
            "TMPDIR": FileManager.default.temporaryDirectory.path,
        ]
        if let language = safeEnvironmentValue(ProcessInfo.processInfo.environment["LANG"]) {
            environment["LANG"] = language
        }
        if let locale = safeEnvironmentValue(ProcessInfo.processInfo.environment["LC_ALL"]) {
            environment["LC_ALL"] = locale
        }
        return environment
    }

    private static func safeEnvironmentValue(_ value: String?) -> String? {
        guard let value, !value.isEmpty,
              !value.contains("\n"), !value.contains("\r"),
              value.utf8.count <= 256 else { return nil }
        return value
    }
}

private final class CodexAppServerResponseCollector: @unchecked Sendable {
    private let requestID: Int
    private var buffered = Data()

    init(requestID: Int) {
        self.requestID = requestID
    }

    func append(_ data: Data) -> Data? {
        guard !data.isEmpty else { return nil }
        buffered.append(data)

        while let newline = buffered.firstIndex(of: 0x0A) {
            let lineRange = buffered.startIndex..<newline
            var line = Data(count: lineRange.count)
            _ = line.withUnsafeMutableBytes { (destination: UnsafeMutableRawBufferPointer) in
                buffered.copyBytes(to: destination, from: lineRange)
            }
            buffered.resetBytes(in: buffered.startIndex...newline)
            buffered.removeSubrange(...newline)
            if line.last == 0x0D { line.removeLast() }
            if !line.isEmpty,
               let header = try? JSONDecoder().decode(ResponseHeader.self, from: line),
               header.id == requestID {
                return line
            }
            line.resetBytes(in: line.indices)
        }
        return nil
    }

    func erase() {
        buffered.resetBytes(in: buffered.indices)
        buffered.removeAll(keepingCapacity: false)
    }
}

private struct ResponseHeader: Decodable {
    let id: Int?
}

private struct HooksListEnvelope: Decodable {
    let id: Int
    let result: HooksListResult?
}

private struct HooksListResult: Decodable {
    let data: [HooksListEntry]
}

private struct HooksListEntry: Decodable {
    let hooks: [HookMetadata]
    let errors: [HookError]
}

private struct HookMetadata: Decodable {
    let eventName: String
    let handlerType: String
    let command: String?
    let sourcePath: String
    let enabled: Bool
    let trustStatus: String
}

private struct HookError: Decodable {}
