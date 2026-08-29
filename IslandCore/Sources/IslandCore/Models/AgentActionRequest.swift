import Foundation

/// Unicode-safe display bound. `String.prefix(_:)` counts grapheme clusters;
/// one hostile cluster can contain hundreds of thousands of combining scalars.
/// Enforce both the product's visible-character budget and a real UTF-8 byte
/// budget before text is retained in the pending action queue.
enum AgentActionTextPolicy {
    static func bounded(
        _ value: String,
        maximumCharacters: Int,
        maximumUTF8Bytes: Int
    ) -> String {
        var result = ""
        result.reserveCapacity(min(maximumUTF8Bytes, value.utf8.count))
        var characterCount = 0
        var byteCount = 0

        for character in value {
            guard characterCount < maximumCharacters else { break }
            let fragment = String(character)
            let fragmentBytes = fragment.utf8.count
            guard byteCount + fragmentBytes <= maximumUTF8Bytes else { break }
            result.append(character)
            characterCount += 1
            byteCount += fragmentBytes
        }
        return result
    }

    static func boundedNonempty(
        _ value: String,
        maximumCharacters: Int,
        maximumUTF8Bytes: Int
    ) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let result = bounded(
            trimmed,
            maximumCharacters: maximumCharacters,
            maximumUTF8Bytes: maximumUTF8Bytes
        )
        return result.isEmpty ? nil : result
    }
}

/// One user decision that an agent is synchronously waiting to receive.
public struct AgentActionRequest: Identifiable, Hashable, Sendable {
    public enum Kind: String, Hashable, Sendable {
        case permission
        case question
        case planReview
    }

    public static let defaultTimeout: TimeInterval = 90
    public static let maximumTimeout: TimeInterval = 120
    public static let maximumTitleCharacters = 256
    public static let maximumTitleBytes = 1_024
    public static let maximumMessageCharacters = 1_024
    public static let maximumMessageBytes = 4_096
    public static let maximumDetailCharacters = 4_096
    public static let maximumDetailBytes = 16_384
    public static let maximumQuestions = 4

    public let id: UUID
    public let source: String
    public let sessionId: String
    public let kind: Kind
    public let title: String
    public let message: String
    public let detail: String?
    /// Structured choices for `.question` requests. Permission requests keep
    /// this empty so existing consumers do not need a parallel model.
    public let questions: [AgentQuestion]
    /// Full Markdown and the exact injected `ExitPlanMode` input that must be
    /// echoed back to Claude Code when the user approves the plan.
    public let planReview: AgentPlanReview?
    public let createdAt: Date
    public let expiresAt: Date

    public init(
        id: UUID = UUID(),
        source: String,
        sessionId: String,
        kind: Kind,
        title: String,
        message: String,
        detail: String? = nil,
        questions: [AgentQuestion] = [],
        planReview: AgentPlanReview? = nil,
        createdAt: Date = .now,
        timeout: TimeInterval = Self.defaultTimeout
    ) {
        self.id = id
        self.source = source
        self.sessionId = sessionId
        self.kind = kind
        self.title = AgentActionTextPolicy.bounded(
            title,
            maximumCharacters: Self.maximumTitleCharacters,
            maximumUTF8Bytes: Self.maximumTitleBytes
        )
        self.message = AgentActionTextPolicy.bounded(
            message,
            maximumCharacters: Self.maximumMessageCharacters,
            maximumUTF8Bytes: Self.maximumMessageBytes
        )
        self.detail = detail.map {
            AgentActionTextPolicy.bounded(
                $0,
                maximumCharacters: Self.maximumDetailCharacters,
                maximumUTF8Bytes: Self.maximumDetailBytes
            )
        }
        self.questions = Array(questions.prefix(Self.maximumQuestions))
        self.planReview = planReview
        let safeCreatedAt = createdAt.timeIntervalSinceReferenceDate.isFinite
            ? createdAt
            : .now
        let safeTimeout = timeout.isFinite
            ? min(max(1, timeout), Self.maximumTimeout)
            : Self.defaultTimeout
        self.createdAt = safeCreatedAt
        self.expiresAt = safeCreatedAt.addingTimeInterval(safeTimeout)
    }

    public var taskIdentity: TaskIdentity {
        TaskIdentity(source: source, id: sessionId)
    }
}

/// A bounded Claude Code plan-review document. `originalInputJSON` preserves
/// the complete vendor-injected `tool_input` object so approval can echo it
/// back without dropping fields that a future Claude Code version adds.
public struct AgentPlanReview: Hashable, Sendable {
    public static let maximumMarkdownCharacters = 65_536
    public static let maximumMarkdownBytes = 262_144
    public static let maximumInputBytes = 262_144

    public let markdown: String
    public let originalInputJSON: Data

    public init?(markdown: String, originalInputJSON: Data) {
        let trimmed = markdown.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              markdown.count <= Self.maximumMarkdownCharacters,
              markdown.utf8.count <= Self.maximumMarkdownBytes,
              !originalInputJSON.isEmpty,
              originalInputJSON.count <= Self.maximumInputBytes else {
            return nil
        }
        self.markdown = markdown
        self.originalInputJSON = originalInputJSON
    }
}

/// One documented AskUserQuestion prompt. Question text is the vendor's wire
/// key for the eventual answers object, so decoders reject duplicates before
/// constructing an action request.
public struct AgentQuestion: Identifiable, Hashable, Sendable {
    public static let maximumQuestionCharacters = 512
    public static let maximumQuestionBytes = 2_048
    public static let maximumHeaderCharacters = 64
    public static let maximumHeaderBytes = 256
    public static let maximumOptions = 8

    public let question: String
    public let header: String
    public let options: [AgentQuestionOption]
    public let allowsMultipleSelection: Bool

    public init(
        question: String,
        header: String,
        options: [AgentQuestionOption],
        allowsMultipleSelection: Bool = false
    ) {
        self.question = AgentActionTextPolicy.bounded(
            question,
            maximumCharacters: Self.maximumQuestionCharacters,
            maximumUTF8Bytes: Self.maximumQuestionBytes
        )
        self.header = AgentActionTextPolicy.bounded(
            header,
            maximumCharacters: Self.maximumHeaderCharacters,
            maximumUTF8Bytes: Self.maximumHeaderBytes
        )
        self.options = Array(options.prefix(Self.maximumOptions))
        self.allowsMultipleSelection = allowsMultipleSelection
    }

    public var id: String { question }
}

public struct AgentQuestionOption: Identifiable, Hashable, Sendable {
    public static let maximumLabelCharacters = 128
    public static let maximumLabelBytes = 512
    public static let maximumDescriptionCharacters = 512
    public static let maximumDescriptionBytes = 2_048

    public let label: String
    public let description: String?

    public init(label: String, description: String? = nil) {
        self.label = AgentActionTextPolicy.bounded(
            label,
            maximumCharacters: Self.maximumLabelCharacters,
            maximumUTF8Bytes: Self.maximumLabelBytes
        )
        self.description = description.map {
            AgentActionTextPolicy.bounded(
                $0,
                maximumCharacters: Self.maximumDescriptionCharacters,
                maximumUTF8Bytes: Self.maximumDescriptionBytes
            )
        }
    }

    public var id: String { label }
}

/// One answer remains an ordered list so multi-select wire values can be
/// serialized deterministically in the same order as the visible options.
public struct AgentQuestionAnswer: Hashable, Sendable {
    public let question: String
    public let selectedLabels: [String]

    public init(question: String, selectedLabels: [String]) {
        self.question = question
        self.selectedLabels = selectedLabels
    }

    public var wireValue: String { selectedLabels.joined(separator: ", ") }
}

public struct AgentQuestionSubmission: Hashable, Sendable {
    public let questions: [AgentQuestion]
    public let answers: [AgentQuestionAnswer]

    public init(questions: [AgentQuestion], answers: [AgentQuestionAnswer]) {
        self.questions = questions
        self.answers = answers
    }
}

public enum AgentActionDecision: String, Hashable, Sendable {
    case allow
    case deny
}

/// Vendor-neutral result returned by the island. Permission decisions and
/// structured answers intentionally cannot be confused at compile time.
public enum AgentActionResponse: Hashable, Sendable {
    case permission(AgentActionDecision)
    case question(AgentQuestionSubmission)
    case planReview(AgentActionDecision, AgentPlanReview)
}
