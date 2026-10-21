import AppKit
import SwiftUI
import DraftlyCore

struct DraftSelectionRow {
    let note: Note
    let title: String
    let lastAction: String?
    let options: DraftListOptions

    init?(item: [String: Any], options: DraftListOptions) {
        guard let values = item["draft"] as? [String: Any],
              let id = (values["uuid"] as? String).flatMap(UUID.init(uuidString:)),
              let content = values["content"] as? String else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        func date(_ key: String) -> Date? {
            guard let text = values[key] as? String else { return nil }
            return formatter.date(from: text) ?? ISO8601DateFormatter().date(from: text)
        }
        guard let created = date("createdAt"), let modified = date("modifiedAt") else { return nil }
        var note = Note(id: id, content: content, tags: values["tags"] as? [String] ?? [], flag: values["flagType"] as? Int ?? 0)
        note.createdAt = created; note.modifiedAt = modified
        self.note = note; self.title = item["title"] as? String ?? note.title
        self.lastAction = options.showLastAction ? item["lastAction"] as? String : nil
        self.options = options
    }

    static func options(_ values: [String: Any]) -> DraftListOptions {
        var options = DraftListOptions()
        options.showPreview = values["showPreview"] as? Bool ?? options.showPreview
        options.previewLines = values["previewLines"] as? Int ?? options.previewLines
        options.showTags = values["showTags"] as? Bool ?? options.showTags
        options.showDate = values["showDate"] as? Bool ?? options.showDate
        options.showLastAction = values["showLastAction"] as? Bool ?? options.showLastAction
        options.searchTitlesOnly = values["searchTitlesOnly"] as? Bool ?? options.searchTitlesOnly
        options.caseSensitiveSearch = values["caseSensitiveSearch"] as? Bool ?? options.caseSensitiveSearch
        options.previewSearchMatches = values["previewSearchMatches"] as? Bool ?? options.previewSearchMatches
        options.highlightFlagged = values["highlightFlagged"] as? Bool ?? options.highlightFlagged
        return options
    }

    func matches(_ query: String) -> Bool {
        var workspace = Workspace(name: "Draft selection")
        workspace.folder = .all; workspace.query = query; workspace.listOptions = options
        return !workspace.filter([note]).isEmpty
    }

    func height(width: CGFloat, query: String = "") -> CGFloat {
        DraftRowPresentation.height(note: note, width: max(80, width - 12), showPreview: options.showPreview,
            previewLines: options.previewLines, showTags: options.showTags, showDate: options.showDate, lastAction: lastAction != nil, query: options.previewSearchMatches ? query : "")
    }

    @MainActor func view(width: CGFloat, emphasized: Bool, query: String = "") -> NSView {
        let row = DraftTableRow(note: note, title: title, showPreview: options.showPreview,
            previewLines: options.previewLines, showTags: options.showTags, showDate: options.showDate,
            query: options.previewSearchMatches ? query : "", lastAction: lastAction, highlightFlagged: options.highlightFlagged, emphasized: emphasized)
        return NSHostingView(rootView: row.padding(.horizontal, 6).padding(.top, DraftRowPresentation.verticalInset)
            .padding(.bottom, DraftRowPresentation.bottomInset).frame(width: max(80, width), height: height(width: width, query: query)))
    }
}
