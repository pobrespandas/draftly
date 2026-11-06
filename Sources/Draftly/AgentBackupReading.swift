import Foundation
import CryptoKit
import DraftlyCore
import AgentContracts

// The existing restore engine validates backups in disposable libraries.
@MainActor final class AgentBackupReading {
    private let library: LibraryStore
    private let drafts: AgentDraftReading
    private let transfers: AgentTransferStore
    private let defaults: UserDefaults
    private let versionKey = SymmetricKey(size: .bits256)

    init(library: LibraryStore, drafts: AgentDraftReading, transfers: AgentTransferStore, defaults: UserDefaults) {
        self.library = library; self.drafts = drafts; self.transfers = transfers; self.defaults = defaults
    }
    private func check(_ authorize: () throws -> Void) throws {
        do { try Task.checkCancellation() } catch { throw AgentErrorCode.cancelled }
        try authorize()
    }
    private func source(_ parameters: [String: AgentJSONValue], grant: AgentGrant, authorize: () throws -> Void) throws -> Data {
        guard let source = parameters["source"] else { throw AgentErrorCode.invalidInput }
        return try AgentImportReading.data(source, grant: grant, defaults: defaults, transfers: transfers,
            maximumBytes: AgentTransferSchemas.maximumBytes, authorize: authorize)
    }
    private func counts(_ backup: Backup) -> AgentJSONValue {
        .object(["drafts": .integer(Int64(backup.notes.count)), "versions": .integer(Int64(backup.revisions.count)),
            "actions": .integer(Int64(backup.actions.count)), "actionGroups": .integer(Int64(backup.actionGroups?.count ?? 0)),
            "workspaces": .integer(Int64(backup.workspaces.count)), "themes": .integer(Int64(backup.themes?.count ?? 0)),
            "syntaxes": .integer(Int64(backup.syntaxes?.count ?? 0)), "runs": .integer(Int64(backup.runs?.count ?? 0))])
    }
    static func changes(_ before: Backup, _ after: Backup) -> AgentJSONValue {
        func count<T: Identifiable & Equatable>(_ old: [T], _ new: [T]) -> AgentJSONValue where T.ID == UUID {
            let values = Dictionary(uniqueKeysWithValues: old.map { ($0.id, $0) })
            return .object(["created": .integer(Int64(new.filter { values[$0.id] == nil }.count)),
                "updated": .integer(Int64(new.filter { item in values[item.id].map { $0 != item } ?? false }.count))])
        }
        return .object(["drafts": count(before.notes, after.notes), "versions": count(before.revisions, after.revisions),
            "actions": count(before.actions, after.actions), "actionGroups": count(before.actionGroups ?? [], after.actionGroups ?? []),
            "workspaces": count(before.workspaces, after.workspaces), "themes": count(before.themes ?? [], after.themes ?? []),
            "syntaxes": count(before.syntaxes ?? [], after.syntaxes ?? []), "runs": count(before.runs ?? [], after.runs ?? [])])
    }
    func importRead(_ request: AgentRequest, parameters: [String: AgentJSONValue], grant: AgentGrant,
                    sourceData: Data? = nil, authorize: () throws -> Void) throws -> [String: AgentJSONValue] {
        try check(authorize)
        guard case .string(let fileExtension) = parameters["fileExtension"] else { throw AgentErrorCode.invalidInput }
        let input = try sourceData ?? source(parameters, grant: grant, authorize: authorize)
        guard input.count <= AgentTransferSchemas.maximumBytes else { throw AgentErrorCode.invalidInput }
        let files = [LibraryFileImport.File(data: input, fileExtension: fileExtension)]
        do { _ = try LibraryFileImport.stage(files) }
        catch { throw AgentErrorCode.invalidInput }
        try check(authorize)
        if request.operation == "imports.validate" { return ["valid": .bool(true)] }
        guard request.operation == "imports.preview", grant.scope == .library else { throw AgentErrorCode.permissionDenied }
        try drafts.requireStoredDraftsForRestorePreview()
        let baseline = try library.backupData()
        let before = try JSONDecoder().decode(Backup.self, from: baseline)
        let staging: LibraryStore
        do { staging = try LibraryFileImport.stage(files, baseline: baseline) }
        catch { throw AgentErrorCode.versionConflict }
        let after = try JSONDecoder().decode(Backup.self, from: staging.backupData())
        let changes = Self.changes(before, after)
        let context = AgentJSONValue.object([
            "grant": AgentRequestBinding.grantValue(grant),
            "source": parameters["source"] ?? .null,
            "fileExtension": .string(fileExtension)
        ])
        let binding = Data("imports.preview:v1".utf8)
            + Data(SHA256.hash(data: try AgentRequestBinding.encoded(context, maximum: AgentRequest.maximumBytes * 2)))
            + Data(SHA256.hash(data: input)) + Data(SHA256.hash(data: baseline))
        let version = Data(HMAC<SHA256>.authenticationCode(for: binding, using: versionKey)).base64EncodedString()
        try check(authorize)
        return ["changes": changes, "versionToken": .string(version)]
    }

    func read(_ request: AgentRequest, parameters: [String: AgentJSONValue],
              grant: AgentGrant, sourceData: Data? = nil, authorize: () throws -> Void) throws -> [String: AgentJSONValue] {
        try check(authorize)
        guard grant.scope == .library else { throw AgentErrorCode.permissionDenied }
        if request.operation == "backups.export" {
            let data = try drafts.backupSnapshot()
            try check(authorize)
            return ["transfer": try transfers.export(data, resources: [], grant: grant)]
        }
        let data = try sourceData ?? source(parameters, grant: grant, authorize: authorize)
        guard data.count <= AgentTransferSchemas.maximumBytes else { throw AgentErrorCode.invalidInput }
        let incoming: Backup
        do {
            incoming = try JSONDecoder().decode(Backup.self, from: data)
            let validation = try LibraryStore(inMemory: true, seed: false)
            try validation.restore(data)
        } catch { throw AgentErrorCode.invalidInput }
        try check(authorize)
        if request.operation == "backups.validate" { return ["valid": .bool(true), "counts": counts(incoming)] }
        guard request.operation == "backups.previewRestore" else { throw AgentErrorCode.unavailable }
        try drafts.requireStoredDraftsForRestorePreview()
        let current = try library.backupData()
        let before = try JSONDecoder().decode(Backup.self, from: current)
        let staging = try LibraryStore(inMemory: true, seed: false)
        do { try staging.restore(current); try staging.restore(data) }
        catch { throw AgentErrorCode.versionConflict }
        let after = try JSONDecoder().decode(Backup.self, from: staging.backupData())
        try check(authorize)
        let binding = Data("backups.previewRestore:v1".utf8) + Data(SHA256.hash(data: current)) + Data(SHA256.hash(data: data))
        let version = Data(HMAC<SHA256>.authenticationCode(for: binding, using: versionKey)).base64EncodedString()
        return ["counts": counts(incoming), "changes": Self.changes(before, after), "versionToken": .string(version)]
    }
}
