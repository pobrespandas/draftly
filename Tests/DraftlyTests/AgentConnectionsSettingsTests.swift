import Foundation
import Testing
import AgentContracts
@testable import Draftly

@Suite("Human agent connection settings") @MainActor
struct AgentConnectionsSettingsTests {
    @MainActor private final class Fixture {
        let libraryID = UUID()
        var bytes: Data?
        var secrets: [UUID: Data] = [:]
        var wall = Date(timeIntervalSince1970: 1_700_000_000)
        var elapsed: TimeInterval = 100
        var locked = false
        var failWrite = false
        var failDelete = false
        var failHostCommand = false
        var ignoreHostCommand = false
        var writes = 0
        var targets: Set<AgentResourceReference> = []
        var selected: Set<AgentResourceReference> = []
        var labels: [AgentConnectionsSettingsModel.ResourceChoice] = []
        var authorityChanges: [UUID] = []
        lazy var registry = makeRegistry()
        lazy var pairing = AgentPairingCoordinator(registry: registry, libraryID: libraryID,
            now: { [unowned self] in self.wall }, uptime: { [unowned self] in self.elapsed },
            validateHost: {}, isLocked: { [unowned self] in self.locked }, resolveTargets: { [unowned self] in $0.intersection(self.targets) })
        func makeRegistry() -> AgentConnectionRegistry {
            AgentConnectionRegistry(metadata: .init(read: { [unowned self] in self.bytes }, replace: { [unowned self] value, expected in
                guard !self.failWrite else { throw AgentErrorCode.storageError }
                guard self.bytes == expected else { throw AgentErrorCode.versionConflict }
                self.writes += 1; self.bytes = value
            }), credentials: .init(read: { [unowned self] in self.secrets[$0] },
                create: { [unowned self] in self.secrets[$0] = $1 }, remove: { [unowned self] id in
                    guard !self.failDelete else { throw AgentErrorCode.storageError }
                    self.secrets.removeValue(forKey: id)
                }), now: { [unowned self] in self.wall }, authorityChanged: { [unowned self] in self.authorityChanges.append($0) })
        }
        func model() throws -> AgentConnectionsSettingsModel {
            try AgentConnectionsSettingsModel(libraryID: libraryID, registry: registry, pairing: pairing,
                now: { [unowned self] in self.wall }, choices: { [unowned self] in self.labels },
                initialTargets: { [unowned self] in self.selected }, resolveTargets: { [unowned self] in $0.intersection(self.targets) },
                setAccessEnabled: { [unowned self] value in
                    if self.failHostCommand { throw AgentErrorCode.unavailable }
                    if !self.ignoreHostCommand { try self.registry.setEnabledFromUserInterface(value) }
                })
        }
        func connect(libraryID: UUID? = nil) throws -> AgentConnectionRecord {
            try registry.connectFromUserInterface(name: "Neutral 🐼", libraryID: libraryID ?? self.libraryID)
        }
        func request() throws -> AgentPairingCoordinator.Challenge {
            try registry.setEnabledFromUserInterface(true)
            return try pairing.request(clientName: "Untrusted client label")
        }
    }

    @Test func openingRefreshingAndCancellingDoNotWriteDefaultsOrCredentials() throws {
        let f = Fixture(), model = try f.model()
        model.refresh(); model.cancelEditing()
        #expect(!model.accessEnabled && model.readable && model.connections.isEmpty)
        #expect(f.bytes == nil && f.secrets.isEmpty && f.writes == 0)
        let record = try f.connect(); model.refresh(); let before = f.bytes
        try model.beginEditing(record.id)
        model.draft?.capabilities.insert(.draftsWrite)
        model.draft?.wholeLibrary = true
        model.cancelEditing()
        #expect(f.bytes == before && model.draft == nil && model.context == nil)
        #expect(try f.registry.configurationForUserInterface().connections[0].grantID == record.grantID)
    }

    @Test func saveReplacesOnlyTheChosenGrantAndRotatesItsIdentity() throws {
        let f = Fixture(), a = try f.connect(), b = try f.connect(), model = try f.model()
        let target = AgentResourceReference(kind: .draft, id: UUID()); f.targets = [target]
        try model.beginEditing(a.id)
        model.draft?.capabilities.insert(.draftsWrite)
        model.draft?.targets = [target]
        model.draft?.expiresAt = f.wall.addingTimeInterval(90)
        model.draft?.renewable = true
        try model.saveExisting()
        let saved = try #require(model.connections.first { $0.id == a.id })
        #expect(saved.grantID != a.grantID && saved.grant.capabilities == [.draftsRead, .draftsWrite])
        #expect(saved.grant.scope == .resources([target]) && saved.renewable)
        #expect(saved.expiresAt == f.wall.addingTimeInterval(90))
        #expect(model.connections.first { $0.id == b.id }?.grantID == b.grantID)
        #expect(model.draft == nil && f.authorityChanges.contains(a.id))
        #expect(f.secrets.count == 2)
    }

    @Test func staleEditingCopiesCannotOverwriteAReplacementGrant() throws {
        let f = Fixture(), record = try f.connect(), first = try f.model(), second = try f.model()
        try first.beginEditing(record.id); try second.beginEditing(record.id)
        first.draft?.wholeLibrary = true; try first.saveExisting()
        let after = f.bytes
        second.draft?.capabilities.insert(.actionsManage)
        #expect(throws: AgentErrorCode.versionConflict) { try second.saveExisting() }
        #expect(f.bytes == after && second.draft?.capabilities.contains(.actionsManage) == true)
        #expect(second.lastError == .versionConflict)
    }

    @Test func failedGrantSaveKeepsTheEditingCopyAndShowsImmediateBlocking() throws {
        let f = Fixture(), record = try f.connect(), model = try f.model()
        try f.registry.setEnabledFromUserInterface(true); model.refresh()
        try model.beginEditing(record.id); model.draft?.capabilities.insert(.draftsWrite)
        let copy = model.draft
        f.failWrite = true
        #expect(throws: AgentErrorCode.storageError) { try model.saveExisting() }
        #expect(model.draft == copy && model.lastError == .storageError)
        #expect(model.status(record) == .needsReview)
        #expect(try f.registry.grantForAuthenticatedConnection(record.id) == nil)
    }

    @Test func deletedResourcesAndInvalidDatesDoNotPersistGrantChanges() throws {
        let f = Fixture(), record = try f.connect(), model = try f.model(), before = f.bytes
        try model.beginEditing(record.id)
        model.draft?.targets = [.init(kind: .draft, id: UUID())]
        #expect(throws: AgentErrorCode.notFound) { try model.saveExisting() }
        #expect(model.resourceChoices().count == 1)
        model.draft?.targets = []
        model.draft?.expiresAt = f.wall
        #expect(throws: AgentErrorCode.invalidInput) { try model.saveExisting() }
        model.draft?.expiresAt = f.wall.addingTimeInterval(1)
        model.draft?.name = "Unsupported rename"
        #expect(throws: AgentErrorCode.invalidInput) { try model.saveExisting() }
        #expect(f.bytes == before && model.draft != nil)
    }

    @Test func pairingStartsFromTheHumanSelectionAndCancelLeavesNoGrant() throws {
        let f = Fixture(), q = try f.request(), model = try f.model()
        let target = AgentResourceReference(kind: .draft, id: UUID()); f.targets = [target]; f.selected = [target]
        let before = f.bytes
        try model.beginPairing(q.id)
        #expect(model.draft?.capabilities == [.draftsRead] && model.draft?.targets == [target])
        #expect(model.draft?.wholeLibrary == false && model.draft?.renewable == false)
        f.selected = []
        #expect(model.draft?.targets == [target])
        try model.preparePairingReview()
        #expect(model.review?.scope == .resources([target]))
        model.cancelEditing()
        #expect(f.bytes == before && f.secrets.isEmpty)
        #expect(try f.pairing.state(q.id) == .pending)
    }

    @Test func codeComparisonAndAnUnchangedReviewAreRequiredBeforeApproval() throws {
        let f = Fixture(), q = try f.request(), model = try f.model()
        try model.beginPairing(q.id); try model.preparePairingReview()
        #expect(throws: AgentErrorCode.interactionRequired) { try model.approvePairing(codesMatch: false) }
        #expect(f.secrets.isEmpty)
        model.draft?.capabilities.insert(.draftsWrite)
        #expect(model.review == nil)
        #expect(throws: AgentErrorCode.invalidInput) { try model.approvePairing(codesMatch: true) }
        try model.preparePairingReview()
        let record = try model.approvePairing(codesMatch: true)
        #expect(record.grant.capabilities == [.draftsRead, .draftsWrite])
        #expect(model.draft == nil && model.pending.isEmpty)
        #expect(try f.pairing.state(q.id) == .approved(connectionID: record.id))
    }

    @Test func changingReviewChoicesOrExpiringTheChallengeRequiresNewConsent() throws {
        let f = Fixture(), q = try f.request(), model = try f.model()
        try model.beginPairing(q.id); try model.preparePairingReview()
        let copy = model.draft
        model.changeReviewChoices()
        #expect(model.review == nil && model.draft == copy)
        try model.preparePairingReview()
        f.wall += 300; f.elapsed += 300
        model.refresh()
        #expect(!model.canReviewPairing && model.review == nil && model.draft == copy)
        #expect(throws: AgentErrorCode.invalidInput) { try model.approvePairing(codesMatch: true) }
        #expect(f.secrets.isEmpty)
    }

    @Test func failedPairingSaveKeepsChoicesButCannotRetryTheTerminalRequest() throws {
        let f = Fixture(), q = try f.request(), model = try f.model()
        try model.beginPairing(q.id); model.draft?.wholeLibrary = true
        try model.preparePairingReview(); let copy = model.draft
        f.failWrite = true
        #expect(throws: AgentErrorCode.storageError) { try model.approvePairing(codesMatch: true) }
        #expect(model.draft == copy && model.review == nil && !model.canReviewPairing)
        f.failWrite = false
        #expect(throws: AgentErrorCode.permissionDenied) { try model.preparePairingReview() }
        #expect(f.secrets.isEmpty)
    }

    @Test func revocationIsImmediateAndCleanupWarningsRemainPerConnection() throws {
        let f = Fixture(), a = try f.connect(), b = try f.connect(), model = try f.model()
        try f.registry.setEnabledFromUserInterface(true)
        f.failDelete = true
        try model.revoke(a.id)
        #expect(model.cleanupPendingIDs == [a.id] && model.status(a) == .revoked)
        #expect(try f.registry.grantForAuthenticatedConnection(a.id) == nil)
        f.failDelete = false; try model.revoke(b.id)
        #expect(model.cleanupPendingIDs == [a.id])
        try model.revoke(a.id)
        #expect(!model.cleanupPending && f.secrets.isEmpty)
    }

    @Test func failedRevocationAndDisableDoNotDisplayActiveAuthority() throws {
        let f = Fixture(), record = try f.connect(), q = try f.request(), model = try f.model()
        f.failWrite = true; f.failDelete = true
        #expect(throws: AgentErrorCode.outcomeUnknown) { try model.revoke(record.id) }
        #expect(model.status(record) == .needsReview)
        #expect(throws: AgentErrorCode.storageError) { try model.setEnabled(false) }
        #expect(!model.accessEnabled)
        #expect(try f.pairing.state(q.id) == .invalidated)
    }

    @Test func enablingUsesTheHostCommandAndRejectsAFalseSuccess() throws {
        let f = Fixture(), model = try f.model()
        f.failHostCommand = true
        #expect(throws: AgentErrorCode.unavailable) { try model.setEnabled(true) }
        #expect(f.bytes == nil && !model.accessEnabled)
        f.failHostCommand = false; f.ignoreHostCommand = true
        #expect(throws: AgentErrorCode.outcomeUnknown) { try model.setEnabled(true) }
        #expect(!model.accessEnabled)
        f.ignoreHostCommand = false
        try model.setEnabled(true)
        #expect(model.accessEnabled)
        try model.setEnabled(false)
        #expect(!model.accessEnabled)
    }

    @Test func corruptMetadataPreservesTheCopyAndBlocksNewReview() throws {
        let f = Fixture(), record = try f.connect(), model = try f.model()
        try model.beginEditing(record.id)
        let copy = model.draft
        f.bytes = Data("invalid metadata".utf8); model.refresh()
        #expect(!model.readable && !model.accessEnabled && model.draft == copy)
        #expect(model.lastError == .storageError)
        #expect(throws: AgentErrorCode.storageError) { try model.saveExisting() }
        #expect(model.draft == copy)
    }

    @Test func otherLibrariesAndMismatchedCoordinatorsCannotBeManaged() throws {
        let f = Fixture(), record = try f.connect(libraryID: UUID()), model = try f.model()
        #expect(model.connections.isEmpty)
        #expect(throws: AgentErrorCode.notFound) { try model.beginEditing(record.id) }
        #expect(throws: AgentErrorCode.notFound) { try model.revoke(record.id) }
        #expect(throws: AgentErrorCode.invalidInput) {
            try AgentConnectionsSettingsModel(libraryID: UUID(), registry: f.registry, pairing: f.pairing,
                choices: { [] }, resolveTargets: { $0 }, setAccessEnabled: { _ in })
        }
        #expect(throws: AgentErrorCode.invalidInput) {
            try AgentConnectionsSettingsModel(libraryID: f.libraryID, registry: f.makeRegistry(), pairing: f.pairing,
                choices: { [] }, resolveTargets: { $0 }, setAccessEnabled: { _ in })
        }
    }

    @Test func missingSelectedIDsStayVisibleAndDuplicateChoicesAreRemoved() throws {
        let f = Fixture(), record = try f.connect(), model = try f.model()
        let a = AgentResourceReference(kind: .draft, id: UUID()), missing = AgentResourceReference(kind: .action, id: UUID())
        f.labels = [.init(reference: a, title: "Same 🐼"), .init(reference: a, title: "duplicate")]
        try model.beginEditing(record.id); model.draft?.targets = [a, missing]
        let choices = model.resourceChoices()
        #expect(choices.map(\.reference) == [a, missing] && choices[0].title == "Same 🐼")
        #expect(choices[1].accessibilityTitle.contains(missing.id.uuidString))
        model.draft?.wholeLibrary = true; model.draft?.wholeLibrary = false
        #expect(model.draft?.targets == [a, missing])
    }

    @Test func displayStatesAndLabelsCoverAllCapabilitiesWithoutChangingStorage() throws {
        let f = Fixture(), record = try f.connect(), model = try f.model(), before = f.bytes
        #expect(model.status(record) == .paused)
        try f.registry.setEnabledFromUserInterface(true); model.refresh()
        #expect(model.status(record) == .active)
        f.wall = record.expiresAt; model.refresh()
        #expect(model.status(record) == .inactive)
        #expect(AgentCapability.allCases.allSatisfy { !$0.userTitle.isEmpty })
        #expect(Set(AgentCapability.allCases.map(\.userTitle)).count == AgentCapability.allCases.count)
        #expect(AgentResourceKind.allCases.allSatisfy { !$0.userTitle.isEmpty })
        #expect(AgentErrorCode.allCases.allSatisfy { !$0.connectionMessage.isEmpty })
        // Only the explicit enable above writes; presentation reads do not.
        #expect(f.writes == 2 && f.bytes != before)
    }

    @Test func resourceAccessibilityNamesIncludeTitlesAndDistinguishHomonyms() {
        let first = AgentConnectionsSettingsModel.ResourceChoice(reference: .init(kind: .draft, id: UUID()), title: "Same 🐼")
        let second = AgentConnectionsSettingsModel.ResourceChoice(reference: .init(kind: .draft, id: UUID()), title: "Same 🐼")
        #expect(first.accessibilityTitle.contains("Same 🐼") && second.accessibilityTitle.contains("Same 🐼"))
        #expect(first.accessibilityTitle.contains(first.reference.id.uuidString))
        #expect(second.accessibilityTitle.contains(second.reference.id.uuidString))
        #expect(first.accessibilityTitle != second.accessibilityTitle)
    }


    @Test func recreatedSettingsReadTheSavedGrantFromSerializedMetadata() throws {
        let f = Fixture(), record = try f.connect(), model = try f.model()
        let target = AgentResourceReference(kind: .draft, id: UUID()); f.targets = [target]
        try model.beginEditing(record.id)
        model.draft?.capabilities = [.draftsRead, .actionsRead]
        model.draft?.targets = [target]
        model.draft?.renewable = true
        model.draft?.expiresAt = f.wall.addingTimeInterval(600)
        try model.saveExisting()
        let registry = f.makeRegistry()
        let pairing = AgentPairingCoordinator(registry: registry, libraryID: f.libraryID,
            now: { f.wall }, validateHost: {}, isLocked: { false }, resolveTargets: { $0.intersection(f.targets) })
        let recreated = try AgentConnectionsSettingsModel(libraryID: f.libraryID, registry: registry, pairing: pairing,
            now: { f.wall }, choices: { [] }, resolveTargets: { $0.intersection(f.targets) },
            setAccessEnabled: { try registry.setEnabledFromUserInterface($0) })
        let stored = try #require(recreated.connections.first)
        #expect(stored.id == record.id && stored.grantID != record.grantID)
        try recreated.beginEditing(record.id)
        #expect(recreated.draft?.capabilities == [.draftsRead, .actionsRead])
        #expect(recreated.draft?.targets == [target] && recreated.draft?.renewable == true)
        #expect(recreated.draft?.expiresAt == f.wall.addingTimeInterval(600))
    }

}
