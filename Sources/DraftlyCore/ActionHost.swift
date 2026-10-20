import Foundation

@MainActor
public protocol ActionHost: AnyObject {
    func perform(_ operation: String, values: [String: Any]) throws -> Any?
    func finishAction()
}

public extension ActionHost { func finishAction() {} }
