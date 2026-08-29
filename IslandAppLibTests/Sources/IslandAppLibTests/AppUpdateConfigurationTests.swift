import Foundation
import XCTest
@testable import IslandAppLib

@MainActor
final class AppUpdateConfigurationTests: XCTestCase {
    private let publicKey = Data(repeating: 0x4D, count: 32).base64EncodedString()

    func testAcceptsOnlyCompleteAuthenticatedConfiguration() throws {
        let configuration = try XCTUnwrap(AppUpdateConfiguration(infoDictionary: validInfo()))

        XCTAssertEqual(configuration.feedURL.absoluteString, "https://github.com/sheepxux/Dev-Island/releases/latest/download/appcast.xml")
        XCTAssertEqual(configuration.publicKey, publicKey)
    }

    func testRejectsNonHTTPSFeedAndEmbeddedCredentials() {
        var insecure = validInfo()
        insecure["SUFeedURL"] = "http://devisland.app/appcast.xml"
        XCTAssertNil(AppUpdateConfiguration(infoDictionary: insecure))

        insecure["SUFeedURL"] = "https://user:pass@devisland.app/appcast.xml"
        XCTAssertNil(AppUpdateConfiguration(infoDictionary: insecure))
    }

    func testRejectsAnyUnexpectedHTTPSFeedDestination() {
        for feed in [
            "https://devisland.app/appcast.xml",
            "https://github.com/sheepxux/Dev-Island/releases/latest/download/other.xml",
            "https://github.com/sheepxux/Dev-Island/releases/latest/download/appcast.xml?channel=other",
            "https://github.com/sheepxux/Dev-Island/releases/latest/download/appcast.xml#other",
        ] {
            var info = validInfo()
            info["SUFeedURL"] = feed
            XCTAssertNil(AppUpdateConfiguration(infoDictionary: info), feed)
        }
    }

    func testRejectsMissingOrMalformedPublicKey() {
        var missing = validInfo()
        missing.removeValue(forKey: "SUPublicEDKey")
        XCTAssertNil(AppUpdateConfiguration(infoDictionary: missing))

        var short = validInfo()
        short["SUPublicEDKey"] = Data(repeating: 1, count: 31).base64EncodedString()
        XCTAssertNil(AppUpdateConfiguration(infoDictionary: short))
    }

    func testRejectsAnyWeakenedSecurityFlag() {
        for key in ["SUVerifyUpdateBeforeExtraction", "SURequireSignedFeed"] {
            var info = validInfo()
            info[key] = false
            XCTAssertNil(AppUpdateConfiguration(infoDictionary: info), key)
        }

        var profiling = validInfo()
        profiling["SUEnableSystemProfiling"] = true
        XCTAssertNil(AppUpdateConfiguration(infoDictionary: profiling))

        var automaticChecks = validInfo()
        automaticChecks["SUEnableAutomaticChecks"] = false
        XCTAssertNil(AppUpdateConfiguration(infoDictionary: automaticChecks))

        var silentInstallation = validInfo()
        silentInstallation["SUAutomaticallyUpdate"] = true
        XCTAssertNil(AppUpdateConfiguration(infoDictionary: silentInstallation))

        var expiringSignedFeedFailure = validInfo()
        expiringSignedFeedFailure["SUSignedFeedFailureExpirationInterval"] = 86_400
        XCTAssertNil(AppUpdateConfiguration(infoDictionary: expiringSignedFeedFailure))

        var frequentChecks = validInfo()
        frequentChecks["SUScheduledCheckInterval"] = 3_600
        XCTAssertNil(AppUpdateConfiguration(infoDictionary: frequentChecks))
    }

    func testRejectsMissingAuthenticatedUpdateField() {
        for key in validInfo().keys {
            var info = validInfo()
            info.removeValue(forKey: key)
            XCTAssertNil(AppUpdateConfiguration(infoDictionary: info), key)
        }
    }

    func testKeylessControllerNeverConstructsOrStartsRuntime() {
        var runtimeCreationCount = 0
        let controller = AppUpdateController(
            infoDictionary: [:],
            currentVersion: "0.3.0",
            makeRuntime: {
                runtimeCreationCount += 1
                return FakeAppUpdateRuntime()
            }
        )

        XCTAssertFalse(controller.isAvailable)
        XCTAssertEqual(controller.status, .unavailable)
        XCTAssertFalse(controller.canCheckForUpdates)
        XCTAssertFalse(controller.canChangeAutomaticChecks)
        controller.start()
        controller.start()
        controller.checkForUpdates()
        controller.setAutomaticallyChecksForUpdates(true)
        XCTAssertEqual(runtimeCreationCount, 0)
    }

    func testRuntimeStartsOnceAndManualCheckHasExplicitBusyState() {
        let runtime = FakeAppUpdateRuntime(
            canCheckForUpdates: true,
            automaticallyChecksForUpdates: true
        )
        var runtimeCreationCount = 0
        let controller = AppUpdateController(
            infoDictionary: validInfo(),
            currentVersion: "0.3.0",
            makeRuntime: {
                runtimeCreationCount += 1
                return runtime
            }
        )

        XCTAssertTrue(controller.isAvailable)
        XCTAssertEqual(controller.status, .starting)
        controller.start()
        controller.start()
        XCTAssertEqual(runtimeCreationCount, 1)
        XCTAssertEqual(runtime.startCount, 1)
        XCTAssertEqual(controller.status, .ready)
        XCTAssertTrue(controller.canCheckForUpdates)
        XCTAssertTrue(controller.automaticallyChecksForUpdates)
        XCTAssertTrue(controller.canChangeAutomaticChecks)

        controller.checkForUpdates()
        controller.checkForUpdates()
        XCTAssertEqual(runtime.checkCount, 1)
        XCTAssertEqual(controller.status, .checking)
        XCTAssertFalse(controller.canCheckForUpdates)

        runtime.emitCanCheck(true)
        XCTAssertEqual(controller.status, .ready)
        XCTAssertTrue(controller.canCheckForUpdates)
    }

    func testFailedStartDisablesControlsAndRejectsLateCallbacks() {
        let runtime = FakeAppUpdateRuntime(startError: FakeUpdateError.startFailed)
        let controller = AppUpdateController(
            infoDictionary: validInfo(),
            currentVersion: "0.3.0",
            makeRuntime: { runtime }
        )

        controller.start()
        XCTAssertTrue(controller.isAvailable)
        XCTAssertEqual(controller.status, .failed)
        XCTAssertFalse(controller.canCheckForUpdates)
        XCTAssertFalse(controller.automaticallyChecksForUpdates)
        XCTAssertFalse(controller.canChangeAutomaticChecks)

        runtime.emitCanCheck(true)
        runtime.emitAutomaticChecks(true)
        XCTAssertEqual(controller.status, .failed)
        XCTAssertFalse(controller.canCheckForUpdates)
        XCTAssertFalse(controller.automaticallyChecksForUpdates)

        controller.checkForUpdates()
        controller.setAutomaticallyChecksForUpdates(false)
        XCTAssertEqual(runtime.checkCount, 0)
        XCTAssertTrue(runtime.automaticallyChecksForUpdates)
    }

    func testAutomaticCheckPreferenceMirrorsRuntimeOnlyAfterStart() {
        let runtime = FakeAppUpdateRuntime(
            canCheckForUpdates: true,
            automaticallyChecksForUpdates: false
        )
        let controller = AppUpdateController(
            infoDictionary: validInfo(),
            currentVersion: "0.3.0",
            makeRuntime: { runtime }
        )

        controller.setAutomaticallyChecksForUpdates(true)
        XCTAssertFalse(runtime.automaticallyChecksForUpdates)
        controller.start()
        controller.setAutomaticallyChecksForUpdates(true)
        XCTAssertTrue(runtime.automaticallyChecksForUpdates)
        XCTAssertTrue(controller.automaticallyChecksForUpdates)
        runtime.emitAutomaticChecks(false)
        XCTAssertFalse(controller.automaticallyChecksForUpdates)
    }

    private func validInfo() -> [String: Any] {
        [
            "SUFeedURL": "https://github.com/sheepxux/Dev-Island/releases/latest/download/appcast.xml",
            "SUPublicEDKey": publicKey,
            "SUVerifyUpdateBeforeExtraction": true,
            "SURequireSignedFeed": true,
            "SUSignedFeedFailureExpirationInterval": 0,
            "SUEnableAutomaticChecks": true,
            "SUScheduledCheckInterval": 86_400,
            "SUAutomaticallyUpdate": false,
            "SUEnableSystemProfiling": false,
        ]
    }
}

@MainActor
private final class FakeAppUpdateRuntime: AppUpdateRuntime {
    var canCheckForUpdates: Bool
    var automaticallyChecksForUpdates: Bool
    private let startError: Error?

    private(set) var startCount = 0
    private(set) var checkCount = 0
    private var canCheckDidChange: ((Bool) -> Void)?
    private var automaticChecksDidChange: ((Bool) -> Void)?

    init(
        canCheckForUpdates: Bool = false,
        automaticallyChecksForUpdates: Bool = false,
        startError: Error? = nil
    ) {
        self.canCheckForUpdates = canCheckForUpdates
        self.automaticallyChecksForUpdates = automaticallyChecksForUpdates
        self.startError = startError
    }

    func start(
        canCheckDidChange: @escaping (Bool) -> Void,
        automaticChecksDidChange: @escaping (Bool) -> Void
    ) throws {
        startCount += 1
        self.canCheckDidChange = canCheckDidChange
        self.automaticChecksDidChange = automaticChecksDidChange
        if let startError { throw startError }
        canCheckDidChange(canCheckForUpdates)
        automaticChecksDidChange(automaticallyChecksForUpdates)
    }

    func checkForUpdates() {
        checkCount += 1
        canCheckForUpdates = false
        canCheckDidChange?(false)
    }

    func emitCanCheck(_ value: Bool) {
        canCheckForUpdates = value
        canCheckDidChange?(value)
    }

    func emitAutomaticChecks(_ value: Bool) {
        automaticallyChecksForUpdates = value
        automaticChecksDidChange?(value)
    }
}

private enum FakeUpdateError: Error {
    case startFailed
}
