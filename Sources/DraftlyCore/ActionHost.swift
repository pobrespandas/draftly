import Foundation

@MainActor
public protocol ActionHost: AnyObject {
    func perform(_ operation: String, values: [String: Any]) throws -> Any?
    func supportsAsync(_ operation: String) -> Bool
    // Supported async operations must suspend and finish their cleanup on cancellation.
    func performAsync(_ operation: String, payload: String) async throws -> String
    func finishAction()
}

public extension ActionHost {
    func supportsAsync(_ operation: String) -> Bool { false }

    func performAsync(_ operation: String, payload: String) async throws -> String {
        guard let values = try JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any] else {
            throw DraftlyError.message("The native operation payload must be an object.")
        }
        let result = try perform(operation, values: values)
        return String(decoding: try JSONSerialization.data(withJSONObject: ["value": result ?? NSNull()]), as: UTF8.self)
    }

    func finishAction() {}
}
