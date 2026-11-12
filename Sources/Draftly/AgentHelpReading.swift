import Foundation
import AgentContracts
import DraftlyCore

/// Read the same public guide as the Help window. This never reads library data.
enum AgentHelpReading {
    static func read(_ operation: String, parameters: [String: AgentJSONValue]) throws -> [String: AgentJSONValue] {
        let articles: [HelpArticle]
        do { articles = try HelpGuide.articles() + [HelpGuide.agentSkill()] }
        catch { throw AgentErrorCode.unavailable }
        func metadata(_ article: HelpArticle) -> [String: AgentJSONValue] {
            ["id": .string(article.id), "title": .string(article.title), "category": .string(article.category)]
        }
        switch operation {
        case "help.search":
            guard case .string(let query) = parameters["query"], case .integer(let limit) = parameters["limit"] else {
                throw AgentErrorCode.invalidInput
            }
            let matches = articles.filter { $0.matches(query) }
            return ["items": .array(matches.prefix(Int(limit)).map { article in
                var value = metadata(article)
                value["summary"] = .string(String(article.markdown.drop(while: { $0 != "\n" }).trimmingCharacters(in: .whitespacesAndNewlines).prefix(600)))
                return .object(value)
            }), "total": .integer(Int64(matches.count))]
        case "help.get":
            guard case .string(let id) = parameters["id"] else { throw AgentErrorCode.invalidInput }
            guard let article = articles.first(where: { $0.id == id }) else { throw AgentErrorCode.notFound }
            var value = metadata(article); value["markdown"] = .string(article.markdown)
            return value
        default: throw AgentErrorCode.unavailable
        }
    }
}
