import Foundation

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
    public init(name: String) { self.name = name; id = Self.identifier(for: name) }
    public static func identifier(for name: String) -> UUID {
        var bytes = [UInt8](repeating: 0, count: 16)
        for (index, value) in name.utf8.enumerated() { bytes[index % 16] = bytes[index % 16] &* 31 &+ value }
        return UUID(uuid: (bytes[0],bytes[1],bytes[2],bytes[3],bytes[4],bytes[5],bytes[6],bytes[7],bytes[8],bytes[9],bytes[10],bytes[11],bytes[12],bytes[13],bytes[14],bytes[15]))
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
