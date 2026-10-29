import Foundation
import CryptoKit

public enum ActionSurface { case list, bar, search }

public struct ActionPresentation: Codable, Equatable {
    public var unknownFields: [String: JSONValue] = [:]
    public var description = ""
    public var tintColor: String?
    public var barLabel: String?
    public var barUsesIcon: Bool?
    public var showInList = true
    public var showInBar = true
    public var showInSearch = true
    public var confirmBeforeRun = false
    public var notifyOnSuccess = false
    public var notifyOnError = false
    public var logLevel: Int?
    public var addTags: [String] = []
    public var removeTags: [String] = []
    public var flagAfterSuccess: Int?
    public var section = ""
    public var order = 0
    public init() {}
}

public struct ActionGroupRecord: Codable, Equatable, Identifiable {
    public var id = UUID()
    public var name: String
    public var symbol = "arrow.up.right.square"
    public var order = 0
    var importedMetadata: [String: JSONValue] = [:]
    public init(name: String) { self.name = name; id = Self.identifier(for: name) }
    private enum CodingKeys: String, CodingKey { case id, name, symbol, order, importedMetadata }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        symbol = try c.decode(String.self, forKey: .symbol)
        order = try c.decode(Int.self, forKey: .order)
        importedMetadata = try c.decodeIfPresent([String: JSONValue].self, forKey: .importedMetadata) ?? [:]
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id); try c.encode(name, forKey: .name)
        try c.encode(symbol, forKey: .symbol); try c.encode(order, forKey: .order)
        if !importedMetadata.isEmpty { try c.encode(importedMetadata, forKey: .importedMetadata) }
    }
    public static func identifier(for name: String) -> UUID {
        var bytes = [UInt8](repeating: 0, count: 16)
        for (index, value) in name.utf8.enumerated() { bytes[index % 16] = bytes[index % 16] &* 31 &+ value }
        return UUID(uuid: (bytes[0],bytes[1],bytes[2],bytes[3],bytes[4],bytes[5],bytes[6],bytes[7],bytes[8],bytes[9],bytes[10],bytes[11],bytes[12],bytes[13],bytes[14],bytes[15]))
    }
}

public enum ActionGroupIdentity {
    public static func identifiers(names: [String], records: [ActionGroupRecord],
                                   preferred: [String: UUID] = [:]) -> [String: UUID] {
        let records = firstRecords(records)
        var result = Dictionary(uniqueKeysWithValues: records.map { ($0.name, $0.id) })
        var occupied = Set(records.map(\.id))
        let missing = Set(names).subtracting(result.keys).sorted()
        for name in missing.filter({ preferred[$0] != nil }) + missing.filter({ preferred[$0] == nil }) {
            var candidate = preferred[name] ?? ActionGroupRecord.identifier(for: name)
            var attempt = 0
            while occupied.contains(candidate) {
                candidate = collisionIdentifier(name: name, attempt: attempt)
                attempt += 1
            }
            result[name] = candidate
            occupied.insert(candidate)
        }
        return result
    }

    public static func collisionNames(names: [String], records: [ActionGroupRecord]) -> Set<String> {
        let records = firstRecords(records)
        let names = Set(names).union(records.map(\.name))
        let legacyOwners = Dictionary(grouping: names, by: ActionGroupRecord.identifier(for:))
        let storedOwners = Dictionary(grouping: records, by: \.id)
        return Set(names.filter { name in
            let legacy = ActionGroupRecord.identifier(for: name)
            return (legacyOwners[legacy]?.count ?? 0) > 1 ||
                storedOwners[legacy]?.contains(where: { $0.name != name }) == true
        })
    }

    private static func firstRecords(_ records: [ActionGroupRecord]) -> [ActionGroupRecord] {
        var seen: Set<String> = []
        return records.filter { seen.insert($0.name).inserted }
    }

    private static func collisionIdentifier(name: String, attempt: Int) -> UUID {
        let input = Data("Draftly action group identity v1\u{0}\(name)\u{0}\(attempt)".utf8)
        var bytes = Array(SHA256.hash(data: input).prefix(16))
        bytes[6] = (bytes[6] & 0x0f) | 0x80
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        return UUID(uuid: (bytes[0],bytes[1],bytes[2],bytes[3],bytes[4],bytes[5],bytes[6],bytes[7],
                           bytes[8],bytes[9],bytes[10],bytes[11],bytes[12],bytes[13],bytes[14],bytes[15]))
    }
}

public extension DraftAction {
    var presentation: ActionPresentation {
        get { options ?? ActionPresentation() }
        set { options = newValue }
    }
    func appears(on surface: ActionSurface) -> Bool {
        switch surface { case .list: presentation.showInList; case .bar: presentation.showInBar; case .search: presentation.showInSearch }
    }
}

public struct DraftListOptions: Codable, Equatable {
    public var showPreview = true
    public var previewLines = 2
    public var showTags = true
    public var showDate = true
    public var searchTitlesOnly = false
    public var caseSensitiveSearch = false
    public var previewSearchMatches = false
    public var showLastAction = false
    public var highlightFlagged = false
    public init() {}
}
