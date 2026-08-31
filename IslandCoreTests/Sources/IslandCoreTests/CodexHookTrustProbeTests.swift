import Darwin
import Foundation
import XCTest
@testable import IslandCore

final class CodexHookTrustProbeTests: XCTestCase {
    /// Process-group fixtures must first receive a scheduler turn so they can
    /// publish the descendant PID that the assertion later proves was reaped.
    /// This isolated test budget does not change the production probe's
    /// three-second default or the dedicated 50 ms timeout regression.
    private let processFixtureSchedulingBudget: TimeInterval = 5
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("dev-island-codex-trust-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryDirectory)
        temporaryDirectory = nil
    }

    func testExactEnabledTrustedDefinitionsVerifyWhileUnrelatedHooksAreIgnored() throws {
        let data = try responseData(unrelatedHook: true)

        XCTAssertTrue(
            CodexHookTrustProbe.responseVerifiesExpectedHooks(
                data,
                configURL: fixtureConfigURL
            )
        )
    }

    func testEveryExpectedDefinitionMustBeEnabledAndTrustedOrManaged() throws {
        for trust in ["untrusted", "modified", "unknown"] {
            XCTAssertFalse(
                CodexHookTrustProbe.responseVerifiesExpectedHooks(
                    try responseData(overrides: ["PermissionRequest": (true, trust)]),
                    configURL: fixtureConfigURL
                ),
                trust
            )
        }
        XCTAssertFalse(
            CodexHookTrustProbe.responseVerifiesExpectedHooks(
                try responseData(overrides: ["PermissionRequest": (false, "trusted")]),
                configURL: fixtureConfigURL
            )
        )
        XCTAssertTrue(
            CodexHookTrustProbe.responseVerifiesExpectedHooks(
                try responseData(overrides: ["PermissionRequest": (true, "managed")]),
                configURL: fixtureConfigURL
            )
        )
    }

    func testMissingWrongCommandWrongPathAndDiscoveryErrorsFailClosed() throws {
        XCTAssertFalse(
            CodexHookTrustProbe.responseVerifiesExpectedHooks(
                try responseData(omitting: "Stop"),
                configURL: fixtureConfigURL
            )
        )
        XCTAssertFalse(
            CodexHookTrustProbe.responseVerifiesExpectedHooks(
                try responseData(wrongCommandFor: "SessionStart"),
                configURL: fixtureConfigURL
            )
        )
        XCTAssertFalse(
            CodexHookTrustProbe.responseVerifiesExpectedHooks(
                try responseData(sourcePath: "/tmp/not-dev-island-hooks.json"),
                configURL: fixtureConfigURL
            )
        )
        XCTAssertFalse(
            CodexHookTrustProbe.responseVerifiesExpectedHooks(
                try responseData(hasErrors: true),
                configURL: fixtureConfigURL
            )
        )
    }

    func testMalformedWrongIDAndOversizedResponsesFailClosed() throws {
        XCTAssertFalse(CodexHookTrustProbe.responseVerifiesExpectedHooks(Data("not-json".utf8)))

        var wrongID = try XCTUnwrap(
            JSONSerialization.jsonObject(with: responseData()) as? [String: Any]
        )
        wrongID["id"] = 99
        XCTAssertFalse(
            CodexHookTrustProbe.responseVerifiesExpectedHooks(
                try JSONSerialization.data(withJSONObject: wrongID),
                configURL: fixtureConfigURL
            )
        )

        let oversized = Data(
            repeating: 0x20,
            count: CodexHookTrustProbe.responseLimitBytes + 1
        )
        XCTAssertFalse(CodexHookTrustProbe.responseVerifiesExpectedHooks(oversized))
    }

    func testShortLivedProcessProbeAcceptsAValidResponse() throws {
        let responseURL = temporaryDirectory.appendingPathComponent("response.jsonl")
        let pidFile = temporaryDirectory.appendingPathComponent("response-child.pid")
        var response = try responseData(sourcePath: LocalAgentDescriptor.codex.configURL.path)
        XCTAssertTrue(
            CodexHookTrustProbe.responseVerifiesExpectedHooks(
                response,
                configURL: LocalAgentDescriptor.codex.configURL
            )
        )
        response.append(0x0A)
        try response.write(to: responseURL)

        let executable = try makeExecutable(
            """
            #!/bin/sh
            (
              trap '' TERM
              while :; do /bin/sleep 1; done
            ) &
            child=$!
            echo "$child" > '\(pidFile.path)'
            /bin/cat '\(responseURL.path)'
            wait "$child"
            """
        )
        defer { terminateFixtureProcess(at: pidFile) }
        let started = Date()
        XCTAssertEqual(
            CodexHookTrustProbe(executableURL: executable).probeCurrentInstall(
                cwd: temporaryDirectory,
                timeout: 5
            ),
            .verified
        )
        XCTAssertLessThan(Date().timeIntervalSince(started), 5.5)
        let pid = try readFixturePID(at: pidFile)
        XCTAssertTrue(waitForProcessExit(pid, timeout: 1))
    }

    func testSilentProcessIsTerminatedAtTheBoundedTimeout() throws {
        let executable = try makeExecutable("#!/bin/sh\n/bin/sleep 5\n")
        let started = Date()
        XCTAssertFalse(
            CodexHookTrustProbe(executableURL: executable).verifiesCurrentInstall(
                cwd: temporaryDirectory,
                timeout: 0.05
            )
        )
        XCTAssertLessThan(Date().timeIntervalSince(started), 1.5)
    }

    func testImmediateExitFailsWithoutWaitingForTheFullTimeout() throws {
        let executable = try makeExecutable("#!/bin/sh\nexit 0\n")
        let started = Date()

        XCTAssertEqual(
            CodexHookTrustProbe(executableURL: executable).probeCurrentInstall(
                cwd: temporaryDirectory,
                timeout: processFixtureSchedulingBudget
            ),
            .invalidResponse
        )
        XCTAssertLessThan(
            Date().timeIntervalSince(started),
            processFixtureSchedulingBudget + 0.5
        )
    }

    func testClosedChildStdinCannotTerminateTheProbeWithSIGPIPE() throws {
        let executable = try makeExecutable(
            """
            #!/bin/sh
            exec 0<&-
            echo closed
            /bin/sleep 0.2
            """
        )

        let completion = BoundedStdioChildProcess.requestResponse(
            executableURL: executable,
            arguments: [],
            environment: ["PATH": "/usr/bin:/bin", "TMPDIR": temporaryDirectory.path],
            currentDirectoryURL: temporaryDirectory,
            input: Data(repeating: 0x61, count: 64 * 1_024),
            outputLimit: 4 * 1_024,
            timeout: processFixtureSchedulingBudget,
            responseFromChunk: { _ in nil }
        )

        guard let completion else {
            return XCTFail("Expected a bounded child-process completion")
        }
        switch completion {
        case .ioFailure, .exitedWithoutResponse:
            break
        default:
            XCTFail(
                "A closed child stdin must fail locally without terminating "
                + "the test process; completion=\(String(describing: completion))"
            )
        }
    }

    func testTimeoutTerminatesTheCompleteProcessGroup() throws {
        let pidFile = temporaryDirectory.appendingPathComponent("timeout-child.pid")
        let executable = try makeExecutable(
            """
            #!/bin/sh
            (
              trap '' TERM
              while :; do /bin/sleep 1; done
            ) &
            child=$!
            echo "$child" > '\(pidFile.path)'
            echo ready
            wait "$child"
            """
        )
        defer { terminateFixtureProcess(at: pidFile) }

        XCTAssertEqual(
            CodexHookTrustProbe(executableURL: executable).probeCurrentInstall(
                cwd: temporaryDirectory,
                timeout: processFixtureSchedulingBudget
            ),
            .timedOut
        )

        let pid = try readFixturePID(at: pidFile)
        XCTAssertTrue(waitForProcessExit(pid, timeout: 1))
    }

    func testOversizedOutputFailsClosedAndTerminatesTheCompleteProcessGroup() throws {
        let pidFile = temporaryDirectory.appendingPathComponent("oversized-child.pid")
        let executable = try makeExecutable(
            """
            #!/bin/sh
            (
              trap '' TERM
              while :; do /bin/sleep 1; done
            ) &
            child=$!
            echo "$child" > '\(pidFile.path)'
            /bin/dd if=/dev/zero bs=4096 count=513 2>/dev/null
            wait "$child"
            """
        )
        defer { terminateFixtureProcess(at: pidFile) }

        XCTAssertEqual(
            CodexHookTrustProbe(executableURL: executable).probeCurrentInstall(
                cwd: temporaryDirectory,
                timeout: processFixtureSchedulingBudget
            ),
            .invalidResponse
        )

        let pid = try readFixturePID(at: pidFile)
        XCTAssertTrue(waitForProcessExit(pid, timeout: 1))
    }

    private var fixtureConfigURL: URL {
        temporaryDirectory.appendingPathComponent("hooks.json")
    }

    private func responseData(
        overrides: [String: (enabled: Bool, trust: String)] = [:],
        omitting omittedEvent: String? = nil,
        wrongCommandFor wrongCommandEvent: String? = nil,
        sourcePath: String? = nil,
        hasErrors: Bool = false,
        unrelatedHook: Bool = false
    ) throws -> Data {
        let descriptor = LocalAgentDescriptor.codex
        let installer = LocalHooksInstaller(descriptor)
        let path = sourcePath ?? fixtureConfigURL.path
        var hooks: [[String: Any]] = descriptor.hookEvents.compactMap { event in
            guard event != omittedEvent else { return nil }
            let state = overrides[event] ?? (true, "trusted")
            let command = event == wrongCommandEvent
                ? "different command"
                : installer.hookCommand(for: event)
            return [
                "eventName": protocolEventName(event),
                "handlerType": "command",
                "command": command,
                "sourcePath": path,
                "enabled": state.enabled,
                "trustStatus": state.trust,
            ]
        }
        if unrelatedHook {
            hooks.append([
                "eventName": "stop",
                "handlerType": "command",
                "command": "third-party command that must never affect the result",
                "sourcePath": path,
                "enabled": true,
                "trustStatus": "untrusted",
            ])
        }

        let errors: [[String: String]] = hasErrors
            ? [["path": path, "message": "fixture discovery error"]]
            : []
        let object: [String: Any] = [
            "id": CodexHookTrustProbe.requestID,
            "result": [
                "data": [[
                    "cwd": temporaryDirectory.path,
                    "hooks": hooks,
                    "warnings": [],
                    "errors": errors,
                ]],
            ],
        ]
        return try JSONSerialization.data(withJSONObject: object)
    }

    private func protocolEventName(_ event: String) -> String {
        guard let first = event.first else { return event }
        return first.lowercased() + event.dropFirst()
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

    private func readFixturePID(at url: URL) throws -> pid_t {
        let deadline = Date.now.addingTimeInterval(1)
        while Date.now < deadline {
            if let text = try? String(contentsOf: url, encoding: .utf8),
               let pid = pid_t(text.trimmingCharacters(in: .whitespacesAndNewlines)),
               pid > 0 {
                return pid
            }
            Thread.sleep(forTimeInterval: 0.01)
        }
        throw FixtureError.pidNotPublished
    }

    private func waitForProcessExit(_ pid: pid_t, timeout: TimeInterval) -> Bool {
        let deadline = Date.now.addingTimeInterval(timeout)
        while Date.now < deadline {
            if Darwin.kill(pid, 0) != 0, errno == ESRCH { return true }
            Thread.sleep(forTimeInterval: 0.01)
        }
        return Darwin.kill(pid, 0) != 0 && errno == ESRCH
    }

    private func terminateFixtureProcess(at url: URL) {
        guard let pid = try? readFixturePID(at: url),
              Darwin.kill(pid, 0) == 0 else { return }
        _ = Darwin.kill(pid, SIGKILL)
    }

    private enum FixtureError: Error {
        case pidNotPublished
    }
}
