import Darwin
import Foundation
import XCTest
@testable import IslandCore

final class LocalHookServerHealthTests: XCTestCase {

    func testPrivateReadinessProbeProvesThisProcessOwnsThePort() async throws {
        let port = try availableLoopbackPort()
        let probe = HookStatusProbe()
        let server = makeLocalHookServer(port: port)

        await server.start(
            agents: [.geminiCLI],
            onStatusChange: { status in
                Task { await probe.record(status) }
            },
            onEvent: { _, _ in }
        )

        do {
            try await waitUntil(timeout: 2) {
                await probe.contains(.listening)
            }
            let status = await server.statusSnapshot()
            XCTAssertEqual(status, .listening)
        } catch {
            await server.stop()
            throw error
        }

        await server.stop()
        let stopped = await server.statusSnapshot()
        XCTAssertEqual(stopped, .stopped)
    }

    func testExternalReadinessChallengeProvesTheRunningAppListener() async throws {
        let port = try availableLoopbackPort()
        let probe = HookStatusProbe()
        let server = makeLocalHookServer(port: port)

        await server.start(
            agents: [.claudeCode, .codex],
            onStatusChange: { status in
                Task { await probe.record(status) }
            },
            onEvent: { _, _ in }
        )

        do {
            try await waitUntil(timeout: 2) {
                await probe.contains(.listening)
            }
            let liveState = await LocalHookListenerReadinessProbe(port: port).probe()
            XCTAssertEqual(liveState, .listening)
        } catch {
            await server.stop()
            throw error
        }

        await server.stop()
        let stoppedState = await LocalHookListenerReadinessProbe(port: port).probe()
        XCTAssertEqual(stoppedState, .unavailable)
    }

    func testExternalReadinessRejectsBrowserOrigin() async throws {
        let port = try availableLoopbackPort()
        let probe = HookStatusProbe()
        let server = makeLocalHookServer(port: port)

        await server.start(
            agents: [.codex],
            onStatusChange: { status in
                Task { await probe.record(status) }
            },
            onEvent: { _, _ in }
        )

        do {
            try await waitUntil(timeout: 2) {
                await probe.contains(.listening)
            }
            let challenge = UUID().uuidString.lowercased()
            let url = try XCTUnwrap(
                URL(string: "http://127.0.0.1:\(port)\(LocalHookListenerReadinessProbe.endpointPath)")
            )
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue(
                challenge,
                forHTTPHeaderField: LocalHookListenerReadinessProbe.challengeHeader
            )
            request.setValue("https://example.invalid", forHTTPHeaderField: "Origin")
            let configuration = URLSessionConfiguration.ephemeral
            configuration.connectionProxyDictionary = [:]
            let session = URLSession(configuration: configuration)
            defer { session.invalidateAndCancel() }
            let (data, _) = try await session.data(for: request)

            XCTAssertNotEqual(
                data,
                Data(LocalHookListenerReadinessProbe.response(for: challenge).utf8)
            )
        } catch {
            await server.stop()
            throw error
        }

        await server.stop()
    }

    func testOccupiedPortReportsRetryingWithoutFalseReady() async throws {
        let occupied = try OccupiedLoopbackPort()
        let probe = HookStatusProbe()
        let server = makeLocalHookServer(port: occupied.port)

        await server.start(
            agents: [.geminiCLI],
            onStatusChange: { status in
                Task { await probe.record(status) }
            },
            onEvent: { _, _ in }
        )

        do {
            try await waitUntil(timeout: 2) {
                await probe.containsRetrying
            }
            let reportedReady = await probe.contains(.listening)
            XCTAssertFalse(reportedReady)
            let status = await server.statusSnapshot()
            guard case .retrying(let attempt, let limit) = status else {
                return XCTFail("expected retrying, got \(status)")
            }
            XCTAssertEqual(attempt, 1)
            XCTAssertEqual(limit, 5)
        } catch {
            await server.stop()
            throw error
        }

        await server.stop()
        occupied.release()
    }

    func testManualRestartRecoversImmediatelyAfterPortIsReleased() async throws {
        let occupied = try OccupiedLoopbackPort()
        let probe = HookStatusProbe()
        let server = makeLocalHookServer(port: occupied.port)

        await server.start(
            agents: [.codex],
            onStatusChange: { status in
                Task { await probe.record(status) }
            },
            onEvent: { _, _ in }
        )

        do {
            try await waitUntil(timeout: 2) {
                await probe.containsRetrying
            }
            occupied.release()
            await server.restart()
            try await waitUntil(timeout: 2) {
                await probe.contains(.listening)
            }
            let status = await server.statusSnapshot()
            XCTAssertEqual(status, .listening)
        } catch {
            await server.stop()
            occupied.release()
            throw error
        }

        await server.stop()
    }

    func testWakeHealthCheckRecoversAfterAutomaticRetriesAreExhausted() async throws {
        let occupied = try OccupiedLoopbackPort()
        let probe = HookStatusProbe()
        let server = makeLocalHookServer(
            port: occupied.port,
            retryPolicy: LocalHookServerRetryPolicy(
                maxConsecutiveFailures: 2,
                delayAfterFailure: { _ in .milliseconds(15) }
            )
        )

        await server.start(
            agents: [.codex],
            onStatusChange: { status in
                Task { await probe.record(status) }
            },
            onEvent: { _, _ in }
        )

        do {
            try await waitUntil(timeout: 2) {
                await probe.contains(.unavailable)
            }
            let unavailableStatus = await server.statusSnapshot()
            XCTAssertEqual(unavailableStatus, .unavailable)

            occupied.release()
            await server.ensureRunning()

            try await waitUntil(timeout: 2) {
                await probe.contains(.listening)
            }
            let recoveredStatus = await server.statusSnapshot()
            let retryLimits = await probe.retryLimits
            XCTAssertEqual(recoveredStatus, .listening)
            XCTAssertEqual(retryLimits, [2])
        } catch {
            await server.stop()
            occupied.release()
            throw error
        }

        await server.stop()
    }

    func testWakeHealthCheckDoesNotRestartHealthyListener() async throws {
        let port = try availableLoopbackPort()
        let probe = HookStatusProbe()
        let server = makeLocalHookServer(port: port)

        await server.start(
            agents: [.geminiCLI],
            onStatusChange: { status in
                Task { await probe.record(status) }
            },
            onEvent: { _, _ in }
        )

        do {
            try await waitUntil(timeout: 2) {
                await probe.contains(.listening)
            }
            let startingCount = await probe.count(of: .starting)

            await server.ensureRunning()
            try await Task.sleep(for: .milliseconds(100))

            let statusAfterHealthCheck = await server.statusSnapshot()
            let startingCountAfterHealthCheck = await probe.count(of: .starting)
            XCTAssertEqual(statusAfterHealthCheck, .listening)
            XCTAssertEqual(startingCountAfterHealthCheck, startingCount)
        } catch {
            await server.stop()
            throw error
        }

        await server.stop()
    }

    func testAuthorizationPreparationFailureNeverBindsTheHookListener() async throws {
        let port = try availableLoopbackPort()
        let server = LocalHookServer(
            port: port,
            retryPolicy: .production,
            authorizationProvider: {
                throw LocalHookAuthorizationStore.StoreError.randomGenerationFailed
            }
        )

        await server.start(agents: [.codex], onEvent: { _, _ in
            XCTFail("An unauthenticated listener must never deliver an event")
        })

        let status = await server.statusSnapshot()
        let readiness = await LocalHookListenerReadinessProbe(port: port).probe()
        XCTAssertEqual(status, .unavailable)
        XCTAssertEqual(readiness, .unavailable)
        await server.stop()
    }

    private func waitUntil(
        timeout: TimeInterval,
        condition: @escaping @Sendable () async -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        throw URLError(.timedOut)
    }

    private func availableLoopbackPort() throws -> Int {
        let fileDescriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard fileDescriptor >= 0 else { throw POSIXError(.EIO) }
        defer { Darwin.close(fileDescriptor) }

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = 0
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fileDescriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else { throw POSIXError(.EADDRINUSE) }

        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let nameResult = withUnsafeMutablePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(fileDescriptor, $0, &length)
            }
        }
        guard nameResult == 0 else { throw POSIXError(.EIO) }
        return Int(UInt16(bigEndian: address.sin_port))
    }
}

private actor HookStatusProbe {
    private var statuses: [LocalHookServiceStatus] = []

    func record(_ status: LocalHookServiceStatus) {
        statuses.append(status)
    }

    func contains(_ expected: LocalHookServiceStatus) -> Bool {
        statuses.contains(expected)
    }

    func count(of expected: LocalHookServiceStatus) -> Int {
        statuses.count(where: { $0 == expected })
    }

    var retryLimits: [Int] {
        statuses.compactMap { status in
            guard case .retrying(_, let limit) = status else { return nil }
            return limit
        }
    }

    var containsRetrying: Bool {
        statuses.contains { status in
            if case .retrying = status { return true }
            return false
        }
    }
}

private final class OccupiedLoopbackPort: @unchecked Sendable {
    private var fileDescriptor: Int32
    let port: Int

    init() throws {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw POSIXError(.EIO) }

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = 0
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0, Darwin.listen(descriptor, 1) == 0 else {
            Darwin.close(descriptor)
            throw POSIXError(.EADDRINUSE)
        }

        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let nameResult = withUnsafeMutablePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(descriptor, $0, &length)
            }
        }
        guard nameResult == 0 else {
            Darwin.close(descriptor)
            throw POSIXError(.EIO)
        }

        fileDescriptor = descriptor
        port = Int(UInt16(bigEndian: address.sin_port))
    }

    func release() {
        guard fileDescriptor >= 0 else { return }
        Darwin.close(fileDescriptor)
        fileDescriptor = -1
    }

    deinit {
        release()
    }
}
