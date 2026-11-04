import Foundation
import CryptoKit
import DraftlyCore
import AgentContracts

// The app resolves installed themes. Connections never supply file paths.
@MainActor final class AgentThemeReading {
    static let operationNames: Set<String> = ["themes.list", "themes.get", "themes.export", "themes.selection", "themes.exportBuiltIn"]
    static let effectOperations: Set<String> = ["themes.get", "themes.export"]
    private let library: LibraryStore
    private let defaults: UserDefaults
    private let pages: AgentReadPages
    private let key = SymmetricKey(size: .bits256)

    init(library: LibraryStore, defaults: UserDefaults, pages: AgentReadPages) {
        self.library = library; self.defaults = defaults; self.pages = pages
    }

    private func version(_ value: AgentJSONValue) throws -> String {
        let bytes = try AgentRequestBinding.encoded(value, maximum: AgentRequest.maximumBytes * 2)
        return Data(HMAC<SHA256>.authenticationCode(for: bytes, using: key)).base64EncodedString()
    }

    func version(_ theme: EditorThemeDefinition) throws -> String {
        try version(theme, filePermission: defaults.data(forKey: ThemeFileAccess.bookmarkKey(for: theme.id)))
    }

    func version(_ theme: EditorThemeDefinition, filePermission: Data?) throws -> String {
        let definition = try encoded(theme)
        guard theme.type == "file" else { return try version(definition) }
        let permission = filePermission.map { AgentJSONValue.string(Data(SHA256.hash(data: $0)).base64EncodedString()) } ?? .null
        return try version(.object(["definition": definition, "filePermission": permission]))
    }

    private func encoded(_ theme: EditorThemeDefinition) throws -> AgentJSONValue {
        try JSONDecoder().decode(AgentJSONValue.self, from: JSONEncoder().encode(theme))
    }

    func definition(_ id: UUID, grant: AgentGrant, authorize: () throws -> Void) throws -> EditorThemeDefinition {
        guard grant.scope.permits(.init(kind: .theme, id: id)),
              let theme = library.themes.first(where: { $0.id == id }) else { throw AgentErrorCode.notFound }
        if theme.type == "file" {
            guard grant.capabilities.contains(.filesRead) else { throw AgentErrorCode.permissionDenied }
            try authorize()
            do {
                let result = try ThemeFileAccess.read(theme, defaults: defaults, maximumBytes: AgentRequest.maximumBytes)
                try authorize()
                return result
            } catch let error as AgentErrorCode { throw error }
            catch { throw AgentErrorCode.unavailable }
        }
        do { try theme.validate() } catch { throw AgentErrorCode.storageError }
        return theme
    }

    func selection(appearance: String, grant: AgentGrant) throws -> [String: AgentJSONValue] {
        guard ["dark", "light"].contains(appearance) else { throw AgentErrorCode.invalidInput }
        let raw = EditorThemePreferences(defaults: defaults).reference(dark: appearance == "dark", themes: library.themes)
        let stored = try JSONDecoder().decode(AgentJSONValue.self, from: JSONSerialization.data(withJSONObject: raw))
        let visible = raw.filter { key, _ in ["type", "name"].contains(key) || (key == "uuid" && raw["type"] as? String != "builtIn") }
        var fields = try JSONDecoder().decode(AgentJSONValue.self, from: JSONSerialization.data(withJSONObject: visible))
        let token = try version(.object(["appearance": .string(appearance), "reference": stored]))
        if let id = (raw["uuid"] as? String).flatMap(UUID.init(uuidString:)), !grant.scope.permits(.init(kind: .theme, id: id)) {
            fields = .null
        }
        return ["appearance": .string(appearance), "reference": fields, "versionToken": .string(token)]
    }

    func read(_ request: AgentRequest, parameters: [String: AgentJSONValue], grant: AgentGrant,
              sessionID: UUID, authorize: () throws -> Void) throws -> [String: AgentJSONValue] {
        try authorize()
        let result: [String: AgentJSONValue]
        switch request.operation {
        case "themes.list":
            let themes = library.themes.filter { grant.scope.permits(.init(kind: .theme, id: $0.id)) }
            let byID = Dictionary(themes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            var page = try pages.page(owner: .init(connectionID: grant.connectionID, grantID: grant.grantID), request: request,
                parameters: parameters, expiresAt: grant.expiresAt, ids: { themes.map(\.id) }, value: { id in
                    guard let theme = byID[id] else { return nil }
                    return .object(["id": .string(id.uuidString), "name": .string(theme.name), "type": .string(theme.type),
                        "versionToken": .string(try self.version(theme))])
                })
            page["builtInNames"] = .array(ThemeCatalog.builtInNames.map(AgentJSONValue.string))
            result = page
        case "themes.selection":
            guard case .string(let appearance) = parameters["appearance"] else { throw AgentErrorCode.invalidInput }
            result = try selection(appearance: appearance, grant: grant)
        case "themes.exportBuiltIn":
            guard case .string(let name) = parameters["name"] else { throw AgentErrorCode.invalidInput }
            let text = try ThemeInstallation.builtIn(name).url.absoluteString
            result = ["name": .string(name), "format": .string("installationURL"),
                "content": .object(try AgentDraftReading.chunk(text, parameters: parameters)),
                "versionToken": .string(try version(.string(text)))]
        case "themes.get", "themes.export":
            guard let id = request.targets.first?.id else { throw AgentErrorCode.invalidInput }
            let theme = try definition(id, grant: grant, authorize: authorize)
            let definition = try encoded(theme), token = try version(theme)
            if request.operation == "themes.get" {
                result = ["definition": definition, "versionToken": .string(token)]
            } else {
                var portable = try DraftsThemeImport.applyingEditorChanges(theme); portable.type = "custom"
                let text: String
                switch parameters["format"] {
                case .string("installationURL"): text = try ThemeInstallation.custom(portable).url.absoluteString
                case .string("drafts"): text = String(decoding: try DraftsThemeImport.exportData(portable), as: UTF8.self)
                default:
                    let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
                    text = String(decoding: try encoder.encode(portable), as: UTF8.self)
                }
                result = ["resourceID": .string(id.uuidString), "format": parameters["format"] ?? .string("native"),
                    "content": .object(try AgentDraftReading.chunk(text, parameters: parameters)), "versionToken": .string(token)]
            }
        default: throw AgentErrorCode.unavailable
        }
        try authorize()
        return result
    }
}
