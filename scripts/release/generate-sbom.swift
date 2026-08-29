#!/usr/bin/env swift

import CryptoKit
import Darwin
import Foundation

private struct ToolFailure: Error, CustomStringConvertible {
    let description: String
}

private struct ResolvedFile: Codable {
    let version: Int
    var pins: [Pin]
}

private struct Pin: Codable {
    let identity: String
    let kind: String
    let location: String
    let state: State

    struct State: Codable {
        let revision: String?
        let version: String?
    }
}

private struct BrandAssetManifest: Codable {
    let schemaVersion: Int
    let assets: [BrandAsset]
}

private struct BrandAsset: Codable {
    let id: String
    let displayName: String
    let sourceFile: String
    let sourceSHA256: String
    let bundleFiles: [BrandBundleFile]
    let upstream: BrandUpstream
    let assetLicense: String
    let bundledNotice: String
    let bundledNoticeSHA256: String
    let provenanceReview: String
    let trademarkReview: String
}

private struct BrandBundleFile: Codable {
    let name: String
    let sha256: String
}

private struct BrandUpstream: Codable {
    let repository: String
    let revision: String
    let path: String
    let version: String
    let sha256: String
    let transform: String
}

private let maximumResolvedBytes = 2 * 1_024 * 1_024
private let maximumHeaderBytes = 8 * 1_024 * 1_024
private let maximumSBOMBytes = 16 * 1_024 * 1_024
private let minimumEpoch: Int64 = 1_577_836_800 // 2020-01-01
private let maximumEpoch: Int64 = 4_102_444_800 // 2100-01-01
private let rootSPDXID = "SPDXRef-Package-Dev-Island"
private let tomlPlusPlusSPDXID = "SPDXRef-Package-tomlplusplus"
private let openCodeBrandSPDXID = "SPDXRef-Package-opencode-brand-square"
private let openCodeBrandVersion = "1.18.23"
private let openCodeBrandRevision = "13c27598d35f6f91fa4763a0b61a220ab7fcb263"
private let openCodeBrandSHA256 = "d6a0e3b8a295f413543f41cb73957e670351b5cb088c8d9dbd186b9e9d633cca"
private let openCodeBrandPath =
    "packages/console/app/src/asset/brand/opencode-logo-dark-square.svg"
private let expectedBrandIDs: Set<String> = [
    "claude-code",
    "codex",
    "copilot-cli",
    "cursor",
    "gemini-cli",
    "kimi-code",
    "manus",
    "opencode",
    "qwen-code",
]

private func fail(_ message: String) throws -> Never {
    throw ToolFailure(description: message)
}

private func matches(_ value: String, _ pattern: String) -> Bool {
    value.range(of: pattern, options: .regularExpression) != nil
}

private func readRegularFile(_ path: String, maximumBytes: Int) throws -> Data {
    var info = stat()
    guard lstat(path, &info) == 0,
          (info.st_mode & S_IFMT) == S_IFREG else {
        try fail("input must be a regular non-symlink file: \(path)")
    }
    guard info.st_size >= 0, info.st_size <= maximumBytes else {
        try fail("input exceeds the size limit: \(path)")
    }
    return try Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe)
}

private func licenseInventory(at path: String) throws -> Set<String> {
    var info = stat()
    guard lstat(path, &info) == 0,
          (info.st_mode & S_IFMT) == S_IFDIR else {
        try fail("license inventory must be a regular non-symlink directory")
    }

    let names = try FileManager.default.contentsOfDirectory(atPath: path)
    guard !names.isEmpty else { try fail("license inventory is empty") }
    var result: Set<String> = []
    for name in names.sorted() {
        guard !name.contains("/"), !name.hasPrefix(".") else {
            try fail("license inventory contains an invalid filename")
        }
        let data = try readRegularFile(
            URL(fileURLWithPath: path).appendingPathComponent(name).path,
            maximumBytes: 1 * 1_024 * 1_024
        )
        guard !data.isEmpty else { try fail("license notice is empty: \(name)") }
        result.insert(name)
    }
    return result
}

private func regularDirectoryEntries(at path: String) throws -> [String] {
    var info = stat()
    guard lstat(path, &info) == 0,
          (info.st_mode & S_IFMT) == S_IFDIR else {
        try fail("input must be a regular non-symlink directory: \(path)")
    }
    return try FileManager.default.contentsOfDirectory(atPath: path).sorted()
}

private func reconstructedUpstreamBrandData(
    for asset: BrandAsset,
    sourceData: Data
) throws -> Data {
    switch asset.upstream.transform {
    case "identity":
        return sourceData
    case "append-trailing-lf":
        guard sourceData.last == 0x0A else {
            try fail("brand append-trailing-lf transform is invalid: \(asset.id)")
        }
        return Data(sourceData.dropLast())
    case "octicons-template-v1":
        guard asset.id == "copilot-cli" else {
            try fail("brand transform is not valid for this asset: \(asset.id)")
        }
        let localPrefix = Data(#"<svg fill="currentColor" height="1em" viewBox="0 0 24 24" width="1em" xmlns="http://www.w3.org/2000/svg"><title>GitHub Copilot CLI</title>"#.utf8)
        let upstreamPrefix = Data(#"<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24">"#.utf8)
        guard sourceData.starts(with: localPrefix), sourceData.last == 0x0A else {
            try fail("brand octicons-template-v1 transform is invalid: \(asset.id)")
        }
        var reconstructed = upstreamPrefix
        reconstructed.append(contentsOf: sourceData.dropFirst(localPrefix.count).dropLast())
        return reconstructed
    case "qwen-template-v1":
        guard asset.id == "qwen-code",
              let source = String(data: sourceData, encoding: .utf8) else {
            try fail("brand transform is not valid for this asset: \(asset.id)")
        }
        let marker = #"fill="currentColor""#
        let parts = source.components(separatedBy: marker)
        guard parts.count == 2 else {
            try fail("brand qwen-template-v1 transform is invalid: \(asset.id)")
        }
        return Data((parts[0] + "fill=\"#6D44E8\"" + parts[1]).utf8)
    default:
        try fail("brand upstream transform is invalid: \(asset.id)")
    }
}

private func verifiedBrandAssets(
    manifestData: Data,
    sourceDirectory: String,
    bundleDirectory: String,
    licenseNames: Set<String>,
    licenseDirectory: String
) throws -> [BrandAsset] {
    let manifest: BrandAssetManifest
    do {
        manifest = try JSONDecoder().decode(BrandAssetManifest.self, from: manifestData)
    } catch {
        try fail("brand asset manifest is malformed")
    }
    guard manifest.schemaVersion == 3,
          manifest.assets.count == expectedBrandIDs.count else {
        try fail("brand asset manifest schema or entry count is unsupported")
    }

    var seenIDs: Set<String> = []
    var expectedSources: Set<String> = []
    var expectedBundles: Set<String> = []
    for asset in manifest.assets {
        guard matches(asset.id, #"^[a-z0-9]+(-[a-z0-9]+)*$"#),
              seenIDs.insert(asset.id).inserted,
              asset.displayName.utf8.count <= 80,
              !asset.displayName.isEmpty,
              asset.sourceFile == "\(asset.id).svg",
              matches(asset.sourceSHA256, #"^[0-9a-f]{64}$"#) else {
            try fail("brand asset identity or source metadata is invalid")
        }
        expectedSources.insert(asset.sourceFile)
        let sourceData = try readRegularFile(
            URL(fileURLWithPath: sourceDirectory)
                .appendingPathComponent(asset.sourceFile)
                .path,
            maximumBytes: 1 * 1_024 * 1_024
        )
        guard sha256Hex(sourceData) == asset.sourceSHA256 else {
            try fail("brand source SHA-256 mismatch: \(asset.id)")
        }

        let expectedBundleNames = [
            "AgentLogo-\(asset.id).png",
            "AgentLogo-\(asset.id)@2x.png",
        ]
        guard asset.bundleFiles.map(\.name) == expectedBundleNames else {
            try fail("brand bundle inventory must contain canonical 1x and 2x PNGs: \(asset.id)")
        }
        for bundle in asset.bundleFiles {
            guard matches(bundle.sha256, #"^[0-9a-f]{64}$"#) else {
                try fail("brand bundle SHA-256 is invalid: \(bundle.name)")
            }
            expectedBundles.insert(bundle.name)
            let bundleData = try readRegularFile(
                URL(fileURLWithPath: bundleDirectory)
                    .appendingPathComponent(bundle.name)
                    .path,
                maximumBytes: 1 * 1_024 * 1_024
            )
            guard sha256Hex(bundleData) == bundle.sha256 else {
                try fail("brand bundle SHA-256 mismatch: \(bundle.name)")
            }
        }

        let upstreamFields = [
            asset.upstream.repository,
            asset.upstream.revision,
            asset.upstream.path,
            asset.upstream.sha256,
            asset.upstream.transform,
        ]
        let asserted = upstreamFields.allSatisfy { $0 != "NOASSERTION" }
        let unasserted = upstreamFields.allSatisfy { $0 == "NOASSERTION" }
        guard asserted || unasserted else {
            try fail("brand upstream must be fully asserted or fully NOASSERTION: \(asset.id)")
        }
        if asserted {
            _ = try repositoryName(for: asset.upstream.repository)
            guard matches(asset.upstream.revision, #"^[0-9a-f]{40}$"#),
                  matches(asset.upstream.path, #"^(?!/)(?!.*(^|/)\.\.?/)[A-Za-z0-9._@+/-]+$"#),
                  matches(asset.upstream.sha256, #"^[0-9a-f]{64}$"#) else {
                try fail("brand upstream revision, path, or SHA-256 is invalid: \(asset.id)")
            }
            let upstreamData = try reconstructedUpstreamBrandData(
                for: asset,
                sourceData: sourceData
            )
            guard sha256Hex(upstreamData) == asset.upstream.sha256 else {
                try fail("brand upstream SHA-256 mismatch after transform: \(asset.id)")
            }
        }
        guard asset.upstream.version == "NOASSERTION" ||
                matches(asset.upstream.version, #"^[0-9A-Za-z][0-9A-Za-z.+-]{0,63}$"#),
              asset.assetLicense == "NOASSERTION" ||
                matches(asset.assetLicense, #"^[A-Za-z0-9.+-]{1,64}$"#),
              asset.bundledNotice == "NOASSERTION" ||
                matches(asset.bundledNotice, #"^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$"#),
              asset.bundledNoticeSHA256 == "NOASSERTION" ||
                matches(asset.bundledNoticeSHA256, #"^[0-9a-f]{64}$"#),
              ["required", "reviewed"].contains(asset.provenanceReview),
              ["approved", "required"].contains(asset.trademarkReview) else {
            try fail("brand version, license, notice, or review state is invalid: \(asset.id)")
        }
        if asset.provenanceReview == "reviewed", !asserted {
            try fail("reviewed brand provenance requires asserted upstream: \(asset.id)")
        }
        let hasUnassertedNotice = asset.bundledNotice == "NOASSERTION" &&
            asset.bundledNoticeSHA256 == "NOASSERTION"
        guard (asset.assetLicense == "NOASSERTION") == hasUnassertedNotice else {
            try fail("brand license and notice assertion state must match: \(asset.id)")
        }
        if asset.bundledNotice != "NOASSERTION" {
            guard licenseNames.contains(asset.bundledNotice) else {
                try fail("brand asset notice is absent from the packaged inventory: \(asset.id)")
            }
            let noticeData = try readRegularFile(
                URL(fileURLWithPath: licenseDirectory)
                    .appendingPathComponent(asset.bundledNotice)
                    .path,
                maximumBytes: 1 * 1_024 * 1_024
            )
            guard sha256Hex(noticeData) == asset.bundledNoticeSHA256 else {
                try fail("brand notice SHA-256 mismatch: \(asset.id)")
            }
        }
    }
    guard seenIDs == expectedBrandIDs else {
        try fail("brand asset manifest does not contain the exact supported Agent set")
    }

    let actualSources = try regularDirectoryEntries(at: sourceDirectory)
        .filter { $0.hasSuffix(".svg") }
    guard Set(actualSources) == expectedSources,
          actualSources.count == expectedSources.count else {
        try fail("brand source directory is not exactly represented by the manifest")
    }
    let actualBundles = try regularDirectoryEntries(at: bundleDirectory)
        .filter { $0.hasPrefix("AgentLogo-") && $0.hasSuffix(".png") }
    guard Set(actualBundles) == expectedBundles,
          actualBundles.count == expectedBundles.count else {
        try fail("brand bundle directory is not exactly represented by the manifest")
    }

    guard let openCode = manifest.assets.first(where: { $0.id == "opencode" }),
          openCode.sourceSHA256 == openCodeBrandSHA256,
          openCode.upstream.version == openCodeBrandVersion,
          openCode.upstream.revision == openCodeBrandRevision,
          openCode.upstream.path == openCodeBrandPath,
          openCode.upstream.sha256 == openCodeBrandSHA256,
          openCode.upstream.transform == "identity",
          openCode.assetLicense == "MIT",
          openCode.bundledNotice == "opencode-MIT-LICENSE",
          openCode.bundledNoticeSHA256 ==
            "625f0f619133f89bbbb2abe37369613dfa1885eba1e50d02170deb62bb42cb6b" else {
        try fail("OpenCode brand asset does not match the reviewed upstream contract")
    }
    guard let kimi = manifest.assets.first(where: { $0.id == "kimi-code" }),
          kimi.assetLicense == "Apache-2.0",
          kimi.bundledNotice == "kimi-code-vscode-Apache-2.0-LICENSE",
          kimi.bundledNoticeSHA256 ==
            "cfc7749b96f63bd31c3c42b5c471bf756814053e847c10f3eb003417bc523d30" else {
        try fail("Kimi Code brand license does not match the reviewed upstream contract")
    }
    guard let qwen = manifest.assets.first(where: { $0.id == "qwen-code" }),
          qwen.assetLicense == "Apache-2.0",
          qwen.bundledNotice ==
            "qwen-code-desktop-Apache-2.0-LICENSE-NOTICE",
          qwen.bundledNoticeSHA256 ==
            "fa668918263f754d5339c3fd84fb65123525e48db72cfbbb3fff250d3775afeb" else {
        try fail("Qwen Code brand license does not match the reviewed upstream contract")
    }
    return manifest.assets.sorted { $0.id < $1.id }
}

private func repositoryName(for location: String) throws -> String {
    guard let components = URLComponents(string: location),
          components.scheme == "https",
          components.host?.lowercased() == "github.com",
          components.user == nil,
          components.password == nil,
          components.query == nil,
          components.fragment == nil else {
        try fail("dependency location must be a credential-free GitHub HTTPS URL")
    }
    var name = components.path.split(separator: "/").last.map(String.init) ?? ""
    if name.hasSuffix(".git") { name.removeLast(4) }
    guard matches(name, #"^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$"#) else {
        try fail("dependency repository name is invalid")
    }
    return name
}

private func macroValue(_ name: String, in header: String) throws -> Int {
    let escaped = NSRegularExpression.escapedPattern(for: name)
    let pattern = #"(?m)^[ \t]*#define[ \t]+"# + escaped + #"[ \t]+([0-9]+)[ \t]*$"#
    let expression = try NSRegularExpression(pattern: pattern)
    let range = NSRange(header.startIndex..<header.endIndex, in: header)
    guard let match = expression.firstMatch(in: header, range: range),
          let capture = Range(match.range(at: 1), in: header),
          let value = Int(header[capture]),
          (0...9_999).contains(value) else {
        try fail("vendored toml++ header is missing canonical \(name)")
    }
    return value
}

private func tomlPlusPlusVersion(from header: String) throws -> String {
    let major = try macroValue("TOML_LIB_MAJOR", in: header)
    let minor = try macroValue("TOML_LIB_MINOR", in: header)
    let patch = try macroValue("TOML_LIB_PATCH", in: header)
    return "\(major).\(minor).\(patch)"
}

private func sha256Hex(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

private func dependencySPDXID(identity: String, revision: String) -> String {
    let sanitized = identity.map { character -> Character in
        character.isLetter || character.isNumber || character == "-" ? character : "-"
    }
    return "SPDXRef-Package-\(String(sanitized))-\(revision.prefix(12))"
}

private func notices(
    for repository: String,
    inventory: Set<String>
) -> [String] {
    inventory.filter { name in
        name.hasPrefix("\(repository)-LICENSE") ||
            name.hasPrefix("\(repository)-COPYING")
    }.sorted()
}

private func githubPURL(repository: String, revision: String) -> String? {
    guard let components = URLComponents(string: repository),
          components.scheme == "https",
          components.host?.lowercased() == "github.com",
          components.user == nil,
          components.password == nil,
          components.query == nil,
          components.fragment == nil else {
        return nil
    }
    let path = components.path.split(separator: "/").map(String.init)
    guard path.count == 2 else { return nil }
    var repositoryName = path[1]
    if repositoryName.hasSuffix(".git") { repositoryName.removeLast(4) }
    guard matches(path[0], #"^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$"#),
          matches(repositoryName, #"^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$"#),
          matches(revision, #"^[0-9a-f]{40}$"#) else {
        return nil
    }
    return "pkg:github/\(path[0])/\(repositoryName)@\(revision)"
}

private func makeSBOM(
    resolvedData: Data,
    productVersion: String,
    sourceRevision: String,
    sourceDateEpoch: Int64,
    licenseNames: Set<String>,
    tomlHeader: String,
    brandAssets: [BrandAsset]
) throws -> Data {
    guard matches(productVersion, #"^(0|[1-9][0-9]{0,3})\.(0|[1-9][0-9]?)\.(0|[1-9][0-9]?)$"#) else {
        try fail("product version must be canonical numeric major.minor.patch")
    }
    guard matches(sourceRevision, #"^[0-9a-f]{40}$"#) else {
        try fail("source revision must be a lowercase 40-character Git SHA")
    }
    guard (minimumEpoch...maximumEpoch).contains(sourceDateEpoch) else {
        try fail("source date epoch is outside the supported range")
    }

    let resolved: ResolvedFile
    do {
        resolved = try JSONDecoder().decode(ResolvedFile.self, from: resolvedData)
    } catch {
        try fail("Package.resolved is malformed")
    }
    guard resolved.version == 3, (1...256).contains(resolved.pins.count) else {
        try fail("Package.resolved schema or dependency count is unsupported")
    }
    guard licenseNames.contains("Dev-Island-LICENSE") else {
        try fail("Dev Island root license is absent from the packaged inventory")
    }
    guard licenseNames.contains("tomlplusplus-LICENSE") else {
        try fail("vendored toml++ license is absent from the packaged inventory")
    }
    guard !brandAssets.isEmpty,
          brandAssets.map(\.id) == brandAssets.map(\.id).sorted(),
          Set(brandAssets.map(\.id)).count == brandAssets.count else {
        try fail("verified brand asset inventory is empty, duplicated, or unsorted")
    }
    for asset in brandAssets where asset.bundledNotice != "NOASSERTION" {
        guard licenseNames.contains(asset.bundledNotice) else {
            try fail("brand asset notice is absent from the packaged inventory: \(asset.id)")
        }
    }

    var seenIdentities: Set<String> = []
    var seenRepositories: Set<String> = []
    var packages: [[String: Any]] = []
    var relationships: [[String: Any]] = [[
        "spdxElementId": "SPDXRef-DOCUMENT",
        "relationshipType": "DESCRIBES",
        "relatedSpdxElement": rootSPDXID,
    ]]

    packages.append([
        "SPDXID": rootSPDXID,
        "name": "Dev Island",
        "versionInfo": productVersion,
        "downloadLocation": "https://github.com/sheepxux/Dev-Island",
        "filesAnalyzed": false,
        "licenseConcluded": "MIT",
        "licenseDeclared": "MIT",
        "copyrightText": "NOASSERTION",
        "primaryPackagePurpose": "APPLICATION",
        "sourceInfo": "Git revision \(sourceRevision)",
        "comment": "Bundled notice: Dev-Island-LICENSE",
        "externalRefs": [[
            "referenceCategory": "PACKAGE-MANAGER",
            "referenceType": "purl",
            "referenceLocator": "pkg:github/sheepxux/Dev-Island@\(productVersion)",
        ]],
    ])

    var swiftTomlID: String?
    for pin in resolved.pins.sorted(by: { $0.identity < $1.identity }) {
        guard matches(pin.identity, #"^[a-z0-9][a-z0-9._-]{0,127}$"#),
              seenIdentities.insert(pin.identity).inserted else {
            try fail("dependency identity is invalid or duplicated")
        }
        guard pin.kind == "remoteSourceControl",
              let version = pin.state.version,
              matches(version, #"^[0-9A-Za-z][0-9A-Za-z.+-]{0,63}$"#),
              let revision = pin.state.revision,
              matches(revision, #"^[0-9a-f]{40}$"#) else {
            try fail("dependency state is not an exact version and revision")
        }
        let repository = try repositoryName(for: pin.location)
        guard seenRepositories.insert(repository).inserted else {
            try fail("dependency repository appears more than once")
        }
        let bundledNotices = notices(for: repository, inventory: licenseNames)
        guard !bundledNotices.isEmpty else {
            try fail("packaged license notice is missing for \(pin.identity)")
        }
        let spdxID = dependencySPDXID(identity: pin.identity, revision: revision)
        if pin.identity == "swift-toml" { swiftTomlID = spdxID }
        packages.append([
            "SPDXID": spdxID,
            "name": pin.identity,
            "versionInfo": version,
            "downloadLocation": pin.location,
            "filesAnalyzed": false,
            "licenseConcluded": "NOASSERTION",
            "licenseDeclared": "NOASSERTION",
            "copyrightText": "NOASSERTION",
            "primaryPackagePurpose": "LIBRARY",
            "sourceInfo": "SwiftPM locked Git revision \(revision)",
            "comment": "Bundled notices: \(bundledNotices.joined(separator: ", "))",
            "externalRefs": [[
                "referenceCategory": "PACKAGE-MANAGER",
                "referenceType": "purl",
                "referenceLocator": "pkg:swift/\(pin.identity)@\(version)",
            ]],
        ])
        relationships.append([
            "spdxElementId": rootSPDXID,
            "relationshipType": "DEPENDS_ON",
            "relatedSpdxElement": spdxID,
        ])
    }

    guard let swiftTomlID else {
        try fail("swift-toml must remain explicit because it vendors toml++")
    }
    let tomlVersion = try tomlPlusPlusVersion(from: tomlHeader)
    packages.append([
        "SPDXID": tomlPlusPlusSPDXID,
        "name": "tomlplusplus",
        "versionInfo": tomlVersion,
        "downloadLocation": "https://github.com/marzer/tomlplusplus",
        "filesAnalyzed": false,
        "licenseConcluded": "MIT",
        "licenseDeclared": "MIT",
        "copyrightText": "NOASSERTION",
        "primaryPackagePurpose": "LIBRARY",
        "sourceInfo": "Vendored single-header component in swift-toml",
        "comment": "Bundled notice: tomlplusplus-LICENSE",
        "externalRefs": [[
            "referenceCategory": "PACKAGE-MANAGER",
            "referenceType": "purl",
            "referenceLocator": "pkg:github/marzer/tomlplusplus@\(tomlVersion)",
        ]],
    ])
    relationships.append([
        "spdxElementId": swiftTomlID,
        "relationshipType": "DEPENDS_ON",
        "relatedSpdxElement": tomlPlusPlusSPDXID,
    ])

    for asset in brandAssets {
        let isOpenCode = asset.id == "opencode"
        let spdxID = isOpenCode
            ? openCodeBrandSPDXID
            : "SPDXRef-Package-agent-brand-\(asset.id)"
        let assertedUpstream = asset.upstream.repository != "NOASSERTION"
        let bundleHashes = asset.bundleFiles
            .map { "\($0.name)=\($0.sha256)" }
            .joined(separator: ", ")
        let sourceInfo: String
        if assertedUpstream {
            sourceInfo = "Official \(asset.displayName) brand asset at Git revision \(asset.upstream.revision); path \(asset.upstream.path); upstream SVG SHA-256 \(asset.upstream.sha256); transform \(asset.upstream.transform); source SVG SHA-256 \(asset.sourceSHA256); shipped PNG SHA-256 \(bundleHashes)"
        } else {
            sourceInfo = "Local \(asset.displayName) brand source awaiting upstream provenance review; source SVG SHA-256 \(asset.sourceSHA256); shipped PNG SHA-256 \(bundleHashes)"
        }
        var package: [String: Any] = [
            "SPDXID": spdxID,
            "name": isOpenCode ? "opencode-logo-dark-square" : "\(asset.id)-agent-brand-assets",
            "downloadLocation": assertedUpstream ? asset.upstream.repository : "NOASSERTION",
            "filesAnalyzed": false,
            "licenseConcluded": asset.assetLicense,
            "licenseDeclared": asset.assetLicense,
            "copyrightText": isOpenCode ? "Copyright (c) 2025 opencode" : "NOASSERTION",
            "primaryPackagePurpose": "FILE",
            "sourceInfo": sourceInfo,
            "comment": "Bundled notice: \(asset.bundledNotice) SHA-256 \(asset.bundledNoticeSHA256); provenanceReview=\(asset.provenanceReview); trademarkReview=\(asset.trademarkReview); nominative use does not imply affiliation or endorsement",
        ]
        if asset.upstream.version != "NOASSERTION" {
            package["versionInfo"] = asset.upstream.version
        }
        if assertedUpstream,
           let purl = githubPURL(
               repository: asset.upstream.repository,
               revision: asset.upstream.revision
           ) {
            package["externalRefs"] = [[
                "referenceCategory": "PACKAGE-MANAGER",
                "referenceType": "purl",
                "referenceLocator": purl,
            ]]
        }
        packages.append(package)
        relationships.append([
            "spdxElementId": rootSPDXID,
            "relationshipType": "CONTAINS",
            "relatedSpdxElement": spdxID,
        ])
    }

    var fixedNoticeNames: Set<String> = [
        "Dev-Island-LICENSE",
        "tomlplusplus-LICENSE",
    ]
    fixedNoticeNames.formUnion(
        brandAssets.map(\.bundledNotice).filter { $0 != "NOASSERTION" }
    )
    for name in licenseNames {
        let represented = fixedNoticeNames.contains(name) || seenRepositories.contains { prefix in
            name == "\(prefix)-LICENSE" ||
                name.hasPrefix("\(prefix)-LICENSE.") ||
                name == "\(prefix)-COPYING" ||
                name.hasPrefix("\(prefix)-COPYING.")
        }
        guard represented else {
            try fail("packaged notice is not represented by the SBOM: \(name)")
        }
    }

    packages.sort {
        ($0["SPDXID"] as? String ?? "") < ($1["SPDXID"] as? String ?? "")
    }
    relationships.sort {
        let lhs = "\($0["spdxElementId"] ?? "")|\($0["relationshipType"] ?? "")|\($0["relatedSpdxElement"] ?? "")"
        let rhs = "\($1["spdxElementId"] ?? "")|\($1["relationshipType"] ?? "")|\($1["relatedSpdxElement"] ?? "")"
        return lhs < rhs
    }

    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    let created = formatter.string(from: Date(timeIntervalSince1970: TimeInterval(sourceDateEpoch)))
    let resolvedHash = sha256Hex(resolvedData)
    let document: [String: Any] = [
        "spdxVersion": "SPDX-2.3",
        "dataLicense": "CC0-1.0",
        "SPDXID": "SPDXRef-DOCUMENT",
        "name": "Dev-Island-\(productVersion)-SBOM",
        "documentNamespace": "https://devisland.app/spdx/dev-island/\(productVersion)/\(sourceRevision)/\(resolvedHash)",
        "creationInfo": [
            "created": created,
            "creators": ["Tool: Dev-Island-release-sbom/1"],
        ],
        "packages": packages,
        "relationships": relationships,
    ]
    guard JSONSerialization.isValidJSONObject(document) else {
        try fail("generated SPDX document is not valid JSON")
    }
    var data = try JSONSerialization.data(
        withJSONObject: document,
        options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    )
    data.append(0x0A)
    guard data.count <= maximumSBOMBytes else {
        try fail("generated SPDX document exceeds GitHub's attestation limit")
    }
    return data
}

private func writeNewFile(_ data: Data, to path: String) throws {
    var info = stat()
    guard lstat(path, &info) != 0, errno == ENOENT else {
        try fail("refusing to overwrite an existing SBOM output")
    }
    let parent = URL(fileURLWithPath: path).deletingLastPathComponent().path
    guard lstat(parent, &info) == 0,
          (info.st_mode & S_IFMT) == S_IFDIR else {
        try fail("SBOM output directory must already exist and not be a symlink")
    }
    // Foundation traps instead of throwing when `.atomic` and
    // `.withoutOverwriting` are combined. The lstat check above rejects an
    // existing file or symlink; atomic writing then replaces only its own
    // same-directory temporary file.
    try data.write(to: URL(fileURLWithPath: path), options: .atomic)
    chmod(path, S_IRUSR | S_IWUSR | S_IRGRP | S_IROTH)
}

private func selfTest() throws {
    let sourceRevision = String(repeating: "a", count: 40)
    let alphaRevision = String(repeating: "b", count: 40)
    let tomlRevision = String(repeating: "c", count: 40)
    let valid = ResolvedFile(
        version: 3,
        pins: [
            Pin(
                identity: "swift-toml",
                kind: "remoteSourceControl",
                location: "https://github.com/mattt/swift-toml.git",
                state: .init(revision: tomlRevision, version: "2.0.0")
            ),
            Pin(
                identity: "alpha",
                kind: "remoteSourceControl",
                location: "https://github.com/example/Alpha.git",
                state: .init(revision: alphaRevision, version: "1.2.3")
            ),
        ]
    )
    let resolvedData = try JSONEncoder().encode(valid)
    let licenses: Set<String> = [
        "Dev-Island-LICENSE",
        "Alpha-LICENSE.txt",
        "swift-toml-LICENSE.md",
        "tomlplusplus-LICENSE",
        "opencode-MIT-LICENSE",
    ]
    let header = """
    #define TOML_LIB_MAJOR 3
    #define TOML_LIB_MINOR 4
    #define TOML_LIB_PATCH 0
    """
    let brands = [BrandAsset(
        id: "opencode",
        displayName: "OpenCode",
        sourceFile: "opencode.svg",
        sourceSHA256: openCodeBrandSHA256,
        bundleFiles: [
            BrandBundleFile(
                name: "AgentLogo-opencode.png",
                sha256: String(repeating: "d", count: 64)
            ),
            BrandBundleFile(
                name: "AgentLogo-opencode@2x.png",
                sha256: String(repeating: "e", count: 64)
            ),
        ],
        upstream: BrandUpstream(
            repository: "https://github.com/anomalyco/opencode",
            revision: openCodeBrandRevision,
            path: openCodeBrandPath,
            version: openCodeBrandVersion,
            sha256: openCodeBrandSHA256,
            transform: "identity"
        ),
        assetLicense: "MIT",
        bundledNotice: "opencode-MIT-LICENSE",
        bundledNoticeSHA256:
            "625f0f619133f89bbbb2abe37369613dfa1885eba1e50d02170deb62bb42cb6b",
        provenanceReview: "reviewed",
        trademarkReview: "required"
    )]
    let first = try makeSBOM(
        resolvedData: resolvedData,
        productVersion: "0.3.0",
        sourceRevision: sourceRevision,
        sourceDateEpoch: 1_787_688_000,
        licenseNames: licenses,
        tomlHeader: header,
        brandAssets: brands
    )
    let second = try makeSBOM(
        resolvedData: resolvedData,
        productVersion: "0.3.0",
        sourceRevision: sourceRevision,
        sourceDateEpoch: 1_787_688_000,
        licenseNames: licenses,
        tomlHeader: header,
        brandAssets: brands
    )
    guard first == second,
          let object = try JSONSerialization.jsonObject(with: first) as? [String: Any],
          object["spdxVersion"] as? String == "SPDX-2.3",
          (object["packages"] as? [[String: Any]])?.count == 5,
          String(data: first, encoding: .utf8)?.contains("tomlplusplus@3.4.0") == true,
          String(data: first, encoding: .utf8)?.contains(openCodeBrandSHA256) == true else {
        try fail("deterministic SPDX self-test failed")
    }

    let temporaryDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("dev-island-sbom-self-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(
        at: temporaryDirectory,
        withIntermediateDirectories: false
    )
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
    let temporaryOutput = temporaryDirectory.appendingPathComponent("sbom.json").path
    try writeNewFile(first, to: temporaryOutput)
    guard try readRegularFile(temporaryOutput, maximumBytes: maximumSBOMBytes) == first else {
        try fail("SPDX file-write self-test failed")
    }
    var overwriteRejected = false
    do {
        try writeNewFile(second, to: temporaryOutput)
    } catch is ToolFailure {
        overwriteRejected = true
    }
    guard overwriteRejected else {
        try fail("SPDX output overwrite self-test unexpectedly succeeded")
    }

    var duplicate = valid
    duplicate.pins.append(valid.pins[1])
    let invalidCases: [(ResolvedFile, Set<String>, String)] = [
        (duplicate, licenses, header),
        (valid, licenses.subtracting(["Alpha-LICENSE.txt"]), header),
        (valid, licenses.subtracting(["opencode-MIT-LICENSE"]), header),
        (valid, licenses, "#define TOML_LIB_MAJOR 3"),
        (
            ResolvedFile(
                version: 3,
                pins: valid.pins.map { pin in
                    pin.identity == "alpha"
                        ? Pin(
                            identity: pin.identity,
                            kind: pin.kind,
                            location: pin.location,
                            state: .init(revision: "not-a-revision", version: pin.state.version)
                        )
                        : pin
                }
            ),
            licenses,
            header
        ),
    ]
    for (resolved, inventory, candidateHeader) in invalidCases {
        var rejected = false
        do {
            _ = try makeSBOM(
                resolvedData: JSONEncoder().encode(resolved),
                productVersion: "0.3.0",
                sourceRevision: sourceRevision,
                sourceDateEpoch: 1_787_688_000,
                licenseNames: inventory,
                tomlHeader: candidateHeader,
                brandAssets: brands
            )
        } catch is ToolFailure {
            rejected = true
        }
        guard rejected else {
            try fail("negative SPDX self-test unexpectedly succeeded")
        }
    }
    var duplicateBrandRejected = false
    do {
        _ = try makeSBOM(
            resolvedData: resolvedData,
            productVersion: "0.3.0",
            sourceRevision: sourceRevision,
            sourceDateEpoch: 1_787_688_000,
            licenseNames: licenses,
            tomlHeader: header,
            brandAssets: brands + brands
        )
    } catch is ToolFailure {
        duplicateBrandRejected = true
    }
    guard duplicateBrandRejected else {
        try fail("duplicated brand asset self-test unexpectedly succeeded")
    }
    print("SBOM generator self-test: PASS")
}

private func main() throws {
    let arguments = Array(CommandLine.arguments.dropFirst())
    if arguments == ["--self-test"] {
        try selfTest()
        return
    }

    var options: [String: String] = [:]
    var index = 0
    while index < arguments.count {
        let key = arguments[index]
        guard key.hasPrefix("--"), index + 1 < arguments.count,
              options[key] == nil else {
            try fail("invalid or duplicated command-line option")
        }
        options[key] = arguments[index + 1]
        index += 2
    }
    let allowed: Set<String> = [
        "--package-resolved",
        "--version-file",
        "--licenses-dir",
        "--toml-header",
        "--brand-manifest",
        "--brand-source-dir",
        "--brand-bundle-dir",
        "--source-revision",
        "--source-date-epoch",
        "--output",
        "--check",
    ]
    guard Set(options.keys).isSubset(of: allowed),
          let resolvedPath = options["--package-resolved"],
          let versionPath = options["--version-file"],
          let licensesPath = options["--licenses-dir"],
          let headerPath = options["--toml-header"],
          let brandManifestPath = options["--brand-manifest"],
          let brandSourceDirectory = options["--brand-source-dir"],
          let brandBundleDirectory = options["--brand-bundle-dir"],
          let sourceRevision = options["--source-revision"],
          let epochText = options["--source-date-epoch"],
          let sourceDateEpoch = Int64(epochText),
          (options["--output"] == nil) != (options["--check"] == nil) else {
        try fail("required SBOM arguments are missing or conflicting")
    }

    let resolvedData = try readRegularFile(resolvedPath, maximumBytes: maximumResolvedBytes)
    let versionData = try readRegularFile(versionPath, maximumBytes: 128)
    let headerData = try readRegularFile(headerPath, maximumBytes: maximumHeaderBytes)
    let brandManifestData = try readRegularFile(
        brandManifestPath,
        maximumBytes: 1 * 1_024 * 1_024
    )
    let licenseNames = try licenseInventory(at: licensesPath)
    guard let productVersion = String(data: versionData, encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines),
        let tomlHeader = String(data: headerData, encoding: .utf8) else {
        try fail("version or vendored header is not UTF-8")
    }
    let generated = try makeSBOM(
        resolvedData: resolvedData,
        productVersion: productVersion,
        sourceRevision: sourceRevision,
        sourceDateEpoch: sourceDateEpoch,
        licenseNames: licenseNames,
        tomlHeader: tomlHeader,
        brandAssets: try verifiedBrandAssets(
            manifestData: brandManifestData,
            sourceDirectory: brandSourceDirectory,
            bundleDirectory: brandBundleDirectory,
            licenseNames: licenseNames,
            licenseDirectory: licensesPath
        )
    )

    if let output = options["--output"] {
        try writeNewFile(generated, to: output)
        print("SPDX SBOM: \(output)")
    } else if let check = options["--check"] {
        let actual = try readRegularFile(check, maximumBytes: maximumSBOMBytes)
        guard actual == generated else {
            try fail("SBOM does not match the canonical locked dependency inventory")
        }
        print("SPDX SBOM verification: PASS")
    }
}

do {
    try main()
} catch {
    fputs("error: \(error)\n", stderr)
    exit(1)
}
