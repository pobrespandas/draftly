import Foundation
import DraftlyCore

/// Retain the final execution identity and result at an automation boundary.
enum AutomationActionError: LocalizedError, Equatable, Sendable {
    struct Details: Equatable, Sendable {
        let executionID: UUID
        let result: ActionExecutionResult
        let message: String
    }

    case cancelled(Details)
    case timeout(Details)
    case busy(Details)
    case failed(Details)

    var details: Details {
        switch self {
        case .cancelled(let value), .timeout(let value), .busy(let value), .failed(let value): return value
        }
    }
    var executionID: UUID { details.executionID }
    var result: ActionExecutionResult { details.result }
    var reason: ActionTerminationReason {
        switch self {
        case .cancelled: return .cancelled
        case .timeout: return .timeout
        case .busy: return .busy
        case .failed: return .error
        }
    }
    var errorDescription: String? { details.message }

    static func from(_ report: ActionExecutionReport, message: String = "") -> AutomationActionError? {
        guard report.reason != .success || !report.result.succeeded else { return nil }
        let supplied: String
        if case .failure(let failure) = report.result, !failure.isEmpty { supplied = failure }
        else { supplied = message }
        let fallback: String
        switch report.reason {
        case .cancelled: fallback = "The action was cancelled."
        case .timeout: fallback = "The action operation timed out before it completed."
        case .busy: fallback = "The library is already running an action."
        case .success, .error: fallback = "The action did not complete."
        }
        let details = Details(executionID: report.executionID, result: report.result, message: supplied.isEmpty ? fallback : supplied)
        switch report.reason {
        case .cancelled: return .cancelled(details)
        case .timeout: return .timeout(details)
        case .busy: return .busy(details)
        case .success, .error: return .failed(details)
        }
    }
}
