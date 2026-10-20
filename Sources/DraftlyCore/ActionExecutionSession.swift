import Foundation
import Combine

public enum ActionTerminationReason: String, Sendable {
    case success, cancelled, error, timeout, busy
}

public struct ActionExecutionReport: Equatable, Sendable {
    public let executionID: UUID
    public let actionID: UUID
    public let startedAt: Date
    public let finishedAt: Date
    public let result: ActionExecutionResult
    public let reason: ActionTerminationReason
    public let successParameters: [String: String]

    public static func notStarted(actionID: UUID, reason: ActionTerminationReason, message: String) -> Self {
        precondition(reason != .success, "An unstarted action cannot succeed.")
        let now = Date()
        return Self(executionID: UUID(), actionID: actionID, startedAt: now, finishedAt: now,
                    result: reason == .cancelled ? .cancelled : .failure(message),
                    reason: reason, successParameters: [:])
    }
}

public struct ActionExecutionStep: Equatable, Sendable {
    public let actionID: UUID
    public let stepID: UUID
    public let index: Int
    public let type: String
}

@MainActor
public final class ActionExecutionSession: ObservableObject {
    public let id = UUID()
    public let actionID: UUID
    public let startedAt = Date()
    @Published public private(set) var currentStep: ActionExecutionStep?
    @Published public private(set) var cancellationRequested = false
    @Published public private(set) var report: ActionExecutionReport?
    private var stepCount = 0

    init(actionID: UUID) { self.actionID = actionID }

    public func cancel() {
        guard report == nil else { return }
        cancellationRequested = true
    }

    func enter(actionID: UUID, step: ActionStep) {
        guard report == nil, !cancellationRequested else { return }
        currentStep = ActionExecutionStep(actionID: actionID, stepID: step.id, index: stepCount, type: step.type)
        stepCount += 1
    }

    @discardableResult
    func finish(_ result: ActionExecutionResult, reason: ActionTerminationReason, successParameters: [String: String]) -> ActionExecutionReport {
        if let report { return report }
        let final = ActionExecutionReport(executionID: id, actionID: actionID, startedAt: startedAt, finishedAt: Date(), result: result, reason: reason, successParameters: result.succeeded ? successParameters : [:])
        report = final
        return final
    }
}

public enum ActionExecutionInterruption: LocalizedError {
    case cancelled
    case timeout
    public var errorDescription: String? {
        switch self {
        case .cancelled: return "The action was cancelled."
        case .timeout: return "The action operation timed out before it completed."
        }
    }
}
