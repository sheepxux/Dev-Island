import XCTest
@testable import IslandAppLib

final class AppSingleInstanceGateTests: XCTestCase {
    func testCurrentProcessWinsWhenItIsTheOnlyLiveCandidate() {
        XCTAssertNil(AppInstanceSelectionPolicy.existingWinner(
            currentProcessIdentifier: 200,
            currentCodeIdentity: adHocIdentity(1),
            candidates: [candidate(200)],
            resolveCodeIdentity: { _ in self.adHocIdentity(1) }
        ))
    }

    func testOlderLiveProcessWinsDeterministically() {
        let winner = AppInstanceSelectionPolicy.existingWinner(
            currentProcessIdentifier: 300,
            currentCodeIdentity: adHocIdentity(1),
            candidates: [candidate(300), candidate(100), candidate(200)],
            resolveCodeIdentity: { _ in self.adHocIdentity(1) }
        )
        XCTAssertEqual(winner?.processIdentifier, 100)
    }

    func testCurrentProcessStaysWhenItIsOldest() {
        XCTAssertNil(AppInstanceSelectionPolicy.existingWinner(
            currentProcessIdentifier: 100,
            currentCodeIdentity: adHocIdentity(1),
            candidates: [candidate(300), candidate(100), candidate(200)],
            resolveCodeIdentity: { _ in self.adHocIdentity(1) }
        ))
    }

    func testTerminatedAndInvalidCandidatesCannotWin() {
        XCTAssertNil(AppInstanceSelectionPolicy.existingWinner(
            currentProcessIdentifier: 300,
            currentCodeIdentity: adHocIdentity(1),
            candidates: [
                candidate(100, isTerminated: true),
                candidate(0),
                candidate(-1),
                candidate(300),
            ],
            resolveCodeIdentity: { _ in self.adHocIdentity(1) }
        ))
    }

    func testInvalidCurrentProcessFailsOpen() {
        XCTAssertNil(AppInstanceSelectionPolicy.existingWinner(
            currentProcessIdentifier: 0,
            currentCodeIdentity: adHocIdentity(1),
            candidates: [candidate(100)],
            resolveCodeIdentity: { _ in self.adHocIdentity(1) }
        ))
    }

    func testSameTeamCanTrustDifferentReleaseHashes() {
        let current = teamIdentity("DEVTEAM", hashByte: 1)
        let candidate = teamIdentity("DEVTEAM", hashByte: 2)

        XCTAssertTrue(candidate.isTrustedPeer(of: current))
        XCTAssertNotEqual(candidate, current)
    }

    func testDifferentTeamsCannotArbitrate() {
        let current = teamIdentity("TEAM-A")
        let candidateIdentity = teamIdentity("TEAM-B")

        XCTAssertFalse(candidateIdentity.isTrustedPeer(of: current))
        XCTAssertNil(AppInstanceSelectionPolicy.existingWinner(
            currentProcessIdentifier: 200,
            currentCodeIdentity: current,
            candidates: [candidate(100)],
            resolveCodeIdentity: { _ in candidateIdentity }
        ))
    }

    func testAdHocCopiesRequireTheSameNonemptyCDHash() {
        XCTAssertTrue(adHocIdentity(7).isTrustedPeer(of: adHocIdentity(7)))
        XCTAssertFalse(adHocIdentity(7).isTrustedPeer(of: adHocIdentity(8)))
        XCTAssertFalse(
            AppInstanceCodeIdentity.hashBound(
                identifier: bundleIdentifier,
                cdHash: Data()
            )
            .isTrustedPeer(of: adHocIdentity(7))
        )
    }

    func testTeamAndAdHocIdentitiesNeverMix() {
        XCTAssertFalse(teamIdentity("DEVTEAM").isTrustedPeer(of: adHocIdentity(1)))
        XCTAssertFalse(adHocIdentity(1).isTrustedPeer(of: teamIdentity("DEVTEAM")))
    }

    func testBundleIdentifierMustMatchExactly() {
        let impostor = AppInstanceCodeIdentity.teamSigned(
            identifier: "app.devisland.Island.preview",
            teamIdentifier: "DEVTEAM",
            cdHash: Data(repeating: 1, count: 20)
        )
        XCTAssertFalse(impostor.isTrustedPeer(of: teamIdentity("DEVTEAM")))
    }

    func testUntrustedOlderCandidateCannotDisplaceTrustedOlderCandidate() {
        let current = adHocIdentity(1)
        let winner = AppInstanceSelectionPolicy.existingWinner(
            currentProcessIdentifier: 400,
            currentCodeIdentity: current,
            candidates: [candidate(100), candidate(200), candidate(300)],
            resolveCodeIdentity: { processIdentifier in
                processIdentifier == 200 ? current : self.adHocIdentity(9)
            }
        )

        XCTAssertEqual(winner?.processIdentifier, 200)
    }

    func testDuplicateUnorderedCandidatesResolveEachEligiblePIDAtMostOnce() {
        var resolutions: [Int32: Int] = [:]
        let current = adHocIdentity(1)
        let winner = AppInstanceSelectionPolicy.existingWinner(
            currentProcessIdentifier: 400,
            currentCodeIdentity: current,
            candidates: [
                candidate(300), candidate(100), candidate(200),
                candidate(100), candidate(300), candidate(200),
            ],
            resolveCodeIdentity: { processIdentifier in
                resolutions[processIdentifier, default: 0] += 1
                return processIdentifier == 200 ? current : self.adHocIdentity(9)
            }
        )

        XCTAssertEqual(winner?.processIdentifier, 200)
        XCTAssertEqual(resolutions, [100: 1, 200: 1])
    }

    func testCandidateFloodFailsOpenWithoutResolvingIdentity() {
        var resolutionCount = 0
        let candidates = (0...AppInstanceSelectionPolicy.maximumCandidateCount).map {
            candidate(Int32($0 + 1))
        }

        XCTAssertNil(AppInstanceSelectionPolicy.existingWinner(
            currentProcessIdentifier: 1_000,
            currentCodeIdentity: adHocIdentity(1),
            candidates: candidates,
            resolveCodeIdentity: { _ in
                resolutionCount += 1
                return self.adHocIdentity(1)
            }
        ))
        XCTAssertEqual(resolutionCount, 0)
    }

    func testTrustedWinnerIsRevalidatedThenActivatedExactlyOnce() {
        var resolutionCount = 0
        var activatedProcessIdentifiers: [Int32] = []

        let didActivate = AppInstanceSelectionPolicy.activateExistingInstanceIfNeeded(
            currentProcessIdentifier: 300,
            currentCodeIdentity: adHocIdentity(1),
            candidates: [candidate(100), candidate(200)],
            resolveCodeIdentity: { _ in
                resolutionCount += 1
                return self.adHocIdentity(1)
            },
            activate: {
                activatedProcessIdentifiers.append($0)
                return true
            }
        )

        XCTAssertTrue(didActivate)
        XCTAssertEqual(resolutionCount, 2)
        XCTAssertEqual(activatedProcessIdentifiers, [100])
    }

    func testActivationFailureKeepsCurrentInstanceRunning() {
        var activatedProcessIdentifiers: [Int32] = []

        let didActivate = AppInstanceSelectionPolicy.activateExistingInstanceIfNeeded(
            currentProcessIdentifier: 300,
            currentCodeIdentity: adHocIdentity(1),
            candidates: [candidate(100), candidate(200)],
            resolveCodeIdentity: { _ in self.adHocIdentity(1) },
            activate: {
                activatedProcessIdentifiers.append($0)
                return false
            }
        )

        XCTAssertFalse(didActivate)
        XCTAssertEqual(activatedProcessIdentifiers, [100])
    }

    func testIdentityDriftBeforeActivationFailsOpen() {
        var resolutionCount = 0
        var activationCount = 0

        let didActivate = AppInstanceSelectionPolicy.activateExistingInstanceIfNeeded(
            currentProcessIdentifier: 300,
            currentCodeIdentity: adHocIdentity(1),
            candidates: [candidate(100)],
            resolveCodeIdentity: { _ in
                resolutionCount += 1
                return self.adHocIdentity(resolutionCount == 1 ? 1 : 2)
            },
            activate: { _ in
                activationCount += 1
                return true
            }
        )

        XCTAssertFalse(didActivate)
        XCTAssertEqual(resolutionCount, 2)
        XCTAssertEqual(activationCount, 0)
    }

    func testCandidateDisappearingBeforeActivationFailsOpen() {
        var resolutionCount = 0
        var activationCount = 0

        let didActivate = AppInstanceSelectionPolicy.activateExistingInstanceIfNeeded(
            currentProcessIdentifier: 300,
            currentCodeIdentity: teamIdentity("DEVTEAM"),
            candidates: [candidate(100)],
            resolveCodeIdentity: { _ in
                resolutionCount += 1
                return resolutionCount == 1 ? self.teamIdentity("DEVTEAM") : nil
            },
            activate: { _ in
                activationCount += 1
                return true
            }
        )

        XCTAssertFalse(didActivate)
        XCTAssertEqual(activationCount, 0)
    }

    func testSecurityResolverRejectsInvalidProcessIdentifiers() {
        XCTAssertNil(AppInstanceCodeIdentityResolver.identity(
            processIdentifier: 0,
            expectedIdentifier: bundleIdentifier
        ))
        XCTAssertNil(AppInstanceCodeIdentityResolver.identity(
            processIdentifier: -1,
            expectedIdentifier: bundleIdentifier
        ))
    }

    func testSigningClassifierRequiresExplicitAdHocFlagForHashBinding() {
        let hash = Data(repeating: 7, count: 20)

        XCTAssertEqual(
            AppInstanceCodeIdentityResolver.classifiedIdentity(
                identifier: bundleIdentifier,
                expectedIdentifier: bundleIdentifier,
                teamIdentifier: nil,
                cdHash: hash,
                isAdHoc: true,
                teamSignatureIsTrusted: { _ in false }
            ),
            .hashBound(identifier: bundleIdentifier, cdHash: hash)
        )
        XCTAssertNil(AppInstanceCodeIdentityResolver.classifiedIdentity(
            identifier: bundleIdentifier,
            expectedIdentifier: bundleIdentifier,
            teamIdentifier: nil,
            cdHash: hash,
            isAdHoc: false,
            teamSignatureIsTrusted: { _ in true }
        ))
    }

    func testSigningClassifierRequiresAppleAnchoredTeamSignature() {
        let hash = Data(repeating: 8, count: 20)
        var checkedTeams: [String] = []

        XCTAssertNil(AppInstanceCodeIdentityResolver.classifiedIdentity(
            identifier: bundleIdentifier,
            expectedIdentifier: bundleIdentifier,
            teamIdentifier: "DEVTEAM",
            cdHash: hash,
            isAdHoc: false,
            teamSignatureIsTrusted: { _ in false }
        ))
        XCTAssertEqual(
            AppInstanceCodeIdentityResolver.classifiedIdentity(
                identifier: bundleIdentifier,
                expectedIdentifier: bundleIdentifier,
                teamIdentifier: "DEVTEAM",
                cdHash: hash,
                isAdHoc: false,
                teamSignatureIsTrusted: {
                    checkedTeams.append($0)
                    return true
                }
            ),
            .teamSigned(
                identifier: bundleIdentifier,
                teamIdentifier: "DEVTEAM",
                cdHash: hash
            )
        )
        XCTAssertEqual(checkedTeams, ["DEVTEAM"])
    }

    func testSigningClassifierRejectsMixedOrMalformedIdentity() {
        let hash = Data(repeating: 9, count: 20)

        XCTAssertNil(AppInstanceCodeIdentityResolver.classifiedIdentity(
            identifier: bundleIdentifier,
            expectedIdentifier: bundleIdentifier,
            teamIdentifier: "DEVTEAM",
            cdHash: hash,
            isAdHoc: true,
            teamSignatureIsTrusted: { _ in true }
        ))
        XCTAssertNil(AppInstanceCodeIdentityResolver.classifiedIdentity(
            identifier: "\(bundleIdentifier)\" or true",
            expectedIdentifier: "\(bundleIdentifier)\" or true",
            teamIdentifier: "DEVTEAM",
            cdHash: hash,
            isAdHoc: false,
            teamSignatureIsTrusted: { _ in true }
        ))
        XCTAssertNil(AppInstanceCodeIdentityResolver.classifiedIdentity(
            identifier: bundleIdentifier,
            expectedIdentifier: bundleIdentifier,
            teamIdentifier: "DEV TEAM",
            cdHash: hash,
            isAdHoc: false,
            teamSignatureIsTrusted: { _ in true }
        ))
    }

    func testSigningClassifierRejectsMissingIdentityFields() {
        let hash = Data(repeating: 9, count: 20)

        for identifier in [nil, ""] as [String?] {
            XCTAssertNil(AppInstanceCodeIdentityResolver.classifiedIdentity(
                identifier: identifier,
                expectedIdentifier: bundleIdentifier,
                teamIdentifier: nil,
                cdHash: hash,
                isAdHoc: true,
                teamSignatureIsTrusted: { _ in false }
            ))
        }
        for candidateHash in [nil, Data()] as [Data?] {
            XCTAssertNil(AppInstanceCodeIdentityResolver.classifiedIdentity(
                identifier: bundleIdentifier,
                expectedIdentifier: bundleIdentifier,
                teamIdentifier: nil,
                cdHash: candidateHash,
                isAdHoc: true,
                teamSignatureIsTrusted: { _ in false }
            ))
        }
    }

    func testSameTeamIdentityDriftStillFailsRevalidation() {
        var resolutionCount = 0
        var activationCount = 0

        let didActivate = AppInstanceSelectionPolicy.activateExistingInstanceIfNeeded(
            currentProcessIdentifier: 300,
            currentCodeIdentity: teamIdentity("DEVTEAM", hashByte: 3),
            candidates: [candidate(100)],
            resolveCodeIdentity: { _ in
                resolutionCount += 1
                return self.teamIdentity(
                    "DEVTEAM",
                    hashByte: resolutionCount == 1 ? 3 : 4
                )
            },
            activate: { _ in
                activationCount += 1
                return true
            }
        )

        XCTAssertFalse(didActivate)
        XCTAssertEqual(activationCount, 0)
    }

    private func candidate(
        _ processIdentifier: Int32,
        isTerminated: Bool = false
    ) -> AppInstanceCandidate {
        AppInstanceCandidate(
            processIdentifier: processIdentifier,
            isTerminated: isTerminated
        )
    }

    private var bundleIdentifier: String { "app.devisland.Island" }

    private func teamIdentity(
        _ teamIdentifier: String,
        hashByte: UInt8 = 1
    ) -> AppInstanceCodeIdentity {
        .teamSigned(
            identifier: bundleIdentifier,
            teamIdentifier: teamIdentifier,
            cdHash: Data(repeating: hashByte, count: 20)
        )
    }

    private func adHocIdentity(_ byte: UInt8) -> AppInstanceCodeIdentity {
        .hashBound(
            identifier: bundleIdentifier,
            cdHash: Data(repeating: byte, count: 20)
        )
    }
}
