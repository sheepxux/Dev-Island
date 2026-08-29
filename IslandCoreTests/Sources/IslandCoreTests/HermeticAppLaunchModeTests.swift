import XCTest
@testable import IslandCore

final class HermeticAppLaunchModeTests: XCTestCase {
    func testRequiresExactArgumentAndEnvironmentValueTogether() {
        XCTAssertTrue(HermeticAppLaunchMode.isEnabled(
            arguments: ["IslandApp", HermeticAppLaunchMode.argument],
            environment: [
                HermeticAppLaunchMode.environmentKey:
                    HermeticAppLaunchMode.environmentValue,
            ]
        ))

        XCTAssertFalse(HermeticAppLaunchMode.isEnabled(
            arguments: ["IslandApp", HermeticAppLaunchMode.argument],
            environment: [:]
        ))
        XCTAssertFalse(HermeticAppLaunchMode.isEnabled(
            arguments: ["IslandApp"],
            environment: [
                HermeticAppLaunchMode.environmentKey:
                    HermeticAppLaunchMode.environmentValue,
            ]
        ))
    }

    func testRejectsDuplicatesAndLookalikes() {
        let environment = [
            HermeticAppLaunchMode.environmentKey:
                HermeticAppLaunchMode.environmentValue,
        ]
        XCTAssertFalse(HermeticAppLaunchMode.isEnabled(
            arguments: [
                "IslandApp",
                HermeticAppLaunchMode.argument,
                HermeticAppLaunchMode.argument,
            ],
            environment: environment
        ))
        XCTAssertFalse(HermeticAppLaunchMode.isEnabled(
            arguments: ["IslandApp", "\(HermeticAppLaunchMode.argument)-extra"],
            environment: environment
        ))
        XCTAssertFalse(HermeticAppLaunchMode.isEnabled(
            arguments: ["IslandApp", HermeticAppLaunchMode.argument],
            environment: [HermeticAppLaunchMode.environmentKey: "true"]
        ))
    }

    func testUnrelatedInputsDoNotEnableMode() {
        XCTAssertFalse(HermeticAppLaunchMode.isEnabled(
            arguments: ["IslandApp", "--help"],
            environment: ["DEV_ISLAND_HERMETIC_LAUNCH_SMOKE_EXTRA": "v1"]
        ))
    }
}
