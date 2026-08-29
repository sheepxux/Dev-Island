import Foundation
import TOML

/// One Kimi Code `[[hooks]]` row. Kept independent from the vendor model so
/// the registry remains the source of truth for the exact commands Dev Island
/// owns.
struct TomlHookDefinition: Equatable, Sendable {
    let event: String
    let matcher: String?
    let command: String
    let timeout: Int?
}

/// Parser-validated, byte-preserving maintenance for Kimi Code's
/// `~/.kimi-code/config.toml`.
///
/// A normal TOML encoder would discard comments, reorder keys and normalize
/// user formatting. Instead, Dev Island validates the complete document with
/// a pinned TOML 1.0 parser, then adds/removes only explicitly delimited
/// managed `[[hooks]]` blocks. All bytes outside those blocks survive exactly.
/// Every candidate result is parsed again before an atomic write.
enum TomlHookConfigEditor {

    enum EditError: LocalizedError {
        case unreadableConfig(URL, Error)
        case invalidUTF8(URL)
        case invalidConfig(URL, Error)
        case unrecognizedManagedEntry(URL)
        case malformedManagedBlock(URL)

        var errorDescription: String? {
            switch self {
            case .unreadableConfig(let url, let error):
                return "Couldn't read \(url.path): \(error.localizedDescription)"
            case .invalidUTF8(let url):
                return "\(url.path) must be UTF-8 TOML"
            case .invalidConfig(let url, let error):
                return "Couldn't parse \(url.path) as TOML: \(error.localizedDescription)"
            case .unrecognizedManagedEntry(let url):
                return "\(url.path) contains an unrecognized Dev Island Kimi Hook; no changes were made"
            case .malformedManagedBlock(let url):
                return "\(url.path) contains an incomplete Dev Island managed block; no changes were made"
            }
        }
    }

    static func isInstalled(
        at url: URL,
        definitions: [TomlHookDefinition],
        marker: String
    ) -> Bool {
        guard let data = try? ManagedConfigFile.snapshotIfExists(at: url)?.data,
              let config = try? parsedConfig(from: data, at: url) else {
            return false
        }
        let managed = (config.hooks ?? []).filter { $0.command.contains(marker) }
        guard managed.count == definitions.count else { return false }
        return definitions.allSatisfy { expected in
            managed.contains { $0.definition == expected }
        }
    }

    static func containsManagedEntries(at url: URL, marker: String) -> Bool {
        guard let data = ManagedConfigFile.boundedReadForManagedMarker(at: url) else {
            return false
        }
        do {
            let config = try parsedConfig(from: data, at: url)
            return (config.hooks ?? []).contains { $0.command.contains(marker) }
                || ((try? managedBlockRanges(in: data, at: url, marker: marker).isEmpty) == false)
        } catch {
            // Match the JSON editor's fail-closed maintenance behavior: a
            // malformed file that still contains our endpoint must not be
            // reported as safely disconnected.
            return data.range(of: Data(marker.utf8)) != nil
        }
    }

    static func install(
        at url: URL,
        definitions: [TomlHookDefinition],
        marker: String
    ) throws {
        let originalSnapshot = try ManagedConfigFile.snapshotIfExists(at: url)
        let original = originalSnapshot?.data ?? Data()

        _ = try parsedConfig(from: original, at: url)
        let base = try preparedUninstall(from: original, at: url, marker: marker) ?? original
        var updated = base
        appendManagedBlocks(definitions, marker: marker, to: &updated)

        _ = try parsedConfig(from: updated, at: url)
        guard isInstalled(in: updated, at: url, definitions: definitions, marker: marker) else {
            throw EditError.malformedManagedBlock(url)
        }
        try HookConfigEditor.writeData(
            updated,
            to: url,
            expecting: originalSnapshot.map(ManagedConfigFile.ExpectedState.snapshot) ?? .absent
        )
    }

    static func uninstall(at url: URL, marker: String) throws {
        guard let original = try ManagedConfigFile.snapshotIfExists(at: url),
              let data = try preparedUninstall(
                from: original.data,
                at: url,
                marker: marker
              ) else { return }
        try HookConfigEditor.writeData(data, to: url, expecting: .snapshot(original))
    }

    static func preparedUninstall(at url: URL, marker: String) throws -> Data? {
        guard let original = try ManagedConfigFile.snapshotIfExists(at: url) else {
            return nil
        }
        return try preparedUninstall(from: original.data, at: url, marker: marker)
    }

    static func preparedUninstall(
        from original: Data,
        at url: URL,
        marker: String
    ) throws -> Data? {
        let config: ParsedConfig
        do {
            config = try parsedConfig(from: original, at: url)
        } catch {
            guard original.range(of: Data(marker.utf8)) != nil else { return nil }
            throw error
        }

        let managedHooks = (config.hooks ?? []).filter { $0.command.contains(marker) }
        let ranges = try managedBlockRanges(in: original, at: url, marker: marker)
        guard !managedHooks.isEmpty || !ranges.isEmpty else { return nil }
        guard managedHooks.count == ranges.count else {
            throw EditError.unrecognizedManagedEntry(url)
        }

        for range in ranges {
            let body = Data(original[range.body])
            let parsed = try parsedConfig(from: body, at: url)
            guard let hooks = parsed.hooks,
                  hooks.count == 1,
                  hooks[0].command.contains(marker) else {
                throw EditError.malformedManagedBlock(url)
            }
        }

        var updated = original
        for range in ranges.reversed() {
            updated.removeSubrange(range.full)
        }
        let result = try parsedConfig(from: updated, at: url)
        guard !(result.hooks ?? []).contains(where: { $0.command.contains(marker) }) else {
            throw EditError.unrecognizedManagedEntry(url)
        }
        return updated
    }

    // MARK: - Parsing and rendering

    private struct ParsedConfig: Decodable {
        let hooks: [ParsedHook]?
    }

    private struct ParsedHook: Decodable {
        let event: String
        let matcher: String?
        let command: String
        let timeout: Int?

        private struct Key: CodingKey, Hashable {
            let stringValue: String
            let intValue: Int?

            init?(stringValue: String) {
                self.stringValue = stringValue
                self.intValue = nil
            }

            init?(intValue: Int) {
                self.stringValue = String(intValue)
                self.intValue = intValue
            }
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: Key.self)
            let allowed = Set(["event", "matcher", "command", "timeout"])
            let unknown = Set(container.allKeys.map(\.stringValue)).subtracting(allowed)
            guard unknown.isEmpty else {
                throw DecodingError.dataCorrupted(.init(
                    codingPath: decoder.codingPath,
                    debugDescription: "Unknown Kimi Hook fields: \(unknown.sorted().joined(separator: ", "))"
                ))
            }

            let eventKey = Key(stringValue: "event")!
            let matcherKey = Key(stringValue: "matcher")!
            let commandKey = Key(stringValue: "command")!
            let timeoutKey = Key(stringValue: "timeout")!
            event = try container.decode(String.self, forKey: eventKey)
            matcher = try container.decodeIfPresent(String.self, forKey: matcherKey)
            command = try container.decode(String.self, forKey: commandKey)
            timeout = try container.decodeIfPresent(Int.self, forKey: timeoutKey)
        }

        var definition: TomlHookDefinition {
            TomlHookDefinition(
                event: event,
                matcher: matcher,
                command: command,
                timeout: timeout
            )
        }
    }

    private static func parsedConfig(from data: Data, at url: URL) throws -> ParsedConfig {
        guard String(data: data, encoding: .utf8) != nil else {
            throw EditError.invalidUTF8(url)
        }
        do {
            return try TOMLDecoder().decode(ParsedConfig.self, from: data)
        } catch {
            throw EditError.invalidConfig(url, error)
        }
    }

    private static func isInstalled(
        in data: Data,
        at url: URL,
        definitions: [TomlHookDefinition],
        marker: String
    ) -> Bool {
        guard let config = try? parsedConfig(from: data, at: url) else { return false }
        let managed = (config.hooks ?? []).filter { $0.command.contains(marker) }
        guard managed.count == definitions.count else { return false }
        return definitions.allSatisfy { expected in
            managed.contains { $0.definition == expected }
        }
    }

    private static func renderedBlock(
        _ definition: TomlHookDefinition,
        marker: String,
        ownsLeadingNewline: Bool
    ) -> Data {
        var lines = [
            startMarker(marker, ownsLeadingNewline: ownsLeadingNewline),
            "[[hooks]]",
            "event = \(tomlString(definition.event))",
        ]
        if let matcher = definition.matcher {
            lines.append("matcher = \(tomlString(matcher))")
        }
        lines.append("command = \(tomlString(definition.command))")
        if let timeout = definition.timeout {
            lines.append("timeout = \(timeout)")
        }
        lines.append(endMarker(marker))
        return Data((lines.joined(separator: "\n") + "\n").utf8)
    }

    /// Append blocks without touching any existing byte. If a non-empty
    /// config has no trailing newline, the first block owns the one delimiter
    /// newline needed to start a TOML comment on a new line. Its distinct
    /// marker lets uninstall remove that byte as part of the managed range,
    /// restoring the original document exactly. Subsequent blocks start
    /// immediately after the previous managed block's trailing newline.
    private static func appendManagedBlocks(
        _ definitions: [TomlHookDefinition],
        marker: String,
        to data: inout Data
    ) {
        guard !definitions.isEmpty else { return }
        for (index, definition) in definitions.enumerated() {
            let ownsLeadingNewline = index == 0 && !data.isEmpty && data.last != 0x0A
            if ownsLeadingNewline { data.append(0x0A) }
            data.append(renderedBlock(
                definition,
                marker: marker,
                ownsLeadingNewline: ownsLeadingNewline
            ))
        }
    }

    private static func tomlString(_ value: String) -> String {
        var escaped = value.replacingOccurrences(of: "\\", with: "\\\\")
        escaped = escaped.replacingOccurrences(of: "\"", with: "\\\"")
        escaped = escaped.replacingOccurrences(of: "\n", with: "\\n")
        escaped = escaped.replacingOccurrences(of: "\r", with: "\\r")
        escaped = escaped.replacingOccurrences(of: "\t", with: "\\t")
        return "\"\(escaped)\""
    }

    // MARK: - Managed block scanner

    private struct ManagedBlockRange {
        let full: Range<Data.Index>
        let body: Range<Data.Index>
    }

    private struct OpenManagedBlock {
        let fullStart: Data.Index
        let bodyStart: Data.Index
    }

    private enum StringMode: Equatable {
        case none
        case basic
        case literal
        case multilineBasic
        case multilineLiteral
    }

    /// Locate marker comments only when they are real TOML comments. This
    /// prevents marker-looking text inside basic/literal multiline strings
    /// from being treated as an editable boundary.
    private static func managedBlockRanges(
        in data: Data,
        at url: URL,
        marker: String
    ) throws -> [ManagedBlockRange] {
        let startText = startMarker(marker, ownsLeadingNewline: false)
        let owningStartText = startMarker(marker, ownsLeadingNewline: true)
        let endText = endMarker(marker)
        var mode = StringMode.none
        var cursor = data.startIndex
        var open: OpenManagedBlock?
        var ranges: [ManagedBlockRange] = []

        while cursor < data.endIndex {
            let newline = data[cursor...].firstIndex(of: 0x0A)
            let lineEnd = newline ?? data.endIndex
            let fullEnd = newline.map { data.index(after: $0) } ?? data.endIndex
            let modeAtLineStart = mode

            if modeAtLineStart == .none,
               let comment = topLevelCommentText(in: data[cursor..<lineEnd]) {
                if comment == startText || comment == owningStartText {
                    guard open == nil else { throw EditError.malformedManagedBlock(url) }
                    let fullStart: Data.Index
                    if comment == owningStartText {
                        guard cursor > data.startIndex else {
                            throw EditError.malformedManagedBlock(url)
                        }
                        let delimiter = data.index(before: cursor)
                        guard data[delimiter] == 0x0A else {
                            throw EditError.malformedManagedBlock(url)
                        }
                        fullStart = delimiter
                    } else {
                        fullStart = cursor
                    }
                    open = OpenManagedBlock(fullStart: fullStart, bodyStart: fullEnd)
                } else if comment == endText {
                    guard let current = open else { throw EditError.malformedManagedBlock(url) }
                    ranges.append(ManagedBlockRange(
                        full: current.fullStart..<fullEnd,
                        body: current.bodyStart..<cursor
                    ))
                    open = nil
                }
            }

            scanLine(data[cursor..<lineEnd], mode: &mode)
            cursor = fullEnd
        }

        guard open == nil else { throw EditError.malformedManagedBlock(url) }
        return ranges
    }

    private static func topLevelCommentText(
        in line: Data.SubSequence
    ) -> String? {
        var index = line.startIndex
        while index < line.endIndex && (line[index] == 0x20 || line[index] == 0x09) {
            index = line.index(after: index)
        }
        guard index < line.endIndex, line[index] == 0x23 else { return nil }
        var bytes = Data(line[index..<line.endIndex])
        while let last = bytes.last, last == 0x20 || last == 0x09 || last == 0x0D {
            bytes.removeLast()
        }
        return String(data: bytes, encoding: .utf8)
    }

    private static func scanLine(
        _ line: Data.SubSequence,
        mode: inout StringMode
    ) {
        var index = line.startIndex
        while index < line.endIndex {
            switch mode {
            case .none:
                if line[index] == 0x23 { return } // TOML comment
                if hasTripleQuote(in: line, at: index, quote: 0x22) {
                    mode = .multilineBasic
                    index = line.index(index, offsetBy: 3)
                } else if hasTripleQuote(in: line, at: index, quote: 0x27) {
                    mode = .multilineLiteral
                    index = line.index(index, offsetBy: 3)
                } else if line[index] == 0x22 {
                    mode = .basic
                    index = line.index(after: index)
                } else if line[index] == 0x27 {
                    mode = .literal
                    index = line.index(after: index)
                } else {
                    index = line.index(after: index)
                }

            case .basic:
                if line[index] == 0x5C {
                    index = line.index(after: index)
                    if index < line.endIndex { index = line.index(after: index) }
                } else if line[index] == 0x22 {
                    mode = .none
                    index = line.index(after: index)
                } else {
                    index = line.index(after: index)
                }

            case .literal:
                if line[index] == 0x27 {
                    mode = .none
                }
                index = line.index(after: index)

            case .multilineBasic:
                if hasTripleQuote(in: line, at: index, quote: 0x22) {
                    mode = .none
                    index = line.index(index, offsetBy: 3)
                } else if line[index] == 0x5C {
                    index = line.index(after: index)
                    if index < line.endIndex { index = line.index(after: index) }
                } else {
                    index = line.index(after: index)
                }

            case .multilineLiteral:
                if hasTripleQuote(in: line, at: index, quote: 0x27) {
                    mode = .none
                    index = line.index(index, offsetBy: 3)
                } else {
                    index = line.index(after: index)
                }
            }
        }
        // Basic and literal strings may not span a newline. The full parser
        // rejects such input; resetting here keeps the scanner bounded.
        if mode == .basic || mode == .literal { mode = .none }
    }

    private static func hasTripleQuote(
        in line: Data.SubSequence,
        at index: Data.Index,
        quote: UInt8
    ) -> Bool {
        guard line.distance(from: index, to: line.endIndex) >= 3 else { return false }
        return line[index] == quote
            && line[line.index(after: index)] == quote
            && line[line.index(index, offsetBy: 2)] == quote
    }

    private static func startMarker(
        _ marker: String,
        ownsLeadingNewline: Bool
    ) -> String {
        let ownership = ownsLeadingNewline ? " [owns leading newline]" : ""
        return "# >>> Dev Island managed Hook \(marker)\(ownership)"
    }

    private static func endMarker(_ marker: String) -> String {
        "# <<< Dev Island managed Hook \(marker)"
    }
}
