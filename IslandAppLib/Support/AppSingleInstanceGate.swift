import AppKit
import Security

/// The bounded code identity used for single-instance arbitration.
///
/// A Team ID is the cross-version publisher boundary once Dev Island is
/// Developer-ID signed. Local ad-hoc builds have no publisher certificate, so
/// they deliberately fall back to an exact CDHash match and can trust only a
/// byte-identical copy. Bundle ID alone is never treated as identity.
enum AppInstanceCodeIdentity: Equatable, Sendable {
    case teamSigned(identifier: String, teamIdentifier: String, cdHash: Data)
    case hashBound(identifier: String, cdHash: Data)

    var identifier: String {
        switch self {
        case .teamSigned(let identifier, _, _), .hashBound(let identifier, _):
            return identifier
        }
    }

    func isTrustedPeer(of other: AppInstanceCodeIdentity) -> Bool {
        guard !identifier.isEmpty,
              identifier == other.identifier else {
            return false
        }

        switch (self, other) {
        case let (
            .teamSigned(_, candidateTeam, _),
            .teamSigned(_, currentTeam, _)
        ):
            return !candidateTeam.isEmpty && candidateTeam == currentTeam
        case let (
            .hashBound(_, candidateHash),
            .hashBound(_, currentHash)
        ):
            return !candidateHash.isEmpty && candidateHash == currentHash
        case (.teamSigned, .hashBound), (.hashBound, .teamSigned):
            return false
        }
    }
}

/// The small, deterministic input used to choose which copy of Dev Island
/// owns the current login session.
struct AppInstanceCandidate: Equatable, Sendable {
    let processIdentifier: Int32
    let isTerminated: Bool
}

struct AppInstanceWinner: Equatable, Sendable {
    let processIdentifier: Int32
    let codeIdentity: AppInstanceCodeIdentity
}

/// Pure selection policy kept separate from LaunchServices so simultaneous
/// launches cannot make both copies yield to each other.
enum AppInstanceSelectionPolicy {
    /// Code-signature inspection is synchronous and this gate runs before the
    /// first window. A same-Bundle-ID flood must therefore fail open instead
    /// of creating unbounded launch work on the main actor.
    static let maximumCandidateCount = 32

    static func existingWinner(
        currentProcessIdentifier: Int32,
        currentCodeIdentity: AppInstanceCodeIdentity,
        candidates: [AppInstanceCandidate],
        resolveCodeIdentity: (Int32) -> AppInstanceCodeIdentity?
    ) -> AppInstanceWinner? {
        guard currentProcessIdentifier > 0,
              candidates.count <= maximumCandidateCount else {
            return nil
        }

        // A newcomer can yield only to an older trusted process. Selecting
        // from sorted, deduplicated PIDs makes simultaneous launch decisions
        // deterministic even if LaunchServices briefly omits the current App.
        let olderLiveProcessIdentifiers = Set(candidates.lazy
            .filter {
                !$0.isTerminated
                    && $0.processIdentifier > 0
                    && $0.processIdentifier < currentProcessIdentifier
            }
            .map(\.processIdentifier))
            .sorted()

        for processIdentifier in olderLiveProcessIdentifiers {
            guard let identity = resolveCodeIdentity(processIdentifier),
                  identity.isTrustedPeer(of: currentCodeIdentity) else {
                continue
            }
            return AppInstanceWinner(
                processIdentifier: processIdentifier,
                codeIdentity: identity
            )
        }
        return nil
    }

    /// Re-resolves the selected PID immediately before activation. An exited
    /// process, PID reuse, or signing-identity drift therefore keeps the
    /// current App alive rather than activating an unrelated application and
    /// yielding the real Dev Island owner.
    static func activateExistingInstanceIfNeeded(
        currentProcessIdentifier: Int32,
        currentCodeIdentity: AppInstanceCodeIdentity,
        candidates: [AppInstanceCandidate],
        resolveCodeIdentity: (Int32) -> AppInstanceCodeIdentity?,
        activate: (Int32) -> Bool
    ) -> Bool {
        guard let winner = existingWinner(
            currentProcessIdentifier: currentProcessIdentifier,
            currentCodeIdentity: currentCodeIdentity,
            candidates: candidates,
            resolveCodeIdentity: resolveCodeIdentity
        ),
        let revalidatedIdentity = resolveCodeIdentity(winner.processIdentifier),
        revalidatedIdentity == winner.codeIdentity,
        revalidatedIdentity.isTrustedPeer(of: currentCodeIdentity) else {
            return false
        }

        return activate(winner.processIdentifier)
    }
}

/// Resolves only Security.framework's dynamic PID identity. It never reads a
/// candidate's path, arguments, environment, windows, preferences or IPC.
enum AppInstanceCodeIdentityResolver {
    static func identity(
        processIdentifier: Int32,
        expectedIdentifier: String
    ) -> AppInstanceCodeIdentity? {
        guard processIdentifier > 0,
              !expectedIdentifier.isEmpty else {
            return nil
        }

        let attributes = [
            kSecGuestAttributePid as String: NSNumber(value: processIdentifier),
        ] as CFDictionary
        var dynamicCode: SecCode?
        guard SecCodeCopyGuestWithAttributes(
            nil,
            attributes,
            [],
            &dynamicCode
        ) == errSecSuccess,
        let dynamicCode else {
            return nil
        }

        guard SecCodeCheckValidity(
            dynamicCode,
            [],
            nil
        ) == errSecSuccess else {
            return nil
        }

        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(dynamicCode, [], &staticCode) == errSecSuccess,
              let staticCode else {
            return nil
        }

        var signingInformation: CFDictionary?
        let informationFlags = SecCSFlags(rawValue: kSecCSSigningInformation)
        guard SecCodeCopySigningInformation(
            staticCode,
            informationFlags,
            &signingInformation
        ) == errSecSuccess,
        let information = signingInformation as? [String: Any],
        let signatureFlagsNumber = information[
            kSecCodeInfoFlags as String
        ] as? NSNumber else {
            return nil
        }

        let signatureFlags = SecCodeSignatureFlags(
            rawValue: signatureFlagsNumber.uint32Value
        )
        let identifier = information[kSecCodeInfoIdentifier as String] as? String
        let teamIdentifier = information[
            kSecCodeInfoTeamIdentifier as String
        ] as? String
        let cdHash = information[kSecCodeInfoUnique as String] as? Data

        guard let identity = classifiedIdentity(
            identifier: identifier,
            expectedIdentifier: expectedIdentifier,
            teamIdentifier: teamIdentifier,
            cdHash: cdHash,
            isAdHoc: signatureFlags.contains(.adhoc),
            teamSignatureIsTrusted: { teamIdentifier in
                hasAppleAnchoredTeamSignature(
                    dynamicCode: dynamicCode,
                    identifier: expectedIdentifier,
                    teamIdentifier: teamIdentifier
                )
            }
        ) else {
            return nil
        }

        // Signing information comes from the dynamic code's static origin.
        // Revalidate after reading it so an origin replacement cannot create a
        // validity→identity window. Team identities already performed this
        // second check with their Apple-anchor requirement; ad-hoc identities
        // repeat the default dynamic validation here.
        if case .hashBound = identity,
           SecCodeCheckValidity(dynamicCode, [], nil) != errSecSuccess {
            return nil
        }
        return identity
    }

    /// Pure classification boundary used by deterministic attack regressions.
    /// A missing Team is accepted only when the signature explicitly says it
    /// is ad-hoc; Apple platform code and other signer shapes must not silently
    /// fall through to the local same-CDHash rule.
    static func classifiedIdentity(
        identifier: String?,
        expectedIdentifier: String,
        teamIdentifier: String?,
        cdHash: Data?,
        isAdHoc: Bool,
        teamSignatureIsTrusted: (String) -> Bool
    ) -> AppInstanceCodeIdentity? {
        guard let identifier,
              identifier == expectedIdentifier,
              isSafeCodeIdentifier(identifier),
              let cdHash,
              !cdHash.isEmpty,
              cdHash.count <= 64 else {
            return nil
        }

        let teamIdentifier = teamIdentifier.flatMap { $0.isEmpty ? nil : $0 }
        if isAdHoc {
            guard teamIdentifier == nil else { return nil }
            return .hashBound(identifier: identifier, cdHash: cdHash)
        }

        guard let teamIdentifier,
              isSafeTeamIdentifier(teamIdentifier),
              teamSignatureIsTrusted(teamIdentifier) else {
            return nil
        }
        return .teamSigned(
            identifier: identifier,
            teamIdentifier: teamIdentifier,
            cdHash: cdHash
        )
    }

    private static func hasAppleAnchoredTeamSignature(
        dynamicCode: SecCode,
        identifier: String,
        teamIdentifier: String
    ) -> Bool {
        guard isSafeCodeIdentifier(identifier),
              isSafeTeamIdentifier(teamIdentifier) else {
            return false
        }

        let requirementText = #"anchor apple generic and identifier "\#(identifier)" and certificate leaf[subject.OU] = "\#(teamIdentifier)""#
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(
            requirementText as CFString,
            [],
            &requirement
        ) == errSecSuccess,
        let requirement else {
            return false
        }
        return SecCodeCheckValidity(dynamicCode, [], requirement) == errSecSuccess
    }

    private static func isSafeCodeIdentifier(_ value: String) -> Bool {
        !value.isEmpty
            && value.utf8.count <= 255
            && value.utf8.allSatisfy {
                (48...57).contains($0)
                    || (65...90).contains($0)
                    || (97...122).contains($0)
                    || $0 == 45
                    || $0 == 46
            }
    }

    private static func isSafeTeamIdentifier(_ value: String) -> Bool {
        !value.isEmpty
            && value.utf8.count <= 128
            && value.utf8.allSatisfy {
                (48...57).contains($0)
                    || (65...90).contains($0)
                    || (97...122).contains($0)
            }
    }
}

/// Prevents installed, mounted and development copies with the same bundle ID
/// from running two islands and two local backends at once.
///
/// The oldest trusted live process wins. Team-signed releases trust the same
/// Team across versions; ad-hoc QA builds trust only the same CDHash. The
/// newcomer terminates only after AppKit confirms it could activate that exact
/// revalidated process; every identity or lifecycle failure is fail-open.
@MainActor
public enum AppSingleInstanceGate {
    public static func activateExistingInstanceIfNeeded() -> Bool {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier,
              !bundleIdentifier.isEmpty else {
            return false
        }

        let currentProcessIdentifier = ProcessInfo.processInfo.processIdentifier
        let applications = NSWorkspace.shared.runningApplications.filter {
            $0.bundleIdentifier == bundleIdentifier
        }
        guard applications.count <= AppInstanceSelectionPolicy.maximumCandidateCount,
              let currentCodeIdentity = AppInstanceCodeIdentityResolver.identity(
                processIdentifier: currentProcessIdentifier,
                expectedIdentifier: bundleIdentifier
              ) else {
            return false
        }

        let candidates = applications.map {
            AppInstanceCandidate(
                processIdentifier: $0.processIdentifier,
                isTerminated: $0.isTerminated
            )
        }

        return AppInstanceSelectionPolicy.activateExistingInstanceIfNeeded(
            currentProcessIdentifier: currentProcessIdentifier,
            currentCodeIdentity: currentCodeIdentity,
            candidates: candidates,
            resolveCodeIdentity: { processIdentifier in
                AppInstanceCodeIdentityResolver.identity(
                    processIdentifier: processIdentifier,
                    expectedIdentifier: bundleIdentifier
                )
            },
            activate: { processIdentifier in
                guard let existingApplication = applications.first(where: {
                    $0.processIdentifier == processIdentifier
                        && !$0.isTerminated
                        && $0.bundleIdentifier == bundleIdentifier
                }) else {
                    return false
                }
                return existingApplication.activate(options: [.activateAllWindows])
            }
        )
    }
}
