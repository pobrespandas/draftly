import Foundation

struct ActionCatalog {
    private let actions: [DraftAction]
    private let groups: [ActionGroupRecord]

    init(actions: [DraftAction], groups: [ActionGroupRecord]) {
        self.actions = actions
        self.groups = groups
    }

    var groupNames: [String] {
        var seen = Set<String>()
        let known = groups.map(\.name).filter { seen.insert($0).inserted }
        return known + Set(actions.map(\.group)).subtracting(known).sorted()
    }

    var groupIdentifiers: [String: UUID] {
        ActionGroupIdentity.identifiers(names: groupNames, records: groups)
    }

    func groupNames(on surface: ActionSurface) -> [String] {
        groupNames.filter { groupRecord(named: $0).appears(on: surface) }
    }

    func groupRecord(named name: String) -> ActionGroupRecord {
        if let record = groups.first(where: { $0.name == name }) { return record }
        var record = ActionGroupRecord(name: name)
        record.id = ActionGroupIdentity.identifiers(names: groupNames + [name], records: groups,
            preferred: groupIdentifiers)[name]!
        return record
    }

    func orderedActions(on surface: ActionSurface?) -> [DraftAction] {
        let names = groupNames
        let visibleGroups = surface.map { Set(groupNames(on: $0)) }
        let preferred = ["Copy", "Share", "Add to Reminders", "Add Calendar Event", "Save to File", "Markdown Preview"]
        return actions.filter { action in
            surface.map { action.appears(on: $0) && visibleGroups?.contains(action.group) == true } ?? true
        }.sorted { a, b in
            let ga = names.firstIndex(of: a.group) ?? Int.max, gb = names.firstIndex(of: b.group) ?? Int.max
            if ga != gb { return ga < gb }
            let x = a.options?.order ?? preferred.firstIndex(of: a.name) ?? 100
            let y = b.options?.order ?? preferred.firstIndex(of: b.name) ?? 100
            return x == y ? (a.name == b.name ? a.id.uuidString < b.id.uuidString : a.name.localizedStandardCompare(b.name) == .orderedAscending) : x < y
        }
    }
}
