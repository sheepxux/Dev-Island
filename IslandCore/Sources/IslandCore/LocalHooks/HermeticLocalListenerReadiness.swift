import Darwin
import Foundation

/// Result of the explicit engineering-only loopback transport check.
public enum HermeticLocalListenerCheckState: String, Equatable, Sendable {
    case verified
    case unavailable
}

/// Starts the smallest possible Local Hook listener on an ephemeral port,
/// proves its challenge-response route, then proves that shutdown released
/// the route. The listener receives an in-memory random authorization value
/// and an empty Agent descriptor list, so it cannot read or rewrite managed
/// Hooks, the production authorization file, Keychain, SQLite, or tasks.
public struct HermeticLocalListenerReadinessHarness: Sendable {
    private let timeout: TimeInterval

    public init(timeout: TimeInterval = 3) {
        self.timeout = timeout
    }

    public func run() async -> HermeticLocalListenerCheckState {
        guard let port = Self.availableLoopbackPort() else { return .unavailable }
        return await run(port: port)
    }

    func run(port: Int) async -> HermeticLocalListenerCheckState {
        guard 1...65_535 ~= port,
              timeout.isFinite,
              0.5...10 ~= timeout,
              let authorization = try? LocalHookAuthorizationStore.makeEphemeralAuthorization()
        else { return .unavailable }

        let server = LocalHookServer(
            port: port,
            retryPolicy: LocalHookServerRetryPolicy(
                maxConsecutiveFailures: 1,
                delayAfterFailure: { _ in .zero }
            ),
            authorization: authorization,
            suppressFrameworkLogs: true
        )
        await server.start(agents: [], onEvent: { _, _ in })

        let probe = LocalHookListenerReadinessProbe(
            port: port,
            timeout: min(0.2, timeout)
        )
        let startupDeadline = Date().addingTimeInterval(timeout)
        var challengeVerified = false
        while Date() < startupDeadline {
            let status = await server.statusSnapshot()
            if status == .listening {
                challengeVerified = await probe.probe() == .listening
                break
            }
            if status == .unavailable { break }
            try? await Task.sleep(for: .milliseconds(20))
        }

        await server.stop()
        guard challengeVerified else { return .unavailable }

        // Cancellation is cooperative inside Hummingbird. Do not report a
        // clean harness until the externally visible challenge route is gone.
        let shutdownDeadline = Date().addingTimeInterval(timeout)
        while Date() < shutdownDeadline {
            if await probe.probe() == .unavailable { return .verified }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return .unavailable
    }

    private static func availableLoopbackPort() -> Int? {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return nil }
        defer { Darwin.close(descriptor) }

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = 0
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(
                    descriptor,
                    $0,
                    socklen_t(MemoryLayout<sockaddr_in>.size)
                )
            }
        }
        guard bindResult == 0 else { return nil }

        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let nameResult = withUnsafeMutablePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(descriptor, $0, &length)
            }
        }
        guard nameResult == 0 else { return nil }
        return Int(UInt16(bigEndian: address.sin_port))
    }
}
