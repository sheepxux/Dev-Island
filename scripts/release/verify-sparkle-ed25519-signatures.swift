#!/usr/bin/env swift

import CryptoKit
import Darwin
import Foundation

private let maximumInputBytes: Int64 = 1_073_741_824

private func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(1)
}

private struct FileIdentity: Equatable {
    let device: dev_t
    let inode: ino_t
    let owner: uid_t
    let mode: mode_t
    let linkCount: nlink_t
    let size: off_t
    let modifiedSeconds: Int
    let modifiedNanoseconds: Int
    let changedSeconds: Int
    let changedNanoseconds: Int

    init(_ value: stat) {
        device = value.st_dev
        inode = value.st_ino
        owner = value.st_uid
        mode = value.st_mode
        linkCount = value.st_nlink
        size = value.st_size
        modifiedSeconds = value.st_mtimespec.tv_sec
        modifiedNanoseconds = value.st_mtimespec.tv_nsec
        changedSeconds = value.st_ctimespec.tv_sec
        changedNanoseconds = value.st_ctimespec.tv_nsec
    }
}

private func readStableRegularFile(_ path: String) -> Data {
    let descriptor = open(path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
    guard descriptor >= 0 else {
        fail("Ed25519 input could not be opened safely")
    }
    defer { close(descriptor) }

    var beforeValue = stat()
    guard fstat(descriptor, &beforeValue) == 0 else {
        fail("Ed25519 input metadata could not be read")
    }
    let before = FileIdentity(beforeValue)
    guard (before.mode & S_IFMT) == S_IFREG,
          before.owner == getuid(),
          before.linkCount == 1,
          (before.mode & 0o022) == 0 else {
        fail("Ed25519 input file identity is unsafe")
    }
    guard before.size > 0, before.size <= maximumInputBytes else {
        fail("Ed25519 input size is outside the supported bound")
    }

    var contents = Data()
    contents.reserveCapacity(Int(before.size))
    var buffer = [UInt8](repeating: 0, count: 1_048_576)
    while contents.count < before.size {
        let remaining = Int(before.size) - contents.count
        let requested = min(buffer.count, remaining)
        let count = read(descriptor, &buffer, requested)
        if count < 0 && errno == EINTR {
            continue
        }
        guard count > 0 else {
            fail("Ed25519 input read was incomplete")
        }
        contents.append(contentsOf: buffer[..<count])
    }

    var trailingByte: UInt8 = 0
    let trailingCount = read(descriptor, &trailingByte, 1)
    guard trailingCount == 0 else {
        fail("Ed25519 input changed while being read")
    }

    var afterValue = stat()
    guard fstat(descriptor, &afterValue) == 0,
          FileIdentity(afterValue) == before else {
        fail("Ed25519 input changed while being read")
    }
    return contents
}

private func strictBase64(_ value: String, byteCount: Int, label: String) -> Data {
    guard !value.isEmpty,
          value.unicodeScalars.allSatisfy({ scalar in
              (65...90).contains(scalar.value) ||
              (97...122).contains(scalar.value) ||
              (48...57).contains(scalar.value) ||
              scalar.value == 43 || scalar.value == 47 || scalar.value == 61
          }),
          let decoded = Data(base64Encoded: value),
          decoded.count == byteCount,
          decoded.base64EncodedString() == value else {
        fail("\(label) is not canonical base64 with the required length")
    }
    return decoded
}

private func parseOptions(_ arguments: ArraySlice<String>, allowed: Set<String>) -> [String: String] {
    var options: [String: String] = [:]
    var index = arguments.startIndex
    while index < arguments.endIndex {
        let name = arguments[index]
        guard allowed.contains(name) else {
            fail("Ed25519 verifier received an unsupported option")
        }
        let valueIndex = arguments.index(after: index)
        guard valueIndex < arguments.endIndex,
              !arguments[valueIndex].isEmpty,
              options[name] == nil else {
            fail("Ed25519 verifier received a missing or duplicate option")
        }
        options[name] = arguments[valueIndex]
        index = arguments.index(after: valueIndex)
    }
    guard Set(options.keys) == allowed else {
        fail("Ed25519 verifier did not receive the complete option set")
    }
    return options
}

private func decimalLength(_ value: String, maximum: Int) -> Int {
    guard value.range(of: #"\A(?:0|[1-9][0-9]*)\z"#, options: .regularExpression) != nil,
          let parsed = Int(value),
          parsed > 0,
          parsed <= maximum else {
        fail("signed feed prefix length is invalid")
    }
    return parsed
}

private func publicKey(from value: String) -> Curve25519.Signing.PublicKey {
    let rawKey = strictBase64(value, byteCount: 32, label: "Sparkle public key")
    do {
        return try Curve25519.Signing.PublicKey(rawRepresentation: rawKey)
    } catch {
        fail("Sparkle public key is not a valid Ed25519 public key")
    }
}

private func validSignature(
    _ signatureValue: String,
    publicKey: Curve25519.Signing.PublicKey,
    payload: Data,
    label: String
) -> Bool {
    let signature = strictBase64(signatureValue, byteCount: 64, label: label)
    return publicKey.isValidSignature(signature, for: payload)
}

let arguments = CommandLine.arguments.dropFirst()
guard let mode = arguments.first else {
    fail("Ed25519 verifier mode is required")
}

switch mode {
case "verify-file":
    let allowed: Set<String> = [
        "--public-key-base64",
        "--signature-base64",
        "--input-file",
    ]
    let options = parseOptions(arguments.dropFirst(), allowed: allowed)
    let key = publicKey(from: options["--public-key-base64"]!)
    let payload = readStableRegularFile(options["--input-file"]!)
    guard validSignature(
        options["--signature-base64"]!,
        publicKey: key,
        payload: payload,
        label: "Ed25519 signature"
    ) else {
        fail("Ed25519 signature does not match the supplied public key and file")
    }
    print("Ed25519 file signature: PASS")

case "verify-sparkle":
    let allowed: Set<String> = [
        "--public-key-base64",
        "--archive-file",
        "--archive-signature-base64",
        "--feed-file",
        "--feed-signature-base64",
        "--feed-prefix-length",
    ]
    let options = parseOptions(arguments.dropFirst(), allowed: allowed)
    let key = publicKey(from: options["--public-key-base64"]!)

    let archive = readStableRegularFile(options["--archive-file"]!)
    guard validSignature(
        options["--archive-signature-base64"]!,
        publicKey: key,
        payload: archive,
        label: "Sparkle archive Ed25519 signature"
    ) else {
        fail("Sparkle archive Ed25519 signature verification failed")
    }

    let feed = readStableRegularFile(options["--feed-file"]!)
    let prefixLength = decimalLength(
        options["--feed-prefix-length"]!,
        maximum: feed.count
    )
    let signedPrefix = Data(feed.prefix(prefixLength))
    guard validSignature(
        options["--feed-signature-base64"]!,
        publicKey: key,
        payload: signedPrefix,
        label: "Sparkle feed Ed25519 signature"
    ) else {
        fail("Sparkle feed Ed25519 signature verification failed")
    }
    print("Sparkle Ed25519 signatures: PASS")

default:
    fail("Ed25519 verifier mode is unsupported")
}
