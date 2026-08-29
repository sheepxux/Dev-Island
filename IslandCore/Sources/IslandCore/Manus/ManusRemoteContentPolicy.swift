import Foundation

/// Bounded trust boundary for Manus-authored identifiers and user-visible
/// strings before they can enter SwiftUI or SQLite.
enum ManusRemoteContentPolicy {
    static let maximumResponseBytes = 1_048_576
    static let maximumTaskCount = 1_000
    static let maximumAttachmentCount = 64

    static func isValidOpaqueIdentifier(_ value: String, maximumBytes: Int = 256) -> Bool {
        let bytes = value.utf8
        guard !bytes.isEmpty, bytes.count <= maximumBytes else { return false }
        return bytes.allSatisfy { byte in
            (byte >= 0x30 && byte <= 0x39) ||
                (byte >= 0x41 && byte <= 0x5a) ||
                (byte >= 0x61 && byte <= 0x7a) ||
                byte == 0x2d || byte == 0x5f
        }
    }

    static func isValidEventIdentifier(_ value: String) -> Bool {
        let bytes = value.utf8
        return !bytes.isEmpty &&
            bytes.count <= 512 &&
            bytes.allSatisfy { 0x21...0x7e ~= $0 }
    }

    static func isValidTitle(_ value: String) -> Bool {
        isBoundedText(value, maximumBytes: 1_024, allowsEmpty: false)
    }

    static func isValidMessage(_ value: String) -> Bool {
        isBoundedText(value, maximumBytes: 16_384, allowsEmpty: true)
    }

    static func isValidAttachmentName(_ value: String) -> Bool {
        isBoundedText(value, maximumBytes: 512, allowsEmpty: false)
    }

    static func isValidAttachmentURL(_ value: String) -> Bool {
        let bytes = value.utf8
        return !bytes.isEmpty && bytes.count <= 2_048
    }

    static func isValidTimestamp(_ value: String) -> Bool {
        let bytes = value.utf8
        return !bytes.isEmpty &&
            bytes.count <= 20 &&
            bytes.allSatisfy { 0x30...0x39 ~= $0 } &&
            TimeInterval(value).map(\.isFinite) == true
    }

    private static func isBoundedText(
        _ value: String,
        maximumBytes: Int,
        allowsEmpty: Bool
    ) -> Bool {
        let count = value.utf8.count
        return (allowsEmpty || count > 0) && count <= maximumBytes
    }
}
