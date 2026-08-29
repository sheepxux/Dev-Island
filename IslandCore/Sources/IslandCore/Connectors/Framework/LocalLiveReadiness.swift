import Darwin
import Dispatch
import Foundation

/// Whether an installed local Agent CLI matches the exact version used for
/// Dev Island's current real-protocol review. A newer or older executable is
/// not called incompatible: it is held at review-required until the same
/// acceptance checklist has been repeated against that version.
public enum LocalAgentCLIReadinessState: String, Equatable, Sendable {
    case verified
    case reviewRequired = "review-required"
    case checkFailed = "check-failed"
    case unavailable
}

/// Vendor-owned activation gates are separate from managed config bytes.
public enum LocalAgentActivationReadinessState: String, Equatable, Sendable {
    case notRequired = "not-required"
    case verified
    case reviewRequired = "review-required"
}

/// A challenge-response check of the running App's loopback Hook listener.
public enum LocalHookListenerReadinessState: String, Equatable, Sendable {
    case listening
    case unavailable
}

/// Privacy-safe readiness for one shipping bidirectional local Agent.
public struct LocalAgentLiveReadiness: Equatable, Sendable {
    public let source: String
    public let cli: LocalAgentCLIReadinessState
    public let hook: LocalAgentHookConnectionState
    public let activation: LocalAgentActivationReadinessState

    public init(
        source: String,
        cli: LocalAgentCLIReadinessState,
        hook: LocalAgentHookConnectionState,
        activation: LocalAgentActivationReadinessState
    ) {
        self.source = source
        self.cli = cli
        self.hook = hook
        self.activation = activation
    }

    public var isReady: Bool {
        cli == .verified
            && hook == .connected
            && activation != .reviewRequired
    }
}

/// One read-only report for the two shipping integrations whose synchronous
/// decisions can be completed inside Dev Island. No path, Hook definition,
/// process output, session, prompt, or identifier crosses this model.
public struct LocalLiveReadinessSnapshot: Equatable, Sendable {
    public let listener: LocalHookListenerReadinessState
    public let agents: [LocalAgentLiveReadiness]

    public init(
        listener: LocalHookListenerReadinessState,
        agents: [LocalAgentLiveReadiness]
    ) {
        self.listener = listener
        self.agents = agents
    }

    public var readyAgentCount: Int {
        guard listener == .listening else { return 0 }
        return agents.count(where: \.isReady)
    }

    public var isReady: Bool {
        listener == .listening
            && !agents.isEmpty
            && agents.allSatisfy(\.isReady)
    }
}

/// External listener proof used only by the explicit diagnostic CLI. The
/// challenge is sent in a non-simple header and the server rejects `Origin`,
/// so a web page cannot use the endpoint as a localhost software oracle.
public struct LocalHookListenerReadinessProbe: Sendable {
    static let endpointPath = "/_dev-island/readiness-v1"
    static let challengeHeader = "X-Dev-Island-Readiness-Challenge"
    static let responsePrefix = "dev-island-local-hooks-v1:"

    private let port: Int
    private let timeout: TimeInterval

    public init(
        port: Int = LocalHooksInstaller.defaultPort,
        timeout: TimeInterval = 0.35
    ) {
        self.port = port
        self.timeout = timeout
    }

    public func probe() async -> LocalHookListenerReadinessState {
        guard 1...65_535 ~= port,
              timeout.isFinite,
              0.05...2 ~= timeout,
              let url = URL(string: "http://127.0.0.1:\(port)\(Self.endpointPath)")
        else { return .unavailable }

        let challenge = UUID().uuidString.lowercased()
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue(challenge, forHTTPHeaderField: Self.challengeHeader)
        request.setValue("0", forHTTPHeaderField: "Content-Length")

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        configuration.connectionProxyDictionary = [:]
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }

        do {
            let (data, response) = try await session.data(for: request)
            let expected = Data(Self.response(for: challenge).utf8)
            return (response as? HTTPURLResponse)?.statusCode == 200 && data == expected
                ? .listening
                : .unavailable
        } catch {
            return .unavailable
        }
    }

    static func isValid(challenge: String) -> Bool {
        challenge.utf8.count == 36 && UUID(uuidString: challenge) != nil
    }

    static func response(for challenge: String) -> String {
        responsePrefix + challenge.lowercased()
    }
}

/// Explicit, read-only preflight for a real Claude Code + Codex acceptance
/// run. It never installs or repairs Hooks and never launches an Agent
/// session. The only vendor subprocesses are `claude --version` at a known
/// local installation path and the already bounded OpenAI-signed Codex probes.
public struct LocalLiveReadinessProbe: Sendable {
    public static let verifiedClaudeCodeVersion = "2.1.197"
    public static let verifiedCodexVersion = "0.149.0-alpha.4.3"

    public init() {}

    public func snapshot() async -> LocalLiveReadinessSnapshot {
        let descriptors: [LocalAgentDescriptor] = [.claudeCode, .codex]
        let baseHooks = LocalAgentHookDiagnostics.snapshot(
            descriptors: descriptors,
            configURLsBySource: [:]
        )
        let codexBaseState = baseHooks.agents.first(where: { $0.source == "codex" })?.state

        let codexActivation: LocalAgentActivationReadinessState
        if codexBaseState == .configured,
           CodexHookTrustProbe().probeCurrentInstall() == .verified {
            codexActivation = .verified
        } else {
            codexActivation = .reviewRequired
        }

        let verifiedActivationSources: Set<String> = codexActivation == .verified
            ? ["codex"]
            : []
        let hooks = LocalAgentHookDiagnostics.snapshot(
            descriptors: descriptors,
            configURLsBySource: [:],
            verifiedActivatedSources: verifiedActivationSources
        )

        let claudeCLI = LocalCLIVersionProbe.probe(
            executableURL: LocalCLIVersionProbe.claudeExecutableURL(),
            expectedVersion: Self.verifiedClaudeCodeVersion
        )
        let codexCLI = LocalCLIVersionProbe.probe(
            executableURL: CodexHookTrustProbe.verifiedCodexExecutable(),
            expectedVersion: Self.verifiedCodexVersion
        )
        let listener = await LocalHookListenerReadinessProbe().probe()

        return Self.evaluate(
            listener: listener,
            cliStates: [
                "claude-code": claudeCLI,
                "codex": codexCLI,
            ],
            hooks: hooks,
            codexActivation: codexActivation
        )
    }

    static func evaluate(
        listener: LocalHookListenerReadinessState,
        cliStates: [String: LocalAgentCLIReadinessState],
        hooks: LocalAgentHookHealthSnapshot,
        codexActivation: LocalAgentActivationReadinessState
    ) -> LocalLiveReadinessSnapshot {
        let agents = ["claude-code", "codex"].map { source in
            LocalAgentLiveReadiness(
                source: source,
                cli: cliStates[source] ?? .unavailable,
                hook: hooks.agents.first(where: { $0.source == source })?.state ?? .disconnected,
                activation: source == "codex" ? codexActivation : .notRequired
            )
        }
        return LocalLiveReadinessSnapshot(listener: listener, agents: agents)
    }
}

/// Bounded low-cardinality version check. Raw stdout never leaves this type;
/// stderr is discarded, output is capped, and a hanging process is killed.
enum LocalCLIVersionProbe {
    static let outputLimitBytes = 4 * 1_024
    static let defaultTimeout: TimeInterval = 2

    static func claudeExecutableURL(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL? {
        let candidates = [
            homeDirectory.appendingPathComponent(".local/npm/bin/claude"),
            homeDirectory.appendingPathComponent(".local/bin/claude"),
            homeDirectory.appendingPathComponent(".claude/local/claude"),
            URL(fileURLWithPath: "/opt/homebrew/bin/claude"),
            URL(fileURLWithPath: "/usr/local/bin/claude"),
        ]
        return candidates.first {
            FileManager.default.isExecutableFile(atPath: $0.path)
        }
    }

    static func probe(
        executableURL: URL?,
        expectedVersion: String,
        timeout: TimeInterval = defaultTimeout
    ) -> LocalAgentCLIReadinessState {
        guard let executableURL,
              executableURL.isFileURL,
              executableURL.path.hasPrefix("/"),
              FileManager.default.isExecutableFile(atPath: executableURL.path)
        else { return .unavailable }
        guard timeout.isFinite,
              0.05...5 ~= timeout,
              versionToken(from: Data(expectedVersion.utf8)) == expectedVersion
        else { return .checkFailed }

        guard var result = BoundedChildProcess.run(
            executableURL: executableURL,
            arguments: ["--version"],
            environment: childEnvironment(executableURL: executableURL),
            outputLimit: outputLimitBytes,
            timeout: timeout
        ) else { return .checkFailed }
        defer {
            result.output.resetBytes(in: result.output.indices)
            result.output.removeAll(keepingCapacity: false)
        }

        guard !result.timedOut,
              !result.exceededOutputLimit,
              result.exitCode == 0
        else { return .checkFailed }
        return compatibilityState(
            output: result.output,
            expectedVersion: expectedVersion
        )
    }

    static func compatibilityState(
        output: Data,
        expectedVersion: String
    ) -> LocalAgentCLIReadinessState {
        guard output.count <= outputLimitBytes,
              versionToken(from: Data(expectedVersion.utf8)) == expectedVersion
        else { return .checkFailed }
        return versionToken(from: output) == expectedVersion ? .verified : .reviewRequired
    }

    static func versionToken(from data: Data) -> String? {
        guard !data.isEmpty,
              data.count <= outputLimitBytes,
              let text = String(data: data, encoding: .utf8) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let pattern = #"(?<![0-9A-Za-z.-])([0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?)(?![0-9A-Za-z.-])"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges == 2,
              let tokenRange = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[tokenRange])
    }

    private static func childEnvironment(executableURL: URL) -> [String: String] {
        let executableDirectory = executableURL.deletingLastPathComponent().path
        return [
            "HOME": FileManager.default.homeDirectoryForCurrentUser.path,
            "PATH": "\(executableDirectory):/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
            "TMPDIR": FileManager.default.temporaryDirectory.path,
            "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": "1",
            "DISABLE_AUTOUPDATER": "1",
        ]
    }
}
