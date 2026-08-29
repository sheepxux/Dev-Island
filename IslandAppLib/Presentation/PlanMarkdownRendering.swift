import Foundation

/// Immutable UI input for one Plan Review. Both the block parser and
/// Foundation's inline-Markdown parser run before this value reaches SwiftUI,
/// so row/header-local second ticks never parse or rebuild plan content.
enum PlanMarkdownRenderedBlock: Equatable, Sendable {
    case heading(level: Int, text: AttributedString)
    case paragraph(AttributedString)
    case unorderedListItem(AttributedString)
    case orderedListItem(marker: String, text: AttributedString)
    case code(String)
}

struct PlanMarkdownDocument: Equatable, Sendable {
    static let maximumRenderedBlocks = 512

    let blocks: [PlanMarkdownRenderedBlock]
    let isComplete: Bool

    var isReadyForDecision: Bool { isComplete && !blocks.isEmpty }

    static func render(_ markdown: String) -> Self {
        let parsedBlocks = PlanMarkdownPresentation.blocks(from: markdown)
        guard !parsedBlocks.isEmpty,
              parsedBlocks.count <= maximumRenderedBlocks else {
            return Self(blocks: [], isComplete: false)
        }

        return Self(
            blocks: parsedBlocks.map { block in
                switch block {
                case .heading(let level, let text):
                    return .heading(level: level, text: inlineMarkdown(text))
                case .paragraph(let text):
                    return .paragraph(inlineMarkdown(text))
                case .unorderedListItem(let text):
                    return .unorderedListItem(inlineMarkdown(text))
                case .orderedListItem(let marker, let text):
                    return .orderedListItem(
                        marker: marker,
                        text: inlineMarkdown(text)
                    )
                case .code(let code):
                    return .code(code)
                }
            },
            isComplete: true
        )
    }

    private static func inlineMarkdown(_ source: String) -> AttributedString {
        (try? AttributedString(
            markdown: source,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(source)
    }
}

/// Latest-request-wins delivery state. A TimelineView redraw never starts a
/// render; only a new request identity does. Late work from an older request
/// or a surface that has disappeared cannot replace the current document.
struct PlanMarkdownRenderingOperationState: Equatable {
    private(set) var requestID: UUID?
    private(set) var activeOperationID: UUID?
    private(set) var document: PlanMarkdownDocument?

    init(
        requestID: UUID? = nil,
        document: PlanMarkdownDocument? = nil
    ) {
        self.requestID = requestID
        self.document = document
    }

    var isPreparing: Bool { activeOperationID != nil }

    @discardableResult
    mutating func begin(
        requestID: UUID,
        operationID: UUID = UUID()
    ) -> UUID {
        if self.requestID != requestID {
            document = nil
        }
        self.requestID = requestID
        activeOperationID = operationID
        return operationID
    }

    @discardableResult
    mutating func accept(
        _ document: PlanMarkdownDocument,
        requestID: UUID,
        operationID: UUID
    ) -> Bool {
        guard self.requestID == requestID,
              activeOperationID == operationID else {
            return false
        }
        self.document = document
        activeOperationID = nil
        return true
    }

    mutating func invalidate() {
        requestID = nil
        activeOperationID = nil
        document = nil
    }
}

/// Testable hop for the bounded but potentially expensive block and inline
/// Markdown parsers. The result is immutable and Sendable; only its delivery
/// into view state returns to the main actor.
enum PlanMarkdownRenderingExecutor {
    static func run<Value: Sendable>(
        priority: TaskPriority? = nil,
        operation: @escaping @Sendable () -> Value
    ) async -> Value {
        await Task.detached(priority: priority, operation: operation).value
    }

    static func render(_ markdown: String) async -> PlanMarkdownDocument {
        await run(priority: .userInitiated) {
            PlanMarkdownDocument.render(markdown)
        }
    }
}
