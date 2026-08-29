import XCTest
@testable import IslandAppLib
import IslandCore

final class SupportDiagnosticsTests: XCTestCase {
    private let fixedDate = Date(timeIntervalSince1970: 1_787_710_400)

    func testReportContainsUsefulAggregateState() {
        let report = SupportDiagnostics.report(
            appVersion: "0.3.0",
            appBuild: "30",
            operatingSystem: "macOS 15.6",
            architecture: "arm64",
            generatedAt: fixedDate,
            connectionStatus: .connected,
            apiKeyStatus: .valid,
            tasks: [
                task(id: "one", source: "codex", status: .running),
                task(id: "two", source: "codex", status: .waiting),
                task(id: "three", source: "manus", status: .failed),
            ],
            localHookServiceStatus: .retrying(attempt: 2, limit: 5),
            localAgentHooks: .init(agents: [
                .init(source: "claude-code", displayName: "Claude Code", state: .connected),
                .init(source: "codex", displayName: "Codex", state: .configured),
                .init(source: "qwen-code", displayName: "Qwen Code", state: .updateRequired),
                .init(source: "cursor", displayName: "Cursor", state: .disconnected),
            ]),
            previousLaunchState: .startupInterrupted,
            consecutiveStartupInterruptions: 2
        )

        XCTAssertTrue(report.contains("Version: 0.3.0 (30)"))
        XCTAssertTrue(report.contains("Architecture: arm64"))
        XCTAssertTrue(report.contains("Manus API: configured"))
        XCTAssertTrue(report.contains("Connection: connected"))
        XCTAssertTrue(report.contains("Local Agent Listener: retrying (2/5)"))
        XCTAssertTrue(report.contains("Local Agent Hooks: 1 connected, 1 configured, 1 update required, 1 disconnected"))
        XCTAssertTrue(report.contains("- Claude Code: connected"))
        XCTAssertTrue(report.contains("- Codex: configured; confirm in agent"))
        XCTAssertTrue(report.contains("- Qwen Code: update required"))
        XCTAssertTrue(report.contains("- Cursor: not connected"))
        XCTAssertTrue(report.contains(
            "Previous Launch: startup readiness not reached (2 consecutive; capped at 3)"
        ))
        XCTAssertTrue(report.contains("Sessions: 3"))
        XCTAssertTrue(report.contains("- waiting: 1"))
        XCTAssertTrue(report.contains("- failed: 1"))
        XCTAssertTrue(report.contains("- running: 1"))
        XCTAssertTrue(report.contains("- Codex: 2"))
        XCTAssertTrue(report.contains("- Manus: 1"))
    }

    func testReportNeverIncludesTaskPayloadOrUnknownSourceName() {
        let secret = "sk-super-secret-customer-content"
        let report = SupportDiagnostics.report(
            appVersion: "test",
            appBuild: "test",
            operatingSystem: "test",
            architecture: "test",
            generatedAt: fixedDate,
            connectionStatus: .degraded(reason: secret),
            apiKeyStatus: .invalid,
            tasks: [
                AgentTask(
                    id: "private-session-id",
                    source: "private-project-agent",
                    title: "Confidential acquisition plan",
                    status: .waiting,
                    currentPhase: "Reading /Users/customer/SecretProject",
                    createdAt: fixedDate,
                    updatedAt: fixedDate,
                    taskURL: "https://example.invalid/private-token",
                    waitingMessage: secret
                ),
            ],
            localHookServiceStatus: .unavailable,
            localAgentHooks: .init(agents: [
                .init(source: "private-source", displayName: "Known Agent", state: .disconnected),
            ]),
            previousLaunchState: .ready
        )

        XCTAssertTrue(report.contains("Connection: degraded"))
        XCTAssertTrue(report.contains("Previous Launch: startup ready recorded"))
        XCTAssertTrue(report.contains("- Other: 1"))
        XCTAssertFalse(report.contains(secret))
        XCTAssertFalse(report.contains("private-session-id"))
        XCTAssertFalse(report.contains("private-project-agent"))
        XCTAssertFalse(report.contains("Confidential acquisition plan"))
        XCTAssertFalse(report.contains("/Users/customer/SecretProject"))
        XCTAssertFalse(report.contains("private-token"))
    }

    func testExporterWritesPrivateUTF8FileAndNormalizesFinalNewline() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appendingPathComponent("diagnostics.txt")

        try SupportDiagnosticsExporter.write("privacy-safe report", to: destination)

        XCTAssertEqual(
            try String(contentsOf: destination, encoding: .utf8),
            "privacy-safe report\n"
        )
        let attributes = try FileManager.default.attributesOfItem(
            atPath: destination.path
        )
        XCTAssertEqual(
            (attributes[.posixPermissions] as? NSNumber)?.intValue,
            0o600
        )
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: directory.path),
            ["diagnostics.txt"]
        )
    }

    func testExporterAtomicallyReplacesARegularFileAndKeepsPrivateMode() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appendingPathComponent("diagnostics.txt")
        try Data("old".utf8).write(to: destination)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o644],
            ofItemAtPath: destination.path
        )

        try SupportDiagnosticsExporter.write("new", to: destination)

        XCTAssertEqual(
            try String(contentsOf: destination, encoding: .utf8),
            "new\n"
        )
        let attributes = try FileManager.default.attributesOfItem(
            atPath: destination.path
        )
        XCTAssertEqual(
            (attributes[.posixPermissions] as? NSNumber)?.intValue,
            0o600
        )
    }

    func testExporterRejectsSymlinkWithoutChangingItsTarget() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = directory.appendingPathComponent("target.txt")
        let destination = directory.appendingPathComponent("diagnostics.txt")
        try Data("keep".utf8).write(to: target)
        try FileManager.default.createSymbolicLink(
            at: destination,
            withDestinationURL: target
        )

        XCTAssertThrowsError(
            try SupportDiagnosticsExporter.write("replace", to: destination)
        ) { error in
            XCTAssertEqual(
                error as? SupportDiagnosticsExporter.ExportError,
                .unsafeDestination
            )
        }
        XCTAssertEqual(
            try String(contentsOf: target, encoding: .utf8),
            "keep"
        )
        XCTAssertEqual(
            try FileManager.default.destinationOfSymbolicLink(
                atPath: destination.path
            ),
            target.path
        )
    }

    func testExporterRejectsEmptyOversizedAndUnavailableDestinations() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        XCTAssertThrowsError(
            try SupportDiagnosticsExporter.write(
                "   \n",
                to: directory.appendingPathComponent("empty.txt")
            )
        ) { error in
            XCTAssertEqual(
                error as? SupportDiagnosticsExporter.ExportError,
                .emptyReport
            )
        }

        let oversized = String(
            repeating: "x",
            count: SupportDiagnosticsExporter.maximumReportBytes + 1
        )
        XCTAssertThrowsError(
            try SupportDiagnosticsExporter.write(
                oversized,
                to: directory.appendingPathComponent("large.txt")
            )
        ) { error in
            XCTAssertEqual(
                error as? SupportDiagnosticsExporter.ExportError,
                .reportTooLarge
            )
        }

        XCTAssertThrowsError(
            try SupportDiagnosticsExporter.write(
                "report",
                to: directory
                    .appendingPathComponent("missing", isDirectory: true)
                    .appendingPathComponent("diagnostics.txt")
            )
        ) { error in
            XCTAssertEqual(
                error as? SupportDiagnosticsExporter.ExportError,
                .unavailableFolder
            )
        }
    }

    func testSuggestedFilenameIsStableAndContainsNoUserData() {
        XCTAssertEqual(
            SupportDiagnosticsExporter.suggestedFilename(
                at: Date(timeIntervalSince1970: 0),
                timeZone: TimeZone(secondsFromGMT: 0)!
            ),
            "Dev-Island-Diagnostics-19700101-000000.txt"
        )
    }

    func testDiagnosticOperationInvalidationRejectsLateCompletion() {
        var state = SupportDiagnosticsOperationState()
        let firstID = UUID()
        let secondID = UUID()

        XCTAssertEqual(state.begin(.save, id: firstID), firstID)
        XCTAssertNil(state.begin(.copy, id: secondID))
        XCTAssertTrue(state.isBusy)

        state.invalidate()

        XCTAssertFalse(state.complete(firstID))
        XCTAssertEqual(state.begin(.copy, id: secondID), secondID)
        XCTAssertTrue(state.complete(secondID))
        XCTAssertFalse(state.isBusy)
    }

    func testDiagnosticFeedbackUsesIdentityInsteadOfMessageEquality() {
        var state = SupportDiagnosticsFeedbackState()
        let firstID = UUID()
        let secondID = UUID()

        state.showMessage("Saved", id: firstID)
        state.showMessage("Saved", id: secondID)

        XCTAssertFalse(state.clear(firstID))
        XCTAssertEqual(state.message, "Saved")
        XCTAssertTrue(state.clear(secondID))
        XCTAssertNil(state.message)
    }

    @MainActor
    func testDiagnosticIOExecutorLeavesTheMainThread() async {
        let ranOnMainThread = await SupportDiagnosticsIOExecutor.run {
            Thread.isMainThread
        }

        XCTAssertFalse(ranOnMainThread)
    }

    func testDiagnosticExportWorkerReturnsBoundedOutcome() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appendingPathComponent("diagnostics.txt")

        XCTAssertEqual(
            SupportDiagnosticsExportWorker.write("report", to: destination),
            .saved
        )
        XCTAssertEqual(
            SupportDiagnosticsExportWorker.write("   ", to: destination),
            .failed(.emptyReport)
        )
    }

    private func task(id: String, source: String, status: TaskStatus) -> AgentTask {
        AgentTask(
            id: id,
            source: source,
            title: "title-\(id)",
            status: status,
            createdAt: fixedDate,
            updatedAt: fixedDate,
            taskURL: "file:///tmp/\(id)"
        )
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: false
        )
        return directory
    }
}
