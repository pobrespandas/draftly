import Foundation

@MainActor extension ActionRunner {
    private func configurationValues(_ action: DraftAction, steps: [ActionStep]) -> [String: Any] {
        var configured: [String: Any] = action.configuredValues
        for step in steps where step.type == "configurationKey" {
            let key = step.values["key"] ?? ""
            let dataType = step.values["dataType"] ?? "string"
            let defaultKey = dataType == "boolean" ? "defaultBoolValue" : dataType == "number" ? "defaultNumberValue" : dataType == "text" ? "defaultTextValue" : "defaultStringValue"
            let value = action.configuredValues[key] ?? step.values["defaultValue"] ?? step.values[defaultKey] ?? ""
            configured[key] = value
            if dataType == "boolean" { configured[key] = value == "true" || value == "1" }
            if dataType == "number" { configured[key] = Double(value) ?? 0 }
        }
        return configured
    }

    func additionalConfigurationSource(_ action: DraftAction, steps: [ActionStep]) throws -> String {
        let values = try json(configurationValues(action, steps: steps))
        return "for(const [key,value] of Object.entries(\(values))){if(!Object.prototype.hasOwnProperty.call(context.configuredValues,key))context.configuredValues[key]=value;}"
    }

    func bootstrapSource(_ action: DraftAction, note: Note, steps: [ActionStep]) throws -> String {
        let configured = configurationValues(action, steps: steps)
        return "var draft=new Draft(\(try json(noteValue(note))));var action=new Action(\(try json(actionValue(action))));context.configuredValues=\(try json(configured));action.configuredValues=context.configuredValues;"
    }

    func applySuccessEffects(_ action: DraftAction, noteID: UUID) throws {
        if var original = library.notes.first(where: { $0.id == noteID }) {
            switch action.afterSuccess {
            case "archive", "1": original.isArchived = true
            case "trash", "2": original.trashedAt = Date()
            default: break
            }
            original.tags = TagRules.normalize(original.tags + action.presentation.addTags)
                .filter { !TagRules.normalize(action.presentation.removeTags).contains($0) }
            if let flag = action.presentation.flagAfterSuccess { original.flag = min(7, max(0, flag)) }
            try library.saveNote(original)
        }
    }
}
