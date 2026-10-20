import Foundation

@MainActor
public protocol ActionHost: AnyObject {
    func perform(_ operation: String, values: [String: Any]) throws -> Any?
    func finishAction()
}

public extension ActionHost { func finishAction() {} }

public enum ActionExecutionResult: Equatable, Sendable {
    case success
    case cancelled
    case failure(String)
    public var succeeded: Bool { self == .success }
    public func callbackURL(parameters: [String: String], successParameters: [String: String] = [:]) -> URL? {
        let key: String
        var additions: [String: String] = [:]
        switch self {
        case .success: key = "x-success"; additions = successParameters
        case .cancelled: key = "x-cancel"
        case .failure(let message): key = "x-error"; additions = ["errorMessage": message]
        }
        guard let raw = parameters[key], var components = URLComponents(string: raw), components.scheme != nil else { return nil }
        if !additions.isEmpty {
            components.queryItems = (components.queryItems ?? []).filter { additions[$0.name] == nil }
                + additions.keys.sorted().map { URLQueryItem(name: $0, value: additions[$0]) }
        }
        return components.url
    }

}
