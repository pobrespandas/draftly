import Foundation
import FoundationModels
import DraftlyCore

@MainActor final class NativeModelAPI {
    var onTool: (@MainActor @Sendable (String, String) throws -> String)?
    private var sessions: [String: LanguageModelSession] = [:]
    func clear() { sessions.removeAll() }
    func perform(_ operation: String, _ values: [String: Any]) throws -> Any {
        var modes: [String] = []
        if FoundationModels.SystemLanguageModel.default.isAvailable { modes.append("onDevice") }
        if #available(macOS 27, *), PrivateCloudComputeLanguageModel().isAvailable { modes.append("pcc") }
        if operation == "modelModes" { return modes }
        let mode = values["mode"] as? String ?? "onDevice"
        guard modes.contains(mode) else { throw DraftlyError.message("The selected Apple Intelligence model is unavailable on this Mac.") }
        let id = values["sessionID"] as? String ?? UUID().uuidString
        let session: LanguageModelSession
        if let existing = sessions[id] { session = existing }
        else {
            let instructions = (values["instructions"] as? [String] ?? []).joined(separator: "\n")
            var names = values["tools"] as? [String] ?? []
            for group in values["toolSets"] as? [String] ?? [] {
                switch group {
                case "drafts": names += ["draft.query", "draft.find", "draft.create", "draft.append", "draft.prepend"]
                case "editor": names += ["editor.open"]
                case "actions": names += ["action.run"]
                case "workspaces": names += ["workspace.find"]
                default: throw DraftlyError.message("The model tool set \(group) is unavailable.")
                }
            }
            let tools: [any Tool] = try Array(Set(names)).sorted().map { name in
                guard let onTool else { throw DraftlyError.message("Model tools require an active Draftly window.") }
                return try ScriptModelTool(operation: name, callback: onTool)
            }
            if mode == "pcc" {
                if #available(macOS 27, *) { session = LanguageModelSession(model: PrivateCloudComputeLanguageModel(), tools: tools, instructions: instructions) }
                else { throw DraftlyError.message("Private Cloud Compute requires macOS 27.") }
            } else { session = LanguageModelSession(model: FoundationModels.SystemLanguageModel.default, tools: tools, instructions: instructions) }
            sessions[id] = session
        }
        let schema = try (values["schema"] as? [String: Any]).map(Self.schema)
        let prompt = values["prompt"] as? String ?? "", temperature = min(1, max(0, values["temperature"] as? Double ?? 0.5))
        let result = ModelResult()
        let task = Task { @MainActor in
            do {
                let response: String
                if let schema { response = try await session.respond(to: prompt, schema: schema, options: GenerationOptions(temperature: temperature)).content.jsonString }
                else { response = try await session.respond(to: prompt, options: GenerationOptions(temperature: temperature)).content }
                result.response = response
            } catch { result.error = error }
            result.finished = true
        }
        let deadline = Date().addingTimeInterval(120)
        while !result.finished && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
        guard result.finished else { task.cancel(); throw DraftlyError.message("The model response timed out.") }
        if let error = result.error { throw error }
        let response: Any = schema != nil ? (try JSONSerialization.jsonObject(with: Data((result.response ?? "").utf8))) : result.response ?? ""
        let transcript = String(decoding: try JSONEncoder().encode(session.transcript), as: UTF8.self)
        return ["response": response, "transcript": transcript]
    }
    private static func schema(_ values: [String: Any]) throws -> GenerationSchema {
        let properties = try (values["fields"] as? [[String: Any]] ?? []).map { field -> DynamicGenerationSchema.Property in
            let type = field["type"] as? String ?? "string", isArray = type.hasSuffix("Array")
            let primitive: DynamicGenerationSchema
            switch type.replacingOccurrences(of: "Array", with: "") {
            case "boolean": primitive = DynamicGenerationSchema(type: Bool.self)
            case "int": primitive = DynamicGenerationSchema(type: Int.self)
            case "number": primitive = DynamicGenerationSchema(type: Double.self)
            case "string":
                if let choices = field["options"] as? [String], !choices.isEmpty { primitive = DynamicGenerationSchema(name: field["name"] as? String ?? "Value", anyOf: choices) }
                else { primitive = DynamicGenerationSchema(type: String.self) }
            default: throw DraftlyError.message("The model schema field type is invalid.")
            }
            return DynamicGenerationSchema.Property(name: field["name"] as? String ?? "value", description: field["description"] as? String, schema: isArray ? DynamicGenerationSchema(arrayOf: primitive) : primitive)
        }
        return try GenerationSchema(root: DynamicGenerationSchema(name: "Response", properties: properties), dependencies: [])
    }
}

@MainActor private final class ModelResult {
    var response: String?; var error: Error?; var finished = false
}

private struct ScriptModelTool: Tool {
    typealias Arguments = GeneratedContent
    let operation: String
    var name: String { operation.replacingOccurrences(of: ".", with: "_") }
    var description: String { "Run \(operation) in the user's Draftly library. Supply only the needed fields." }
    let parameters: GenerationSchema
    let callback: @MainActor @Sendable (String, String) throws -> String
    init(operation: String, callback: @escaping @MainActor @Sendable (String, String) throws -> String) throws {
        self.operation = operation; self.callback = callback
        let fields = ["uuid", "text", "query", "name", "folder"].map { DynamicGenerationSchema.Property(name: $0, schema: DynamicGenerationSchema(type: String.self), isOptional: true) }
            + [DynamicGenerationSchema.Property(name: "tags", schema: DynamicGenerationSchema(arrayOf: DynamicGenerationSchema(type: String.self)), isOptional: true)]
        parameters = try GenerationSchema(root: DynamicGenerationSchema(name: "Arguments", properties: fields), dependencies: [])
    }
    func call(arguments: GeneratedContent) async throws -> String { try await callback(operation, arguments.jsonString) }
}
