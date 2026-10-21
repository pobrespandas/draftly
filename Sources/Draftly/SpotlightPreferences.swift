import Combine
import CoreSpotlight
import DraftlyCore
import UniformTypeIdentifiers

struct SpotlightDraft: Equatable, Sendable {
    let id: UUID
    let title: String
    let content: String
    let tags: [String]
    let createdAt: Date
    let modifiedAt: Date

    init(_ note: Note) {
        id = note.id; title = note.title; content = note.content
        tags = note.tags; createdAt = note.createdAt; modifiedAt = note.modifiedAt
    }
}

@MainActor
final class SpotlightPreferences: ObservableObject {
    static let enabledKey = "application.indexDraftsInSpotlight"
    static let hasIndexKey = "application.spotlightHasIndex"
    @Published private(set) var isEnabled: Bool
    @Published private(set) var isChanging = false
    @Published private(set) var error: String?
    let isAvailable: Bool
    private let defaults: UserDefaults
    private let replace: ([SpotlightDraft]) async throws -> Void
    private let clear: () async throws -> Void
    private var subscription: AnyCancellable?
    private var drafts: [SpotlightDraft] = []
    private var pendingUpdate = false
    private var updateTask: Task<Void, Never>?

    convenience init(defaults: UserDefaults = .standard) {
        let index = CSSearchableIndex.default()
        let domain = (Bundle.main.bundleIdentifier ?? ApplicationIdentityMigration.identifier) + ".drafts"
        self.init(defaults: defaults, isAvailable: CSSearchableIndex.isIndexingAvailable(), replace: { drafts in
            try await index.deleteSearchableItems(withDomainIdentifiers: [domain])
            let items = Self.searchableItems(drafts, domain: domain)
            if !items.isEmpty { try await index.indexSearchableItems(items) }
        }, clear: {
            try await index.deleteSearchableItems(withDomainIdentifiers: [domain])
        })
    }

    static func searchableItems(_ drafts: [SpotlightDraft], domain: String) -> [CSSearchableItem] {
        drafts.map { draft in
            let attributes = CSSearchableItemAttributeSet(contentType: .plainText)
            attributes.title = draft.title
            attributes.contentDescription = draft.content
            attributes.textContent = draft.content
            attributes.keywords = draft.tags
            attributes.contentCreationDate = draft.createdAt
            attributes.contentModificationDate = draft.modifiedAt
            let item = CSSearchableItem(uniqueIdentifier: draft.id.uuidString, domainIdentifier: domain, attributeSet: attributes)
            item.expirationDate = .distantFuture
            return item
        }
    }

    init(defaults: UserDefaults, isAvailable: Bool,
         replace: @escaping ([SpotlightDraft]) async throws -> Void,
         clear: @escaping () async throws -> Void) {
        self.defaults = defaults; self.isAvailable = isAvailable
        self.replace = replace; self.clear = clear
        isEnabled = defaults.object(forKey: Self.enabledKey) as? Bool ?? false
    }

    func attach(to library: LibraryStore) {
        subscription = library.$notes.map { notes in
            notes.filter { $0.trashedAt == nil }.map(SpotlightDraft.init)
                .sorted { $0.id.uuidString < $1.id.uuidString }
        }.removeDuplicates().sink { [weak self] drafts in
            guard let self else { return }
            self.drafts = drafts
            if self.isEnabled || self.defaults.bool(forKey: Self.hasIndexKey) { self.scheduleUpdate() }
        }
    }

    func setEnabled(_ enabled: Bool) {
        guard isAvailable, enabled != isEnabled else { return }
        isEnabled = enabled
        defaults.set(enabled, forKey: Self.enabledKey)
        scheduleUpdate()
    }

    func retry() { guard isAvailable else { return }; scheduleUpdate() }

    private func scheduleUpdate() {
        guard isAvailable else { return }
        pendingUpdate = true
        guard updateTask == nil else { return }
        isChanging = true
        updateTask = Task { [weak self] in
            guard let self else { return }
            defer { self.updateTask = nil; self.isChanging = false }
            while self.pendingUpdate {
                self.pendingUpdate = false
                self.error = nil
                do {
                    if self.isEnabled {
                        self.defaults.set(true, forKey: Self.hasIndexKey)
                        try await self.replace(self.drafts)
                    } else {
                        try await self.clear()
                        self.defaults.set(false, forKey: Self.hasIndexKey)
                    }
                } catch {
                    self.error = error.localizedDescription
                }
            }
        }
    }

    func waitForUpdates() async { await updateTask?.value }

    static func draftID(activityType: String, userInfo: [AnyHashable: Any]?) -> UUID? {
        guard activityType == CSSearchableItemActionType,
              let identifier = userInfo?[CSSearchableItemActivityIdentifier] as? String else { return nil }
        return UUID(uuidString: identifier)
    }
}
