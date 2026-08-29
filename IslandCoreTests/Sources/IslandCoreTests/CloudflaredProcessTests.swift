import Foundation
import XCTest
@testable import IslandCore

final class CloudflaredProcessTests: XCTestCase {
    func testFragmentedQuickTunnelURLStartsAndStopClosesTheChild() async throws {
        let fixture = try ProcessFixture()
        defer { fixture.cleanup() }
        let executable = try fixture.makeExecutable(
            """
            #!/bin/sh
            printf 'boot https://fragmented' >&2
            /bin/sleep 0.05
            printf '.trycloudflare.com ready\n' >&2
            exec /bin/sleep 5
            """
        )
        let process = CloudflaredProcess(
            executableURL: executable,
            // Ephemeral scripts can incur macOS executable inspection on a
            // loaded full-suite run. Production remains capped at 30 seconds;
            // this fixture gives launch jitter room while still proving the
            // fragmented stream completes well inside a finite deadline.
            urlAcquisitionTimeout: 5
        )

        let started = Date()
        let url = try await process.start()
        XCTAssertLessThan(Date().timeIntervalSince(started), 5)
        XCTAssertEqual(url.absoluteString, "https://fragmented.trycloudflare.com")
        let runningAfterStart = await process.isRunning
        XCTAssertTrue(runningAfterStart)

        await process.stop()
        let runningAfterStop = await process.isRunning
        XCTAssertFalse(runningAfterStop)
    }

    func testSilentChildCannotOutliveStartupTimeoutEvenWhenItIgnoresTerm() async throws {
        let fixture = try ProcessFixture()
        defer { fixture.cleanup() }
        let executable = try fixture.makeExecutable(
            """
            #!/bin/sh
            trap '' TERM
            printf 'termination trap armed\n' >&2
            while :; do :; done
            """
        )
        let process = CloudflaredProcess(
            executableURL: executable,
            urlAcquisitionTimeout: 0.2
        )
        let started = Date()

        do {
            _ = try await process.start()
            XCTFail("Expected the silent child to time out")
        } catch {
            XCTAssertEqual(error as? CloudflaredError, .urlAcquisitionTimeout)
        }

        XCTAssertLessThan(Date().timeIntervalSince(started), 1.5)
        let isRunning = await process.isRunning
        XCTAssertFalse(isRunning)
    }

    func testUnboundedStartupOutputFailsClosedAndStopsTheChild() async throws {
        let fixture = try ProcessFixture()
        defer { fixture.cleanup() }
        let executable = try fixture.makeExecutable(
            """
            #!/bin/sh
            exec /usr/bin/yes x 1>&2
            """
        )
        let process = CloudflaredProcess(
            executableURL: executable,
            urlAcquisitionTimeout: 5
        )
        let started = Date()

        do {
            _ = try await process.start()
            XCTFail("Expected bounded stderr collection to reject the child")
        } catch {
            XCTAssertEqual(error as? CloudflaredError, .outputLimitExceeded)
        }

        XCTAssertLessThan(Date().timeIntervalSince(started), 5)
        let isRunning = await process.isRunning
        XCTAssertFalse(isRunning)
    }

    func testQuickTunnelParserRejectsLookalikesAndUnsafeLabels() {
        XCTAssertEqual(
            CloudflaredProcess.quickTunnelURL(
                in: Data("notice https://abc-123.trycloudflare.com ready".utf8)
            )?.absoluteString,
            "https://abc-123.trycloudflare.com"
        )

        for value in [
            "https://-leading.trycloudflare.com",
            "https://trailing-.trycloudflare.com",
            "https://UPPER.trycloudflare.com",
            "https://valid.trycloudflare.com.evil.example",
            "http://valid.trycloudflare.com",
        ] {
            XCTAssertNil(
                CloudflaredProcess.quickTunnelURL(in: Data(value.utf8)),
                value
            )
        }
    }

    func testPathLookupNeverExecutesWhichAndRejectsWritableBinary() throws {
        let fixture = try ProcessFixture()
        defer { fixture.cleanup() }
        let sentinel = fixture.directory.appendingPathComponent("which-ran")
        _ = try fixture.makeExecutable(
            """
            #!/bin/sh
            /usr/bin/touch '\(sentinel.path)'
            """,
            name: "which"
        )

        XCTAssertNil(CloudflaredProcess.lookupOnPath(
            "cloudflared",
            path: fixture.directory.path
        ))
        XCTAssertFalse(FileManager.default.fileExists(atPath: sentinel.path))

        let executable = try fixture.makeExecutable(
            "#!/bin/sh\nexit 0\n",
            name: "cloudflared"
        )
        XCTAssertEqual(
            CloudflaredProcess.lookupOnPath(
                "cloudflared",
                path: "/relative:\(fixture.directory.path)"
            ),
            executable.standardizedFileURL.resolvingSymlinksInPath()
        )

        try FileManager.default.setAttributes(
            [.posixPermissions: 0o722],
            ofItemAtPath: executable.path
        )
        XCTAssertNil(CloudflaredProcess.lookupOnPath(
            "cloudflared",
            path: fixture.directory.path
        ))
        XCTAssertFalse(FileManager.default.fileExists(atPath: sentinel.path))
    }
}

private final class ProcessFixture {
    let directory: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("dev-island-cloudflared-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: false
        )
    }

    func makeExecutable(_ source: String, name: String = "cloudflared") throws -> URL {
        let url = directory.appendingPathComponent(name)
        try Data(source.utf8).write(to: url)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: url.path
        )
        return url
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: directory)
    }
}
