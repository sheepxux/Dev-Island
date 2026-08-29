import Darwin
import Foundation
import XCTest
@testable import IslandCore

final class LocalLiveReadinessTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("dev-island-live-readiness-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryDirectory)
        temporaryDirectory = nil
    }

    func testPinnedClaudeAndCodexVersionOutputsVerifyExactly() {
        XCTAssertEqual(
            LocalCLIVersionProbe.compatibilityState(
                output: Data("2.1.197 (Claude Code)\n".utf8),
                expectedVersion: LocalLiveReadinessProbe.verifiedClaudeCodeVersion
            ),
            .verified
        )
        XCTAssertEqual(
            LocalCLIVersionProbe.compatibilityState(
                output: Data("codex-cli 0.149.0-alpha.4.3\n".utf8),
                expectedVersion: LocalLiveReadinessProbe.verifiedCodexVersion
            ),
            .verified
        )
    }

    func testVersionDriftAndMalformedOutputRequireReview() {
        for output in [
            Data("2.1.198 (Claude Code)\n".utf8),
            Data("no semantic version\n".utf8),
        ] {
            XCTAssertEqual(
                LocalCLIVersionProbe.compatibilityState(
                    output: output,
                    expectedVersion: LocalLiveReadinessProbe.verifiedClaudeCodeVersion
                ),
                .reviewRequired
            )
        }
    }

    func testOversizedCompatibilityOutputIsAFailedCheck() {
        XCTAssertEqual(
            LocalCLIVersionProbe.compatibilityState(
                output: Data(
                    repeating: 0x31,
                    count: LocalCLIVersionProbe.outputLimitBytes + 1
                ),
                expectedVersion: LocalLiveReadinessProbe.verifiedClaudeCodeVersion
            ),
            .checkFailed
        )
    }

    func testProductionVersionProbeTimeoutRemainsTwoSeconds() {
        XCTAssertEqual(LocalCLIVersionProbe.defaultTimeout, 2)
    }

    func testBoundedVersionProcessVerifiesExactOutput() throws {
        let executable = try makeExecutable(
            "#!/bin/sh\nprintf '2.1.197 (Claude Code)\\n'\n"
        )

        let started = Date()
        XCTAssertEqual(
            LocalCLIVersionProbe.probe(
                executableURL: executable,
                expectedVersion: LocalLiveReadinessProbe.verifiedClaudeCodeVersion,
                timeout: 5
            ),
            .verified
        )
        XCTAssertLessThan(Date().timeIntervalSince(started), 5.5)
    }

    func testRepeatedFastVersionProcessesDoNotLoseTerminationOrOutput() throws {
        let executable = try makeExecutable(
            "#!/bin/sh\nprintf '2.1.197 (Claude Code)\\n'\n"
        )
        let started = Date()

        // This test protects the fast-exit stdout/waitpid race, not the
        // scheduler's ability to launch twelve new processes inside 500 ms
        // each. On a loaded Mac, an unrelated daemon can hold a core long
        // enough for even a 1.5-second per-process deadline to expire although
        // the child is correct. Give this race test a wide isolation budget;
        // the separate hanging-process tests keep the hard timeout/kill
        // contract at 50 ms and the production probe remains capped at 2 s.
        for iteration in 0..<12 {
            XCTAssertEqual(
                LocalCLIVersionProbe.probe(
                    executableURL: executable,
                    expectedVersion: LocalLiveReadinessProbe.verifiedClaudeCodeVersion,
                    timeout: 5
                ),
                .verified,
                "Fast version probe failed at iteration \(iteration)"
            )
        }
        XCTAssertLessThan(Date().timeIntervalSince(started), 15)
    }

    func testHangingVersionProcessIsKilledAndReportsFailedCheck() throws {
        let executable = try makeExecutable("#!/bin/sh\n/bin/sleep 5\n")
        let started = Date()

        XCTAssertEqual(
            LocalCLIVersionProbe.probe(
                executableURL: executable,
                expectedVersion: LocalLiveReadinessProbe.verifiedClaudeCodeVersion,
                timeout: 0.05
            ),
            .checkFailed
        )
        XCTAssertLessThan(Date().timeIntervalSince(started), 1.5)
    }

    func testTermIgnoringVersionProcessIsKilledAtBoundedDeadline() throws {
        let executable = try makeExecutable(
            "#!/bin/sh\ntrap '' TERM\nwhile :; do /bin/sleep 1; done\n"
        )
        let started = Date()

        XCTAssertEqual(
            LocalCLIVersionProbe.probe(
                executableURL: executable,
                expectedVersion: LocalLiveReadinessProbe.verifiedClaudeCodeVersion,
                timeout: 0.05
            ),
            .checkFailed
        )
        XCTAssertLessThan(Date().timeIntervalSince(started), 1.5)
    }

    func testVersionProcessRequiresZeroExitEvenWithExactOutput() throws {
        let executable = try makeExecutable(
            "#!/bin/sh\nprintf '2.1.197 (Claude Code)\\n'\nexit 7\n"
        )

        XCTAssertEqual(
            LocalCLIVersionProbe.probe(
                executableURL: executable,
                expectedVersion: LocalLiveReadinessProbe.verifiedClaudeCodeVersion
            ),
            .checkFailed
        )
    }

    func testVersionProcessRejectsOversizedOutputWithoutDeadlock() throws {
        let executable = try makeExecutable(
            "#!/bin/sh\n/usr/bin/head -c 8192 /dev/zero\n"
        )
        let started = Date()

        XCTAssertEqual(
            LocalCLIVersionProbe.probe(
                executableURL: executable,
                expectedVersion: LocalLiveReadinessProbe.verifiedClaudeCodeVersion,
                timeout: 5
            ),
            .checkFailed
        )
        // This proves that an unbounded producer is drained and terminated,
        // not that a newly spawned fixture receives CPU within 1.5 seconds.
        // Production remains locked to two seconds by the dedicated default
        // timeout regression above.
        XCTAssertLessThan(Date().timeIntervalSince(started), 5.5)
    }

    func testTransientExecutionFailuresNeverClaimCompatibilityReview() {
        let state = LocalCLIVersionProbe.probe(
            executableURL: URL(fileURLWithPath: "/usr/bin/false"),
            expectedVersion: LocalLiveReadinessProbe.verifiedClaudeCodeVersion,
            timeout: 5
        )

        XCTAssertEqual(state, .checkFailed)
        XCTAssertNotEqual(state, .reviewRequired)
    }

    func testSnapshotRequiresListenerCLIHooksAndVendorActivation() {
        let configuredHooks = LocalAgentHookHealthSnapshot(agents: [
            LocalAgentHookConnection(
                source: "claude-code",
                displayName: "Claude Code",
                state: .connected
            ),
            LocalAgentHookConnection(
                source: "codex",
                displayName: "Codex",
                state: .configured
            ),
        ])
        let snapshot = LocalLiveReadinessProbe.evaluate(
            listener: .listening,
            cliStates: ["claude-code": .verified, "codex": .verified],
            hooks: configuredHooks,
            codexActivation: .reviewRequired
        )

        XCTAssertEqual(snapshot.readyAgentCount, 1)
        XCTAssertFalse(snapshot.isReady)
        XCTAssertEqual(snapshot.agents.map(\.activation), [.notRequired, .reviewRequired])
    }

    func testFullyVerifiedSnapshotIsReadyForBothLiveSessions() {
        let connectedHooks = LocalAgentHookHealthSnapshot(agents: [
            LocalAgentHookConnection(
                source: "claude-code",
                displayName: "Claude Code",
                state: .connected
            ),
            LocalAgentHookConnection(
                source: "codex",
                displayName: "Codex",
                state: .connected
            ),
        ])
        let snapshot = LocalLiveReadinessProbe.evaluate(
            listener: .listening,
            cliStates: ["claude-code": .verified, "codex": .verified],
            hooks: connectedHooks,
            codexActivation: .verified
        )

        XCTAssertEqual(snapshot.readyAgentCount, 2)
        XCTAssertTrue(snapshot.isReady)
        XCTAssertTrue(snapshot.agents.allSatisfy(\.isReady))
    }

    func testStoppedAppForcesReadyAgentCountToZero() {
        let hooks = LocalAgentHookHealthSnapshot(agents: [
            LocalAgentHookConnection(
                source: "claude-code",
                displayName: "Claude Code",
                state: .connected
            ),
            LocalAgentHookConnection(
                source: "codex",
                displayName: "Codex",
                state: .connected
            ),
        ])
        let snapshot = LocalLiveReadinessProbe.evaluate(
            listener: .unavailable,
            cliStates: ["claude-code": .verified, "codex": .verified],
            hooks: hooks,
            codexActivation: .verified
        )

        XCTAssertEqual(snapshot.readyAgentCount, 0)
        XCTAssertFalse(snapshot.isReady)
    }

    func testHermeticListenerHarnessVerifiesChallengeAndCleanShutdown() async throws {
        let port = try availableLoopbackPort()
        let state = await HermeticLocalListenerReadinessHarness(timeout: 2).run(port: port)
        let stoppedState = await LocalHookListenerReadinessProbe(port: port).probe()

        XCTAssertEqual(state, .verified)
        XCTAssertEqual(stoppedState, .unavailable)
    }

    func testEphemeralListenerAuthorizationIsRandomAndMemoryOnly() throws {
        let first = try LocalHookAuthorizationStore.makeEphemeralAuthorization()
        let second = try LocalHookAuthorizationStore.makeEphemeralAuthorization()

        XCTAssertNotEqual(first.headerValue, second.headerValue)
        XCTAssertTrue(first.matches(first.headerValue))
        XCTAssertTrue(second.matches(second.headerValue))
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

    private func makeExecutable(_ source: String) throws -> URL {
        let url = temporaryDirectory.appendingPathComponent("probe-\(UUID().uuidString).sh")
        try Data(source.utf8).write(to: url)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: url.path
        )
        return url
    }
}
