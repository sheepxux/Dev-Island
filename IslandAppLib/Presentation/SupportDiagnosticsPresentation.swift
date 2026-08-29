import Foundation

/// The two diagnostic actions share one surface and must not overlap. The
/// operation identifier is also the view-lifetime token: when Support leaves
/// the hierarchy, late report generation, save-panel callbacks, and completed
/// filesystem writes can no longer mutate its UI.
enum SupportDiagnosticsAction: Equatable, Sendable {
    case copy
    case save
}
struct SupportDiagnosticsOperationState: Equatable {
    private(set) var activeOperationID: UUID?
    private(set) var activeAction: SupportDiagnosticsAction?

    var isBusy: Bool { activeOperationID != nil }

    @discardableResult
    mutating func begin(
        _ action: SupportDiagnosticsAction,
        id: UUID = UUID()
    ) -> UUID? {
        guard activeOperationID == nil else { return nil }
        activeOperationID = id
        activeAction = action
        return id
    }

    func owns(_ id: UUID) -> Bool {
        activeOperationID == id
    }

    @discardableResult
    mutating func complete(_ id: UUID) -> Bool {
        guard owns(id) else { return false }
        activeOperationID = nil
        activeAction = nil
        return true
    }

    mutating func invalidate() {
        activeOperationID = nil
        activeAction = nil
    }
}

/// Latest-feedback-wins state for the short Copy/Saved confirmations. Tokens
/// prevent an older delay from clearing a newer, text-identical message.
struct SupportDiagnosticsFeedbackState: Equatable {
    private(set) var copied = false
    private(set) var message: String?
    private(set) var activeFeedbackID: UUID?

    @discardableResult
    mutating func showCopied(id: UUID = UUID()) -> UUID {
        copied = true
        message = nil
        activeFeedbackID = id
        return id
    }

    @discardableResult
    mutating func showMessage(_ message: String, id: UUID = UUID()) -> UUID {
        copied = false
        self.message = message
        activeFeedbackID = id
        return id
    }

    @discardableResult
    mutating func clear(_ id: UUID) -> Bool {
        guard activeFeedbackID == id else { return false }
        copied = false
        message = nil
        activeFeedbackID = nil
        return true
    }

    mutating func invalidate() {
        copied = false
        message = nil
        activeFeedbackID = nil
    }
}
