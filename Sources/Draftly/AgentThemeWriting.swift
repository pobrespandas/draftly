import Foundation
import AgentContracts
import DraftlyCore

// A theme definition and its receipt commit together. Selection is separate.
@MainActor final class AgentThemeWriting {
    static let operationNames: Set<String> = ["themes.create", "themes.update", "themes.duplicate"]
    private let library: LibraryStore
    private let libraryID: UUID
    private let reader: AgentThemeReading
    private let keys: AgentRetryKeys
    private let now: () -> Date
    private var updating = false

    init(library: LibraryStore, libraryID: UUID, reader: AgentThemeReading,
         keys: AgentRetryKeys, now: @escaping () -> Date) {
        self.library = library; self.libraryID = libraryID; self.reader = reader; self.keys = keys; self.now = now
    }

    private func identity(_ request: AgentRequest, ticket: AgentRetryKeys.Ticket) -> LibraryMutationIdentity {
        .init(requestID: request.requestID, connectionHash: ticket.connectionHash, requestHash: ticket.requestHash)
    }

    private func receipt(_ request: AgentRequest, ticket: AgentRetryKeys.Ticket) throws -> LibraryMutationReceipt? {
        do {
            guard let previous = try library.mutationReceipt(for: identity(request, ticket: ticket), at: now()) else { return nil }
            guard previous.resources.count == 1, let resource = previous.resources.first else { throw AgentErrorCode.storageError }
            if request.operation == "themes.update" {
                guard resource.id == request.targets.first?.id else { throw AgentErrorCode.storageError }
            } else if request.operation == "themes.duplicate" {
                guard resource.id != request.targets.first?.id else { throw AgentErrorCode.storageError }
            } else if case .object(let input) = request.parameters["theme"], case .string(let rawID) = input["id"] {
                guard UUID(uuidString: rawID) == resource.id else { throw AgentErrorCode.storageError }
            }
            return previous
        } catch let error as LibraryMutationReceiptError {
            switch error {
            case .requestConflict: throw AgentErrorCode.invalidInput
            case .retryWindowExpired: throw AgentErrorCode.retryWindowExpired
            case .pendingChanges: throw AgentErrorCode.busy
            case .invalidReceipt: throw AgentErrorCode.storageError
            }
        }
    }

    private func plan(_ request: AgentRequest, grant: AgentGrant, newID: UUID = UUID(),
                      authorize: () throws -> Void) throws -> EditorThemeDefinition {
        let parameters: [String: AgentJSONValue]
        do { parameters = try AgentAppearanceSchemas.validatedParameters(for: request) }
        catch { throw AgentErrorCode.invalidInput }
        var value: EditorThemeDefinition
        if request.operation == "themes.create" {
            guard case .object(let input) = parameters["theme"],
                  case .object(var base) = try JSONDecoder().decode(AgentJSONValue.self,
                    from: JSONEncoder().encode(EditorThemeDefinition(id: newID))) else { throw AgentErrorCode.invalidInput }
            base.merge(input) { _, new in new }
            do { value = try JSONDecoder().decode(EditorThemeDefinition.self, from: JSONEncoder().encode(AgentJSONValue.object(base))) }
            catch { throw AgentErrorCode.invalidInput }
        } else {
            guard let id = request.targets.first?.id, let expected = request.expectedVersion else { throw AgentErrorCode.invalidInput }
            let original = try reader.definition(id, grant: grant, authorize: authorize)
            guard try reader.version(original) == expected else { throw AgentErrorCode.versionConflict }
            if request.operation == "themes.update" {
                // File themes use Reload or targeted replacement in the native app.
                guard original.type == "custom" else { throw AgentErrorCode.interactionRequired }
                guard let input = parameters["theme"] else { throw AgentErrorCode.invalidInput }
                do { value = try JSONDecoder().decode(EditorThemeDefinition.self, from: JSONEncoder().encode(input)) }
                catch { throw AgentErrorCode.invalidInput }
                guard value.id == id else { throw AgentErrorCode.invalidInput }
            } else {
                value = original; value.id = newID; value.type = "custom"
                if case .string(let name) = parameters["name"] { value.name = name }
                else { value.name += " Copy" }
            }
        }
        guard value.type == "custom" else { throw AgentErrorCode.invalidInput }
        do { value = try DraftsThemeImport.applyingEditorChanges(value); try value.validate() }
        catch { throw AgentErrorCode.invalidInput }
        if request.operation != "themes.update", library.themes.contains(where: { $0.id == value.id }) { throw AgentErrorCode.versionConflict }
        guard !library.themes.contains(where: { $0.id != value.id && $0.type == value.type && $0.name == value.name }) else {
            throw AgentErrorCode.versionConflict
        }
        return value
    }

    func prepare(_ request: AgentRequest, grant: AgentGrant, authorize: () throws -> Void) throws -> AgentRetryKeys.Ticket {
        guard !updating else { throw AgentErrorCode.busy }
        updating = true; defer { updating = false }
        guard Self.operationNames.contains(request.operation), request.libraryID == libraryID,
              request.retryKey == nil else { throw AgentErrorCode.invalidInput }
        try authorize()
        let ticket = try keys.issue(request, connectionID: grant.connectionID)
        if try receipt(request, ticket: ticket) == nil { _ = try plan(request, grant: grant, authorize: authorize) }
        try authorize(); _ = try keys.verify(ticket.value, request: request, connectionID: grant.connectionID)
        return ticket
    }

    func update(_ request: AgentRequest, grant: AgentGrant, authorize: () throws -> Void) throws -> LibraryMutationReceipt {
        guard !updating else { throw AgentErrorCode.busy }
        updating = true; defer { updating = false }
        guard Self.operationNames.contains(request.operation), request.libraryID == libraryID,
              let key = request.retryKey else { throw AgentErrorCode.invalidInput }
        try authorize()
        let ticket = try keys.verify(key, request: request, connectionID: grant.connectionID)
        if let previous = try receipt(request, ticket: ticket) { try authorize(); return previous }
        let value = try plan(request, grant: grant, authorize: authorize)
        do {
            return try library.commitTheme(value, mutation: identity(request, ticket: ticket), at: now(), validateCommit: {
                try Task.checkCancellation(); try authorize()
                _ = try self.keys.verify(key, request: request, connectionID: grant.connectionID)
                guard try self.plan(request, grant: grant, newID: value.id, authorize: authorize) == value else {
                    throw AgentErrorCode.versionConflict
                }
                try Task.checkCancellation(); try authorize()
                _ = try self.keys.verify(key, request: request, connectionID: grant.connectionID)
            }, makeResource: { .init(id: $0.id, versionToken: try self.reader.version($0)) })
        } catch is CancellationError { throw AgentErrorCode.cancelled }
        catch let error as AgentErrorCode { throw error }
        catch { throw AgentErrorCode.storageError }
    }
}

// Presentation changes use an atomic preference-domain write.
@MainActor enum AgentThemePresentation {
    static let operationNames: Set<String> = ["themes.select", "themes.selectBuiltIn", "themes.reload"]
    struct Plan: Equatable {
        let appearance: String?
        let reloadedVersion: String?
        let themeID: UUID?
        let name: String?
        let storage: [String: AgentPreferenceBatch.StoredValue]

        func result(_ selection: [String: AgentJSONValue]) throws -> [String: AgentJSONValue] {
            if let reloadedVersion, let themeID {
                return ["resource": .object(["id": .string(themeID.uuidString), "versionToken": .string(reloadedVersion)])]
            }
            guard let appearance else { throw AgentErrorCode.outcomeUnknown }
            guard case .object(let reference) = selection["reference"], let version = selection["versionToken"] else {
                throw AgentErrorCode.outcomeUnknown
            }
            var result: [String: AgentJSONValue] = ["appearance": .string(appearance), "versionToken": version]
            if let themeID {
                guard case .string(let raw) = reference["uuid"], UUID(uuidString: raw) == themeID else { throw AgentErrorCode.outcomeUnknown }
                result["themeID"] = .string(themeID.uuidString)
            } else if let name {
                guard reference["type"] == .string("builtIn"), reference["name"] == .string(name) else { throw AgentErrorCode.outcomeUnknown }
                result["name"] = .string(name)
            } else { throw AgentErrorCode.outcomeUnknown }
            return result
        }
    }

    static func prepare(_ request: AgentRequest, grant: AgentGrant, defaults: UserDefaults,
                        library: LibraryStore, reader: AgentThemeReading, authorize: () throws -> Void) throws -> Plan {
        guard operationNames.contains(request.operation), grant.capabilities.contains(.appearanceManage) else { throw AgentErrorCode.permissionDenied }
        let parameters = try AgentAppearanceSchemas.validatedParameters(for: request)
        if request.operation == "themes.reload" {
            guard grant.capabilities.contains(.filesRead) else { throw AgentErrorCode.permissionDenied }
            guard request.targets.count == 1, let target = request.targets.first, target.kind == .theme else {
                throw AgentErrorCode.invalidInput
            }
            try authorize()
            let theme = try reader.definition(target.id, grant: grant, authorize: authorize)
            guard theme.type == "file" else { throw AgentErrorCode.invalidInput }
            let version = try reader.version(theme)
            guard request.expectedVersion == version else { throw AgentErrorCode.versionConflict }
            try authorize()
            return Plan(appearance: nil, reloadedVersion: version, themeID: target.id, name: nil, storage: [
                ThemeCatalog.revisionKey: .scalar(.integer(Int64(defaults.integer(forKey: ThemeCatalog.revisionKey) &+ 1)))])
        }
        guard case .string(let appearance) = parameters["appearance"] else { throw AgentErrorCode.invalidInput }
        try authorize()
        guard try reader.selection(appearance: appearance, grant: grant)["versionToken"] == request.expectedVersion.map(AgentJSONValue.string) else {
            throw AgentErrorCode.versionConflict
        }
        let reference: [String: Any]
        let themeID: UUID?, name: String?
        if request.operation == "themes.select" {
            guard request.targets.count == 1, let target = request.targets.first, target.kind == .theme,
                  case .string(let expected) = parameters["expectedThemeVersion"] else { throw AgentErrorCode.invalidInput }
            let theme = try reader.definition(target.id, grant: grant, authorize: authorize)
            guard try reader.version(theme) == expected else { throw AgentErrorCode.versionConflict }
            guard ["custom", "file"].contains(theme.type) else { throw AgentErrorCode.invalidInput }
            reference = ["type": theme.type, "uuid": target.id.uuidString, "name": theme.name]
            themeID = target.id; name = nil
        } else {
            guard request.targets.isEmpty, case .string(let value) = parameters["name"] else { throw AgentErrorCode.invalidInput }
            reference = ["type": "builtIn", "name": value]
            themeID = nil; name = value
        }
        let data: Data
        do {
            data = try EditorThemePreferences(defaults: defaults).selectionData(reference: reference,
                dark: appearance == "dark", themes: library.themes, validateFile: { theme in
                    let actual = try reader.definition(theme.id, grant: grant, authorize: authorize)
                    guard case .string(let expected) = parameters["expectedThemeVersion"],
                          try reader.version(actual) == expected else { throw AgentErrorCode.versionConflict }
                })
        } catch let error as AgentErrorCode { throw error }
        catch { throw AgentErrorCode.storageError }
        try authorize()
        return Plan(appearance: appearance, reloadedVersion: nil, themeID: themeID, name: name, storage: [
            EditorThemePreferences.key: .data(data),
            ThemeCatalog.revisionKey: .scalar(.integer(Int64(defaults.integer(forKey: ThemeCatalog.revisionKey) &+ 1)))])
    }
}

// Source resolution runs before this plan. The plan does not save or select.
@MainActor enum AgentThemeImportPlanning {
    enum Input {
        case builtIn(String)
        case definition(EditorThemeDefinition)
        case file(ThemeFileAccess.Prepared)
    }
    struct Plan: Equatable {
        let definition: EditorThemeDefinition?
        let bookmark: Data?
        let builtInName: String?
        let appearance: String?
        let selectionVersion: String?
        let targetVersion: String?
    }

    static func resolve(_ request: AgentRequest, grant: AgentGrant, defaults: UserDefaults,
                        transfers: AgentTransferStore, authorize: () throws -> Void) throws -> Input {
        let parameters = try AgentAppearanceSchemas.validatedParameters(for: request)
        guard let source = parameters["source"], case .object(let fields) = source,
              case .string(let mode) = parameters["mode"] else { throw AgentErrorCode.invalidInput }
        try Task.checkCancellation(); try authorize()
        if fields["kind"] == .string("installationURL") {
            guard case .string(let raw) = fields["url"], let url = URL(string: raw) else { throw AgentErrorCode.invalidInput }
            do {
                switch try ThemeInstallation(url: url) {
                case .builtIn(let name): return .builtIn(name)
                case .custom(let definition): return .definition(definition)
                }
            } catch { throw AgentErrorCode.invalidInput }
        }
        let snapshot = try AgentImportReading.snapshot(source, grant: grant, defaults: defaults,
            transfers: transfers, maximumBytes: AgentRequest.maximumBytes,
            captureFilePermission: mode == "file", authorize: authorize)
        var definition: EditorThemeDefinition
        do { definition = try ThemeInstallation.decodeDefinition(snapshot.data, fallbackID: request.targets.first?.id ?? UUID(), maximumBytes: AgentRequest.maximumBytes) }
        catch { throw AgentErrorCode.invalidInput }
        try Task.checkCancellation(); try authorize()
        if mode == "file" {
            guard let permission = snapshot.filePermission else { throw AgentErrorCode.permissionDenied }
            definition.id = request.targets.first?.id ?? UUID(); definition.type = "file"
            return .file(.init(definition: definition, bookmark: permission))
        }
        return .definition(definition)
    }

    static func validateSource(_ request: AgentRequest, input: Input, defaults: UserDefaults,
                               authorize: () throws -> Void) throws {
        try Task.checkCancellation(); try authorize()
        if case .object(let source) = request.parameters["source"], source["kind"] == .string("bookmark") {
            guard case .string(let raw) = source["bookmarkID"], let id = UUID(uuidString: raw),
                  try BookmarkPreferences.agentRecords(defaults: defaults).contains(where: { $0.id == id }) else {
                throw AgentErrorCode.permissionDenied
            }
        }
        if case .file(let prepared) = input {
            let actual = try ThemeFileAccess.read(prepared, maximumBytes: AgentRequest.maximumBytes)
            guard try AgentRequestBinding.encoded(actual, maximum: AgentRequest.maximumBytes * 2)
                == AgentRequestBinding.encoded(prepared.definition, maximum: AgentRequest.maximumBytes * 2) else {
                throw AgentErrorCode.versionConflict
            }
        }
        try Task.checkCancellation(); try authorize()
    }

    static func prepare(_ request: AgentRequest, input: Input, grant: AgentGrant,
                        library: LibraryStore, reader: AgentThemeReading,
                        authorize: () throws -> Void) throws -> Plan {
        guard request.libraryID == grant.libraryID, ["themes.install", "themes.replace"].contains(request.operation) else { throw AgentErrorCode.invalidInput }
        guard grant.capabilities.isSuperset(of: [.appearanceManage, .filesRead]) else { throw AgentErrorCode.permissionDenied }
        try Task.checkCancellation(); try authorize()
        let parameters = try AgentAppearanceSchemas.validatedParameters(for: request)
        guard case .string(let mode) = parameters["mode"] else { throw AgentErrorCode.invalidInput }
        if case .object(let source) = parameters["source"], source["kind"] == .string("bookmark") {
            guard case .string(let raw) = source["bookmarkID"], let id = UUID(uuidString: raw),
                  grant.scope.permits(.init(kind: .bookmark, id: id)) else { throw AgentErrorCode.permissionDenied }
        }
        let appearance: String?, selectionVersion: String?
        if case .string(let value) = parameters["selectAppearance"], case .string(let token) = parameters["expectedSelectionVersion"] {
            guard try reader.selection(appearance: value, grant: grant)["versionToken"] == .string(token) else {
                throw AgentErrorCode.versionConflict
            }
            appearance = value; selectionVersion = token
        } else { appearance = nil; selectionVersion = nil }
        var definition: EditorThemeDefinition?, bookmark: Data?, builtInName: String?
        switch input {
        case .builtIn(let name):
            guard mode == "custom", request.operation == "themes.install", case .object(let source) = parameters["source"],
                  source["kind"] == .string("installationURL"), case .string(let raw) = source["url"],
                  let url = URL(string: raw), try ThemeInstallation(url: url) == .builtIn(name) else { throw AgentErrorCode.invalidInput }
            builtInName = name
        case .definition(var value):
            guard mode == "custom" else { throw AgentErrorCode.invalidInput }
            value.type = "custom"
            do { value = try DraftsThemeImport.applyingEditorChanges(value); try value.validate() }
            catch { throw AgentErrorCode.invalidInput }
            definition = value
        case .file(let prepared):
            guard mode == "file", prepared.definition.type == "file", !prepared.bookmark.isEmpty else { throw AgentErrorCode.invalidInput }
            do { try prepared.definition.validate() } catch { throw AgentErrorCode.invalidInput }
            definition = prepared.definition; bookmark = prepared.bookmark
        }
        let targetVersion: String?
        if request.operation == "themes.replace" {
            guard request.targets.count == 1, let target = request.targets.first, target.kind == .theme,
                  grant.scope.permits(target), var value = definition else { throw AgentErrorCode.permissionDenied }
            guard let previous = library.themes.first(where: { $0.id == target.id }) else { throw AgentErrorCode.notFound }
            let version = try reader.version(previous)
            guard request.expectedVersion == version else { throw AgentErrorCode.versionConflict }
            guard previous.type == value.type else { throw AgentErrorCode.invalidInput }
            // Explicit replacement keeps the target identity and cannot consume another installed ID.
            guard value.id == target.id || !library.themes.contains(where: { $0.id == value.id }) else {
                throw AgentErrorCode.versionConflict
            }
            value.id = target.id; definition = value; targetVersion = version
        } else {
            guard request.targets.isEmpty, request.expectedVersion == nil else { throw AgentErrorCode.invalidInput }
            targetVersion = nil
            // An existing identity or name needs an explicit versioned replacement.
            if let definition, library.themes.contains(where: { $0.id == definition.id }) { throw AgentErrorCode.versionConflict }
        }
        if let definition, library.themes.contains(where: {
            $0.id != request.targets.first?.id
                && $0.type == definition.type && $0.name == definition.name
        }) { throw AgentErrorCode.versionConflict }
        try Task.checkCancellation(); try authorize()
        return Plan(definition: definition, bookmark: bookmark, builtInName: builtInName,
                    appearance: appearance, selectionVersion: selectionVersion, targetVersion: targetVersion)
    }
}
