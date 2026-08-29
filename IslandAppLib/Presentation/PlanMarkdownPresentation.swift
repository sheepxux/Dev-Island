import Foundation

enum PlanMarkdownBlock: Equatable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case unorderedListItem(String)
    case orderedListItem(marker: String, text: String)
    case code(String)
}

/// A deliberately small block parser for the plan-review surface.
/// `AttributedString(markdown:)` retains inline emphasis but flattens block
/// structure when handed to one SwiftUI `Text`, which made headings and list
/// items run together. Plans need only a readable, bounded subset here;
/// richer editing stays in Claude Code via the explicit fallback action.
enum PlanMarkdownPresentation {
    static func blocks(from markdown: String) -> [PlanMarkdownBlock] {
        var result: [PlanMarkdownBlock] = []
        var paragraphLines: [String] = []
        var codeLines: [String] = []
        var isInsideCodeFence = false

        func flushParagraph() {
            guard !paragraphLines.isEmpty else { return }
            result.append(.paragraph(paragraphLines.joined(separator: " ")))
            paragraphLines.removeAll(keepingCapacity: true)
        }

        func flushCode() {
            guard !codeLines.isEmpty else { return }
            result.append(.code(codeLines.joined(separator: "\n")))
            codeLines.removeAll(keepingCapacity: true)
        }

        for rawLine in markdown.components(separatedBy: .newlines) {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") {
                if isInsideCodeFence {
                    flushCode()
                } else {
                    flushParagraph()
                }
                isInsideCodeFence.toggle()
                continue
            }

            if isInsideCodeFence {
                codeLines.append(rawLine)
                continue
            }

            guard !trimmed.isEmpty else {
                flushParagraph()
                continue
            }

            if let heading = heading(from: trimmed) {
                flushParagraph()
                result.append(heading)
                continue
            }

            if let ordered = orderedListItem(from: trimmed) {
                flushParagraph()
                result.append(ordered)
                continue
            }

            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                flushParagraph()
                result.append(.unorderedListItem(String(trimmed.dropFirst(2))))
                continue
            }

            paragraphLines.append(trimmed)
        }

        flushParagraph()
        flushCode()
        return result
    }

    private static func heading(from line: String) -> PlanMarkdownBlock? {
        let level = line.prefix(while: { $0 == "#" }).count
        guard (1...6).contains(level) else { return nil }
        let content = line.dropFirst(level)
        guard content.first == " " else { return nil }
        let text = content.dropFirst().trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        return .heading(level: level, text: text)
    }

    private static func orderedListItem(from line: String) -> PlanMarkdownBlock? {
        guard let separator = line.firstIndex(of: ".") else { return nil }
        let digits = line[..<separator]
        guard !digits.isEmpty, digits.allSatisfy(\.isNumber) else { return nil }
        let remainder = line[line.index(after: separator)...]
        guard remainder.first == " " else { return nil }
        let text = remainder.dropFirst().trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        return .orderedListItem(marker: "\(digits).", text: text)
    }
}
