import Foundation

package enum AgentAppearanceSchemas {
    package static var operationNames: Set<String> { Set(schemas.keys) }
    package static func schema(for operation: String) -> AgentOperationSchema? { schemas[operation] }

    package static func validatedParameters(for request: AgentRequest) throws -> [String: AgentJSONValue] {
        guard let schema = schemas[request.operation] else { throw AgentErrorCode.unavailable }
        let values = try schema.validatedParameters(request.parameters)
        if request.operation == "themes.update" {
            try AgentResourceShapes.validateDefinitionID(values["theme"], target: request.targets.first)
        }
        if let source = values["source"] {
            let kind = try AgentImportSource.validate(source, installationEndpoint: request.operation.hasPrefix("themes.") ? "theme" : "syntax")
            if values["mode"] == .string("file"), kind != "bookmark" { throw AgentSchemaError.invalidValue }
        }
        if request.operation == "themes.install" || request.operation == "themes.replace" {
            guard (values["selectAppearance"] != nil) == (values["expectedSelectionVersion"] != nil) else {
                throw AgentSchemaError.invalidValue
            }
        }
        return values
    }

    package static func validateResult(_ values: [String: AgentJSONValue], for operation: String) throws {
        guard let schema = schemas[operation] else { throw AgentErrorCode.unavailable }
        try schema.result.validate(values)
        if values["content"] != nil { _ = try AgentTextShapes.validateChunk(values["content"]) }
        if operation == "themes.list" || operation == "syntaxes.list" {
            guard case .array(let names) = values["builtInNames"], case .array(let items) = values["items"] else {
                throw AgentSchemaError.invalidValue
            }
            let expected = operation == "themes.list" ? builtInThemes : builtInSyntaxes
            let actual = names.compactMap { value -> String? in if case .string(let name) = value { return name }; return nil }
            guard actual.count == expected.count, Set(actual) == Set(expected) else { throw AgentSchemaError.invalidValue }
            let ids = items.compactMap { value -> UUID? in
                guard case .object(let fields) = value, case .string(let id) = fields["id"] else { return nil }
                return UUID(uuidString: id)
            }
            guard Set(ids).count == ids.count else { throw AgentSchemaError.invalidValue }
        }
        if operation == "themes.selection", case .object(let reference) = values["reference"] {
            if reference["type"] == .string("builtIn") {
                guard reference["uuid"] == nil, let name = reference["name"] else { throw AgentSchemaError.invalidValue }
                try themeNames.validate(name)
            } else if reference["uuid"] == nil { throw AgentSchemaError.invalidValue }
        }
    }

    package static func validateResult(_ values: [String: AgentJSONValue], for request: AgentRequest) throws {
        try validateResult(values, for: request.operation)
        if ["themes.update", "themes.reload", "themes.replace", "syntaxes.replace", "syntaxes.reload"].contains(request.operation) {
            try AgentResourceShapes.validateDefinitionID(values["resource"], target: request.targets.first)
        } else if ["themes.get", "syntaxes.get"].contains(request.operation) {
            try AgentResourceShapes.validateDefinitionID(values["definition"], target: request.targets.first)
        } else if request.operation == "themes.duplicate" {
            guard case .object(let resource) = values["resource"], case .string(let id) = resource["id"],
                  UUID(uuidString: id) != request.targets.first?.id else { throw AgentSchemaError.invalidValue }
        } else if request.operation == "themes.select" {
            guard case .string(let id) = values["themeID"], UUID(uuidString: id) == request.targets.first?.id else {
                throw AgentSchemaError.invalidValue
            }
        } else if ["themes.delete", "syntaxes.delete"].contains(request.operation) {
            try AgentResourceShapes.validateOrder(values["deletedIDs"], targets: request.targets)
        }
        if ["themes.select", "themes.selectBuiltIn", "themes.selection"].contains(request.operation) {
            guard values["appearance"] == request.parameters["appearance"] else { throw AgentSchemaError.invalidValue }
        }
        if ["themes.selectBuiltIn", "themes.exportBuiltIn", "syntaxes.getBuiltIn", "syntaxes.exportBuiltIn"].contains(request.operation) {
            guard values["name"] == request.parameters["name"] else { throw AgentSchemaError.invalidValue }
        }
        if ["themes.export", "syntaxes.export", "syntaxes.exportBuiltIn"].contains(request.operation) {
            guard let schema = schemas[request.operation] else { throw AgentErrorCode.unavailable }
            let parameters = try schema.validatedParameters(request.parameters)
            guard values["format"] == parameters["format"] else { throw AgentSchemaError.invalidValue }
        }
        if request.operation == "themes.export" || request.operation == "syntaxes.export" {
            guard case .string(let id) = values["resourceID"], UUID(uuidString: id) == request.targets.first?.id else {
                throw AgentSchemaError.invalidValue
            }
        }
        if request.operation == "themes.install" || request.operation == "syntaxes.install" {
            let hasResource = values["resource"] != .null
            let hasBuiltIn = values["builtInName"] != .null
            guard hasResource != hasBuiltIn else { throw AgentSchemaError.invalidValue }
            if hasBuiltIn {
                guard case .object(let source) = request.parameters["source"], source["kind"] == .string("installationURL"),
                      case .string(let text) = source["url"], let url = URLComponents(string: text),
                      let name = url.queryItems?.first(where: { $0.name == "name" })?.value,
                      url.queryItems?.contains(where: { $0.name == "data" }) == false,
                      values["builtInName"] == .string(name) else { throw AgentSchemaError.invalidValue }
            }
        }
        if request.operation == "themes.install" || request.operation == "themes.replace" {
            if let requested = request.parameters["selectAppearance"] {
                guard case .object(let selection) = values["selection"], selection["appearance"] == requested else {
                    throw AgentSchemaError.invalidValue
                }
            } else if values["selection"] != .null { throw AgentSchemaError.invalidValue }
        }
    }

    private static func r(_ shape: AgentValueShape) -> AgentFieldShape { .init(shape: shape, required: true) }
    private static func o(_ shape: AgentValueShape, default value: AgentJSONValue? = nil) -> AgentFieldShape {
        .init(shape: shape, defaultValue: value)
    }
    private static let text = AgentValueShape.string()
    private static let token = AgentResourceShapes.token
    private static let builtInThemes = ["Default", "Dark", "Light"]
    private static let builtInSyntaxes = ["Plain Text", "Markdown", "TaskPaper", "JavaScript", "Simple List", "MultiMarkdown", "GitHub Markdown"]
    private static let themeNames = AgentValueShape.string(choices: builtInThemes)
    private static let syntaxNames = AgentValueShape.string(choices: builtInSyntaxes)
    private static let appearance = AgentValueShape.string(choices: ["light", "dark"])
    private static let theme = AgentObjectShape(fields: [
        "id": r(.uuid), "name": r(text), "foreground": r(text), "background": r(text), "heading": r(text),
        "isDark": r(.boolean), "type": o(.string(choices: ["custom", "file"]))
    ], allowsAdditionalFields: true)
    private static let newTheme = AgentObjectShape(fields: theme.fields.mapValues { .init(shape: $0.shape) }
        .merging(["type": o(.string(choices: ["custom"]))], uniquingKeysWith: { _, new in new }), allowsAdditionalFields: true)
    private static let syntax = AgentObjectShape(fields: [
        "id": r(.uuid), "name": r(text), "type": r(.string(choices: ["custom", "file"])), "source": r(text)
    ])
    private static let page = AgentObjectShape(fields: [
        "limit": o(.integer(minimum: 1, maximum: 200), default: .integer(50)), "cursor": o(token)
    ])
    private static func exportParameters(formats: [String], defaultFormat: String) -> AgentObjectShape {
        .init(fields: AgentTextShapes.chunkParameters.fields.merging([
            "format": o(.string(choices: formats), default: .string(defaultFormat))
        ], uniquingKeysWith: { _, new in new }))
    }
    private static let themeReference = AgentObjectShape(fields: [
        "type": r(.string(choices: ["builtIn", "custom", "file"])), "name": r(text), "uuid": o(.uuid)
    ])
    private static let selectionReceipt = AgentObjectShape(fields: ["appearance": r(appearance), "versionToken": r(token)])
    private static let schemas: [String: AgentOperationSchema] = {
        let none = AgentObjectShape(fields: [:])
        let summary = AgentObjectShape(fields: [
            "id": r(.uuid), "name": r(text), "type": r(.string(choices: ["custom", "file"])), "versionToken": r(token)
        ])
        func listResult(_ builtIns: AgentValueShape) -> AgentObjectShape {
            .init(fields: ["items": r(.array(.object(summary), maximum: 200)), "nextCursor": r(.nullable(token)),
                "builtInNames": r(.array(builtIns, maximum: 200))])
        }
        func exported(_ formats: [String], builtInNames: AgentValueShape? = nil) -> AgentObjectShape {
            var fields: [String: AgentFieldShape] = ["format": r(.string(choices: formats)),
                "content": r(.object(AgentTextShapes.chunk)), "versionToken": r(token)]
            if let builtInNames { fields["name"] = r(builtInNames) }
            else { fields["resourceID"] = r(.uuid) }
            return .init(fields: fields)
        }
        let themeFormats = ["native", "drafts", "installationURL"]
        let syntaxFormats = ["source", "installationURL"]
        let install = AgentObjectShape(fields: [
            "source": r(AgentImportSource.shape),
            "mode": o(.string(choices: ["custom", "file"]), default: .string("custom"))
        ])
        let builtInTheme = AgentObjectShape(fields: ["name": r(themeNames)])
        let builtInSyntax = AgentObjectShape(fields: ["name": r(syntaxNames)])
        return [
            "themes.list": .init(parameters: page, result: listResult(themeNames)),
            "themes.get": .init(parameters: none, result: .init(fields: ["definition": r(.object(theme)), "versionToken": r(token)])),
            "themes.export": .init(parameters: exportParameters(formats: themeFormats, defaultFormat: "native"), result: exported(themeFormats)),
            "themes.create": .init(parameters: .init(fields: ["theme": r(.object(newTheme))]), result: AgentResourceShapes.updated),
            "themes.update": .init(parameters: .init(fields: ["theme": r(.object(theme))]), result: AgentResourceShapes.updated),
            "themes.duplicate": .init(parameters: .init(fields: ["name": o(text)]), result: AgentResourceShapes.updated),
            "themes.selection": .init(parameters: .init(fields: ["appearance": r(appearance)]), result: .init(fields: [
                "appearance": r(appearance), "reference": r(.nullable(.object(themeReference))), "versionToken": r(token)
            ])),
            "themes.select": .init(parameters: .init(fields: ["appearance": r(appearance), "expectedThemeVersion": r(token)]), result: .init(fields: [
                "themeID": r(.uuid), "appearance": r(appearance), "versionToken": r(token)
            ])),
            "themes.selectBuiltIn": .init(parameters: .init(fields: ["name": r(themeNames), "appearance": r(appearance)]), result: .init(fields: [
                "name": r(themeNames), "appearance": r(appearance), "versionToken": r(token)
            ])),
            "themes.exportBuiltIn": .init(parameters: .init(fields: AgentTextShapes.chunkParameters.fields.merging(builtInTheme.fields, uniquingKeysWith: { _, new in new })), result: exported(["installationURL"], builtInNames: themeNames)),
            "themes.reload": .init(parameters: none, result: AgentResourceShapes.updated),
            "themes.install": .init(parameters: .init(fields: install.fields.merging([
                "selectAppearance": o(appearance), "expectedSelectionVersion": o(token)
            ], uniquingKeysWith: { _, new in new })), result: .init(fields: [
                "resource": r(.nullable(.object(AgentResourceShapes.receipt))), "builtInName": r(.nullable(themeNames)),
                "selection": r(.nullable(.object(selectionReceipt)))
            ])),
            "themes.replace": .init(parameters: .init(fields: install.fields.merging([
                "selectAppearance": o(appearance), "expectedSelectionVersion": o(token)
            ], uniquingKeysWith: { _, new in new })), result: .init(fields: [
                "resource": r(.object(AgentResourceShapes.receipt)), "selection": r(.nullable(.object(selectionReceipt)))
            ])),
            "themes.delete": .init(parameters: none, result: AgentResourceShapes.deleted),
            "syntaxes.list": .init(parameters: page, result: listResult(syntaxNames)),
            "syntaxes.get": .init(parameters: none, result: .init(fields: ["definition": r(.object(syntax)), "versionToken": r(token)])),
            "syntaxes.getBuiltIn": .init(parameters: builtInSyntax, result: .init(fields: ["name": r(syntaxNames), "source": r(text), "versionToken": r(token)])),
            "syntaxes.export": .init(parameters: exportParameters(formats: syntaxFormats, defaultFormat: "source"), result: exported(syntaxFormats)),
            "syntaxes.exportBuiltIn": .init(parameters: .init(fields: exportParameters(formats: syntaxFormats, defaultFormat: "source").fields.merging(builtInSyntax.fields, uniquingKeysWith: { _, new in new })), result: exported(syntaxFormats, builtInNames: syntaxNames)),
            "syntaxes.install": .init(parameters: install, result: .init(fields: [
                "resource": r(.nullable(.object(AgentResourceShapes.receipt))), "builtInName": r(.nullable(syntaxNames))
            ])),
            "syntaxes.replace": .init(parameters: install, result: AgentResourceShapes.updated),
            "syntaxes.reload": .init(parameters: none, result: AgentResourceShapes.updated),
            "syntaxes.delete": .init(parameters: none, result: AgentResourceShapes.deleted)
        ]
    }()
}
