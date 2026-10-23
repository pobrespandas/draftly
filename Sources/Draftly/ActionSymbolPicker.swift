import SwiftUI

struct ActionSymbolOption: Identifiable, Equatable {
    let name: String
    let title: String
    let keywords: String

    var id: String { name }
}

enum ActionSymbolCatalog {
    static let options: [ActionSymbolOption] = [
        .init(name: "bolt", title: "Bolt", keywords: "action power"),
        .init(name: "doc.on.doc", title: "Copy", keywords: "duplicate clipboard"),
        .init(name: "square.and.arrow.up", title: "Share", keywords: "export send"),
        .init(name: "folder", title: "Folder", keywords: "file save directory"),
        .init(name: "checklist", title: "Checklist", keywords: "task reminders list"),
        .init(name: "calendar", title: "Calendar", keywords: "date event"),
        .init(name: "envelope", title: "Mail", keywords: "email send"),
        .init(name: "message", title: "Message", keywords: "chat text send"),
        .init(name: "terminal", title: "Terminal", keywords: "shell command script"),
        .init(name: "globe", title: "Web", keywords: "internet browser url"),
        .init(name: "wand.and.stars", title: "Magic Wand", keywords: "transform format"),
        .init(name: "pencil", title: "Pencil", keywords: "edit write"),
        .init(name: "doc", title: "Document", keywords: "draft note file"),
        .init(name: "doc.text", title: "Text Document", keywords: "draft note file"),
        .init(name: "doc.badge.plus", title: "New Document", keywords: "create draft note file"),
        .init(name: "tray", title: "Inbox", keywords: "capture collect"),
        .init(name: "archivebox", title: "Archive", keywords: "store box"),
        .init(name: "trash", title: "Trash", keywords: "delete remove"),
        .init(name: "tag", title: "Tag", keywords: "label organize"),
        .init(name: "flag", title: "Flag", keywords: "mark organize"),
        .init(name: "star", title: "Star", keywords: "favorite bookmark"),
        .init(name: "heart", title: "Heart", keywords: "favorite like"),
        .init(name: "bookmark", title: "Bookmark", keywords: "mark save"),
        .init(name: "link", title: "Link", keywords: "url reference"),
        .init(name: "paperclip", title: "Attachment", keywords: "file attach"),
        .init(name: "magnifyingglass", title: "Search", keywords: "find lookup"),
        .init(name: "arrow.triangle.2.circlepath", title: "Refresh", keywords: "sync reload"),
        .init(name: "arrow.uturn.backward", title: "Undo", keywords: "back revert"),
        .init(name: "arrow.uturn.forward", title: "Redo", keywords: "forward repeat"),
        .init(name: "arrow.up", title: "Up", keywords: "move navigation"),
        .init(name: "arrow.down", title: "Down", keywords: "move navigation"),
        .init(name: "arrow.left", title: "Left", keywords: "move navigation"),
        .init(name: "arrow.right", title: "Right", keywords: "move navigation"),
        .init(name: "checkmark.circle", title: "Complete", keywords: "done success task"),
        .init(name: "xmark.circle", title: "Cancel", keywords: "stop close error"),
        .init(name: "exclamationmark.triangle", title: "Warning", keywords: "alert error"),
        .init(name: "info.circle", title: "Information", keywords: "help details"),
        .init(name: "questionmark.circle", title: "Help", keywords: "question prompt"),
        .init(name: "gearshape", title: "Settings", keywords: "configure preferences"),
        .init(name: "slider.horizontal.3", title: "Options", keywords: "configure filter preferences"),
        .init(name: "lock", title: "Lock", keywords: "secure private"),
        .init(name: "key", title: "Key", keywords: "secure password"),
        .init(name: "person", title: "Person", keywords: "contact user"),
        .init(name: "person.2", title: "People", keywords: "contacts group users"),
        .init(name: "clock", title: "Clock", keywords: "time history"),
        .init(name: "timer", title: "Timer", keywords: "time countdown"),
        .init(name: "bell", title: "Notification", keywords: "alert reminder"),
        .init(name: "location", title: "Location", keywords: "map coordinates"),
        .init(name: "map", title: "Map", keywords: "location directions"),
        .init(name: "mic", title: "Microphone", keywords: "dictation record voice audio"),
        .init(name: "speaker.wave.2", title: "Speaker", keywords: "speech read voice audio"),
        .init(name: "waveform", title: "Waveform", keywords: "transcription record sound audio"),
        .init(name: "camera", title: "Camera", keywords: "photo scan image"),
        .init(name: "photo", title: "Photo", keywords: "picture image"),
        .init(name: "eye", title: "Preview", keywords: "view markdown html"),
        .init(name: "printer", title: "Print", keywords: "paper document"),
        .init(name: "list.bullet", title: "List", keywords: "items text"),
        .init(name: "textformat", title: "Text Format", keywords: "font typography"),
        .init(name: "bold", title: "Bold", keywords: "format markdown text"),
        .init(name: "italic", title: "Italic", keywords: "format markdown text"),
        .init(name: "curlybraces", title: "Code", keywords: "javascript script source"),
        .init(name: "number", title: "Number", keywords: "count hashtag heading"),
        .init(name: "scissors", title: "Cut", keywords: "clipboard text"),
        .init(name: "paperplane", title: "Send", keywords: "mail message share")
    ]

    static func options(matching search: String, currentSymbol: String) -> [ActionSymbolOption] {
        var candidates = options
        if !currentSymbol.isEmpty, !candidates.contains(where: { $0.name == currentSymbol }) {
            candidates.insert(.init(name: currentSymbol, title: currentSymbol, keywords: "current imported"), at: 0)
        }
        let terms = normalized(search).split(whereSeparator: { $0.isWhitespace })
        guard !terms.isEmpty else { return candidates }
        return candidates.filter { option in
            let text = normalized("\(option.name) \(option.title) \(option.keywords)")
            return terms.allSatisfy { text.contains($0) }
        }
    }

    private static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }
}

struct ActionSymbolPicker: View {
    @Binding var symbol: String
    @State private var search = ""

    private var options: [ActionSymbolOption] {
        ActionSymbolCatalog.options(matching: search, currentSymbol: symbol)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: symbol)
                    .font(.title2)
                    .frame(width: 32, height: 32)
                    .accessibilityLabel("Selected icon: \(symbol)")
                TextField("SF Symbol", text: $symbol)
            }
            TextField("Search icons", text: $search)
                .accessibilityLabel("Search icons")
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 8) {
                    ForEach(options) { option in
                        Button { symbol = option.name } label: {
                            Image(systemName: option.name)
                                .frame(maxWidth: .infinity, minHeight: 28)
                                .foregroundStyle(symbol == option.name ? Color.accentColor : .secondary)
                                .background(symbol == option.name ? Color.accentColor.opacity(0.12) : .clear,
                                            in: RoundedRectangle(cornerRadius: 5))
                        }
                        .buttonStyle(.plain)
                        .help("\(option.title) — \(option.name)")
                        .accessibilityLabel("\(option.title): \(option.name)")
                        .accessibilityAddTraits(symbol == option.name ? .isSelected : [])
                    }
                }
                if options.isEmpty {
                    Text("No matching icons. Enter an SF Symbol name above.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(height: 172)
        }
    }
}
