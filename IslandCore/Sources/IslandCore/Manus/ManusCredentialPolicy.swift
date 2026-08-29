/// Shared input boundary for the Manus API credential used by the shipping App
/// and the explicit live-acceptance harness. Prefixes are deliberately not
/// pinned: the verified v1 account and current v2 documentation use different
/// examples, while both are bounded printable ASCII header values.
public enum ManusCredentialPolicy {
    public static let minimumLength = 16
    public static let maximumLength = 512

    public static func validated(_ candidate: String) -> String? {
        let bytes = candidate.utf8
        guard bytes.count >= minimumLength,
              bytes.count <= maximumLength,
              bytes.allSatisfy({ 0x21...0x7e ~= $0 }) else {
            return nil
        }
        return candidate
    }
}
