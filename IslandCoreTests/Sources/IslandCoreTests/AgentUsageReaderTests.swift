import Foundation
import XCTest
@testable import IslandCore

final class AgentUsageReaderTests: XCTestCase {
    func testReadsLatestProviderAuthoredWindowsWithoutReturningContent() throws {
        let fixture = try UsageFixture()
        defer { fixture.remove() }

        try fixture.write(
            name: "rollout-current.jsonl",
            lines: [
                #"{"timestamp":"2026-08-26T06:30:00Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"total_tokens":999}},"rate_limits":{"primary":{"used_percent":42.5,"window_minutes":300,"resets_at":1787745937},"secondary":{"used_percent":11,"window_minutes":10080,"resets_at":1788332737}}}}"#,
                #"{"type":"event_msg","payload":{"type":"user_message","message":"private token_count text must not become usage"}}"#,
            ],
            modifiedAt: Date(timeIntervalSince1970: 2_000)
        )

        let snapshot = try XCTUnwrap(CodexLocalUsageReader(
            codexDirectory: fixture.root
        ).latestSnapshot())

        XCTAssertEqual(snapshot.provider, .codex)
        XCTAssertEqual(snapshot.observedAt, ISO8601DateFormatter().date(from: "2026-08-26T06:30:00Z"))
        XCTAssertEqual(snapshot.windows.map(\.kind), [.primary, .secondary])
        XCTAssertEqual(snapshot.windows[0].usedPercent, 42.5)
        XCTAssertEqual(snapshot.windows[0].durationMinutes, 300)
        XCTAssertEqual(snapshot.windows[1].usedPercent, 11)
        XCTAssertEqual(snapshot.windows[1].durationMinutes, 10_080)
    }

    func testMalformedNewestRecordFallsBackWithoutInventingLimits() throws {
        let fixture = try UsageFixture()
        defer { fixture.remove() }

        try fixture.write(
            name: "rollout-valid.jsonl",
            lines: [usageLine(primary: 25, secondary: 50)],
            modifiedAt: Date(timeIntervalSince1970: 1_000)
        )
        try fixture.write(
            name: "rollout-invalid.jsonl",
            lines: [usageLine(primary: 101, secondary: -1)],
            modifiedAt: Date(timeIntervalSince1970: 2_000)
        )

        let snapshot = try XCTUnwrap(CodexLocalUsageReader(
            codexDirectory: fixture.root
        ).latestSnapshot())

        XCTAssertEqual(snapshot.windows.map(\.usedPercent), [25, 50])
    }

    func testReaderUsesBoundedSuffixAndSnapshotStalenessIsExplicit() throws {
        let fixture = try UsageFixture()
        defer { fixture.remove() }

        let largeNonUsageRecord = #"{"type":"event_msg","payload":{"type":"user_message","message":""#
            + String(repeating: "x", count: 12_000)
            + #""}}"#
        try fixture.write(
            name: "rollout-bounded.jsonl",
            lines: [largeNonUsageRecord, usageLine(primary: 4, secondary: 8)],
            modifiedAt: Date(timeIntervalSince1970: 3_000)
        )

        let snapshot = try XCTUnwrap(CodexLocalUsageReader(
            codexDirectory: fixture.root,
            maximumTailBytes: 4 * 1_024
        ).latestSnapshot())

        XCTAssertEqual(snapshot.windows.map(\.usedPercent), [4, 8])
        XCTAssertFalse(snapshot.isStale(
            at: snapshot.observedAt.addingTimeInterval(899),
            maximumAge: 900
        ))
        XCTAssertTrue(snapshot.isStale(
            at: snapshot.observedAt.addingTimeInterval(901),
            maximumAge: 900
        ))
    }

    func testMissingLocalActivityReturnsNil() throws {
        let fixture = try UsageFixture(createSessions: false)
        defer { fixture.remove() }

        XCTAssertNil(try CodexLocalUsageReader(
            codexDirectory: fixture.root
        ).latestSnapshot())
    }

    func testConcurrentGrowthCannotEscapeMeasuredTailBoundary() throws {
        let fixture = try UsageFixture()
        defer { fixture.remove() }
        let url = try fixture.write(
            name: "rollout-growing.jsonl",
            lines: [usageLine(primary: 12, secondary: 24)],
            modifiedAt: Date(timeIntervalSince1970: 4_000)
        )
        let appended = Data((
            #"{"type":"event_msg","payload":{"type":"user_message","message":""#
                + String(repeating: "x", count: 2 * 1_024 * 1_024)
                + #""}}"#
                + "\n"
                + usageLine(primary: 99, secondary: 98)
                + "\n"
        ).utf8)
        let reader = CodexLocalUsageReader(
            codexDirectory: fixture.root,
            maximumTailBytes: 4 * 1_024,
            maximumCandidateFiles: 24,
            maximumEnumeratedEntries: 8 * 1_024,
            beforeBoundedRead: { candidate in
                guard let handle = try? FileHandle(forWritingTo: candidate) else { return }
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: appended)
            }
        )

        let snapshot = try XCTUnwrap(reader.latestSnapshot())

        XCTAssertEqual(snapshot.windows.map(\.usedPercent), [12, 24])
        XCTAssertGreaterThan(
            try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0,
            2 * 1_024 * 1_024
        )
    }

    func testEnumerationPressureFailsAtHardEntryBudget() throws {
        let fixture = try UsageFixture()
        defer { fixture.remove() }
        for index in 0..<4 {
            try fixture.write(
                name: "rollout-pressure-\(index).jsonl",
                lines: [usageLine(primary: Double(index), secondary: 10)],
                modifiedAt: Date(timeIntervalSince1970: TimeInterval(5_000 + index))
            )
        }
        let reader = CodexLocalUsageReader(
            codexDirectory: fixture.root,
            maximumTailBytes: 4 * 1_024,
            maximumCandidateFiles: 2,
            maximumEnumeratedEntries: 5
        )

        XCTAssertThrowsError(try reader.latestSnapshot()) { error in
            XCTAssertEqual(
                error as? CodexLocalUsageReaderError,
                .enumerationLimitExceeded
            )
        }
    }

    func testWritableRolloutCandidateFailsClosedBeforeReading() throws {
        let fixture = try UsageFixture()
        defer { fixture.remove() }
        let url = try fixture.write(
            name: "rollout-writable.jsonl",
            lines: [usageLine(primary: 7, secondary: 14)],
            modifiedAt: Date(timeIntervalSince1970: 6_000)
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o622],
            ofItemAtPath: url.path
        )

        XCTAssertThrowsError(try CodexLocalUsageReader(
            codexDirectory: fixture.root
        ).latestSnapshot()) { error in
            XCTAssertEqual(error as? CodexLocalUsageReaderError, .unsafeCandidate)
        }
    }

    private func usageLine(primary: Double, secondary: Double) -> String {
        #"{"timestamp":"2026-08-26T06:30:00Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":\#(primary),"window_minutes":300,"resets_at":1787745937},"secondary":{"used_percent":\#(secondary),"window_minutes":10080,"resets_at":1788332737}}}}"#
    }
}

private struct UsageFixture {
    let root: URL
    let sessions: URL

    init(createSessions: Bool = true) throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("dev-island-usage-\(UUID().uuidString)")
        sessions = root.appendingPathComponent("sessions/2026/08/26", isDirectory: true)
        if createSessions {
            try FileManager.default.createDirectory(
                at: sessions,
                withIntermediateDirectories: true
            )
        } else {
            try FileManager.default.createDirectory(
                at: root,
                withIntermediateDirectories: true
            )
        }
    }

    @discardableResult
    func write(name: String, lines: [String], modifiedAt: Date) throws -> URL {
        let url = sessions.appendingPathComponent(name)
        try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: url)
        try FileManager.default.setAttributes(
            [.modificationDate: modifiedAt],
            ofItemAtPath: url.path
        )
        return url
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}
